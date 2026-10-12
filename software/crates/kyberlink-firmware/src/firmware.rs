use core::sync::atomic::{AtomicU8, Ordering};

use ch32_hal::flash::{Blocking as FlashBlocking, Flash};
use ch32_hal::gpio::{Level, Output, OutputOpenDrain, Speed};
use ch32_hal::spi::{Config as SpiConfig, Spi};
use ch32_hal::time::Hertz;
use embassy_executor::Spawner;
use embassy_futures::join::join;
use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::signal::Signal;
use embassy_time::Timer;
use kyberlink_board::bringup;
use kyberlink_board::mdio;
use kyberlink_board::pinmap::{self, Board, Pins};
use kyberlink_board::spi::SpiMaster;
use kyberlink_board::uart;
use kyberlink_core::cfg_msg::{self, Binding, IDENTITY_LEN};
use kyberlink_core::cfg_store::{self, CfgError, NorFlash, IDENTITY_BASE, MAGIC_IDENTITY};
use kyberlink_core::console::Console;
use kyberlink_core::dispatch::{Action, Mode, PhyAccess};
use kyberlink_core::handshake_fsm::{
    write_data_plane, write_sa, Config, Fsm, FsmOutcome, Role, SpiBus, REG_ERR,
};
use kyberlink_crypto::entropy::{derive_kem_seeds, KemSeeds};
use kyberlink_crypto::handshake::RomIdentity;
use kyberlink_crypto::mldsa_internal::VerifyPrecomp;
use static_cell::{ConstStaticCell, StaticCell};

const FLASH_BASE: u32 = 0x0800_0000;
const FLASH_LEN: u32 = 0x7_8000;
const REG_SEQ: u8 = 0x74;
const SEQ_PROBE: u32 = 0x5A5A_5A5A;
const SA_SEQ_INIT: u32 = 1;
const ERR_POLL_TICKS: u32 = 100;

fn flash_window() -> &'static [u8; FLASH_LEN as usize] {
    // SAFETY: the flash window is memory-mapped at a fixed address and stays
    // valid for the entire program run.
    unsafe { &*(FLASH_BASE as *const [u8; FLASH_LEN as usize]) }
}

const IWDG_CTLR: u32 = 0x4000_3000;
const IWDG_PSCR: u32 = IWDG_CTLR + 4;
const IWDG_RLR: u32 = IWDG_CTLR + 8;
const IWDG_CTLR_UNLOCK: u32 = 0x5555;
const IWDG_CTLR_START: u32 = 0xcccc;
const IWDG_CTLR_FEED: u32 = 0xaaaa;
const IWDG_PSCR_DIV64: u32 = 4;
const IWDG_RLR_PERIOD: u32 = 4095;

struct FlashPort<'d>(Flash<'d, FlashBlocking>);

impl NorFlash for FlashPort<'_> {
    fn read(&mut self, off: u32, buf: &mut [u8]) -> Result<(), CfgError> {
        self.0.blocking_read(off, buf).map_err(|_| CfgError::Flash)
    }

    fn write_page(&mut self, off: u32, page: &[u8]) -> Result<(), CfgError> {
        self.0
            .blocking_write(off, page)
            .map_err(|_| CfgError::Flash)
    }

    fn erase(&mut self, off: u32, len: u32) -> Result<(), CfgError> {
        self.0
            .blocking_erase(off, off + len)
            .map_err(|_| CfgError::Flash)
    }
}

static FSM: StaticCell<Fsm<SpiMaster, RomIdentity>> = StaticCell::new();
static PC: ConstStaticCell<VerifyPrecomp> = ConstStaticCell::new(VerifyPrecomp::const_zeroed());
static BINDING: StaticCell<Binding> = StaticCell::new();
static ERR_FLAGS: AtomicU8 = AtomicU8::new(0);
static LINK_FLAGS: AtomicU8 = AtomicU8::new(0);

pub(crate) fn err_flags() -> u8 {
    ERR_FLAGS.load(Ordering::Relaxed) | LINK_FLAGS.load(Ordering::Relaxed)
}

fn watchdog_start() {
    // SAFETY: IWDG occupies a fixed peripheral window that stays mapped for the
    // whole run; the writes follow the reference manual unlock/load/start order.
    unsafe {
        (IWDG_CTLR as *mut u32).write_volatile(IWDG_CTLR_UNLOCK);
        (IWDG_PSCR as *mut u32).write_volatile(IWDG_PSCR_DIV64);
        (IWDG_RLR as *mut u32).write_volatile(IWDG_RLR_PERIOD);
        (IWDG_CTLR as *mut u32).write_volatile(IWDG_CTLR_START);
    }
}

fn watchdog_feed() {
    // SAFETY: same fixed peripheral window as watchdog_start.
    unsafe { (IWDG_CTLR as *mut u32).write_volatile(IWDG_CTLR_FEED) };
}

fn clock_config() -> ch32_hal::Config {
    pinmap::clock_config()
}

fn load_device(flash: &mut FlashPort) -> Result<(Binding, RomIdentity), CfgError> {
    let binding = Binding::load(flash)?;
    if !binding.is_configured() {
        return Err(CfgError::Value);
    }
    cfg_store::verify(flash, IDENTITY_BASE, &MAGIC_IDENTITY, IDENTITY_LEN as u16)?;
    let base = IDENTITY_BASE as usize + cfg_store::HEADER_LEN;
    let payload = flash_window()
        .get(base..base + IDENTITY_LEN)
        .ok_or(CfgError::Unmapped)?;
    Ok((binding, cfg_msg::identity_from_payload(payload)?))
}

fn clock_entropy() -> [u8; 256] {
    let mut buf = [0u8; 256];
    let rtc = ch32_hal::pac::RTC;
    let mut i = 0;
    for _ in 0..128 {
        let d0 = rtc.divl().read().divl();
        let t0 = riscv::register::mcycle::read();
        let mut d1 = d0;
        let mut spins = 0u32;
        while d1 == d0 && spins < 200_000 {
            d1 = rtc.divl().read().divl();
            spins += 1;
        }
        let t1 = riscv::register::mcycle::read();
        let dt = t1.wrapping_sub(t0) as u16;
        buf[i] = (dt & 0xFF) as u8;
        buf[i + 1] = (dt >> 8) as u8;
        i += 2;
    }
    buf
}

fn sample_entropy() -> KemSeeds {
    let mut buf = [0u8; 268];
    buf[..256].copy_from_slice(&clock_entropy());
    buf[256..].copy_from_slice(&ch32_hal::signature::unique_id());
    derive_kem_seeds(&buf)
}

async fn provisioning(flash: &mut FlashPort<'_>, pins: uart::UartPins) -> ! {
    let mut console = Console::new(Mode::Configure);
    let signal = ActionSignal::new();
    let phy = mdio::PhyConsole::new(None);
    let link = serve(pins, &mut console, flash, &phy, &signal);
    match join(link, reboot_watch(&signal)).await {}
}

async fn reboot_watch(signal: &ActionSignal) -> ! {
    loop {
        if let Action::Reboot = signal.wait().await {
            system_reset();
        }
    }
}

fn start_fsm(
    bus: SpiMaster,
    binding: &Binding,
    seeds: KemSeeds,
    identity: RomIdentity,
) -> &'static mut Fsm<SpiMaster, RomIdentity> {
    write_data_plane(&bus, binding);
    FSM.init(Fsm::new(Config::from_parts(binding, seeds, identity), bus))
}

async fn run_forever(
    fsm: &'static mut Fsm<SpiMaster, RomIdentity>,
    pc: &'static mut VerifyPrecomp,
    board: &mut Board<'_>,
    binding: &'static Binding,
    phys: Option<&mdio::PhysPair<'_>>,
    signal: &ActionSignal,
) -> ! {
    let mut ticks = 0u32;
    let mut last = embassy_time::Instant::now();
    loop {
        let now = embassy_time::Instant::now();
        let elapsed = ((now - last).as_millis() as u32).max(1);
        last = now;
        if let FsmOutcome::Sa(sa) = fsm.poll_ms(elapsed, pc) {
            write_sa(&fsm.spi, &sa, fsm.role == Role::Initiator, SA_SEQ_INIT);
        }
        if signal.signaled() {
            match signal.wait().await {
                Action::Rekey => fsm.reseed(sample_entropy()),
                Action::Resume => write_data_plane(&fsm.spi, binding),
                Action::Reboot => {
                    board.fpga_reset.enable();
                    Timer::after_millis(10).await;
                    system_reset();
                }
                _ => {}
            }
        }
        ticks += 1;
        if ticks.is_multiple_of(ERR_POLL_TICKS) {
            ERR_FLAGS.store(fsm.spi.read_reg(REG_ERR) as u8, Ordering::Relaxed);
            LINK_FLAGS.store(phys.map_or(0, mdio::link_flags), Ordering::Relaxed);
        }
        watchdog_feed();
        Timer::after_millis(1).await;
    }
}

fn system_reset() -> ! {
    ch32_hal::pac::PFIC.sctlr().modify(|w| w.set_sysreset(true));
    loop {
        core::hint::spin_loop();
    }
}

pub type ActionSignal = Signal<CriticalSectionRawMutex, Action>;

pub async fn serve<F: NorFlash, P: PhyAccess>(
    pins: uart::UartPins,
    console: &mut Console,
    flash: &mut F,
    phy: &P,
    signal: &ActionSignal,
) -> ! {
    let (mut tx, mut rx) = uart::open(pins).split();
    let mut buf = [0u8; 64];
    loop {
        let n = match rx.read_until_idle(&mut buf).await {
            Ok(n) => n,
            Err(_) => continue,
        };
        console.set_err(err_flags());
        for &byte in &buf[..n] {
            let action = console.push_with(byte, flash, phy);
            if let Some(reply) = console.take_reply() {
                let _ = tx.write(reply.as_bytes()).await;
            }
            match action {
                Action::Rekey | Action::Reboot => signal.signal(action),
                _ => {}
            }
        }
    }
}

#[embassy_executor::main(entry = "ch32_hal::entry")]
async fn main(_spawner: Spawner) -> ! {
    let p = ch32_hal::init(clock_config());

    let pins = Pins {
        spi_sck: p.PA5,
        spi_mosi: p.PA7,
        spi_miso: p.PA6,
        spi_cs: p.PA4,
        fpga_rst: p.PA1,
        fpga_recfg: p.PA2,
        fpga_done: p.PA3,
        uart_tx: p.PB6,
        uart_rx: p.PB7,
        phy_rst: p.PA11,
        phy_mdc: p.PC6,
        wan_mdio: p.PC8,
        lan_mdio: p.PC9,
    };

    let mut flash = FlashPort(Flash::new_blocking(p.FLASH));
    let (binding, identity) = match load_device(&mut flash) {
        Ok(loaded) => loaded,
        Err(_) => {
            provisioning(
                &mut flash,
                uart::UartPins {
                    usart: p.USART1,
                    tx: pins.uart_tx,
                    rx: pins.uart_rx,
                    tx_dma: p.DMA1_CH4,
                    rx_dma: p.DMA1_CH5,
                },
            )
            .await
        }
    };

    watchdog_start();

    let mut spi_config = SpiConfig::default();
    spi_config.frequency = Hertz::khz(2250);
    let spi = Spi::new_blocking::<0>(
        p.SPI1,
        pins.spi_sck,
        pins.spi_mosi,
        pins.spi_miso,
        spi_config,
    );
    let cs = Output::new(pins.spi_cs, Level::High, Default::default());
    let bus = SpiMaster::new(spi, cs);

    let seeds = sample_entropy();

    let mut board = Board::new(pins.fpga_rst, pins.fpga_recfg, pins.phy_rst, pins.fpga_done);
    let mdc = mdio::MdcPin::new(Output::new(pins.phy_mdc, Level::Low, Default::default()));
    let lan_bus = mdio::BitBangMdio::new(
        &mdc,
        OutputOpenDrain::new(pins.lan_mdio, Level::High, Speed::Low),
    );
    let wan_bus = mdio::BitBangMdio::new(
        &mdc,
        OutputOpenDrain::new(pins.wan_mdio, Level::High, Speed::Low),
    );

    let up = bringup::bring_up(&mut board, lan_bus, wan_bus, || {
        bus.write_reg(REG_SEQ, SEQ_PROBE);
        bus.read_reg(REG_SEQ) == SEQ_PROBE
    })
    .await;
    let phys = up.as_ref().ok().map(|out| &out.phys);
    let binding: &'static Binding = BINDING.init(binding);
    let fsm = start_fsm(bus, binding, seeds, identity);
    let pc = PC.take();
    let mut console = Console::new(Mode::Running);
    let signal = ActionSignal::new();
    let console_phy = mdio::PhyConsole::new(phys);
    let link = serve(
        uart::UartPins {
            usart: p.USART1,
            tx: pins.uart_tx,
            rx: pins.uart_rx,
            tx_dma: p.DMA1_CH4,
            rx_dma: p.DMA1_CH5,
        },
        &mut console,
        &mut flash,
        &console_phy,
        &signal,
    );
    match join(
        link,
        run_forever(fsm, pc, &mut board, binding, phys, &signal),
    )
    .await {}
}
