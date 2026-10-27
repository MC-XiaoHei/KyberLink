use core::cell::UnsafeCell;
use core::mem::MaybeUninit;
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
    write_data_plane, write_sa, Config, Fsm, FsmOutcome, Role, SpiBus, REG_ERR, REG_SCRATCH,
};
use kyberlink_crypto::entropy::{derive_kem_seeds, KemSeeds};
use kyberlink_crypto::handshake::RomIdentity;
use static_cell::StaticCell;

const FLASH_BASE: u32 = 0x0800_0000;
const FLASH_LEN: u32 = 0x7_8000;
const SEQ_PROBE: u32 = 0x5A5A_5A5A;
const SA_SEQ_INIT: u32 = 1;
const ERR_POLL_TICKS: u32 = 100;

fn flash_window() -> &'static [u8; FLASH_LEN as usize] {
    // SAFETY: the flash window is memory-mapped at a fixed address and stays
    // valid for the entire program run.
    unsafe { &*(FLASH_BASE as *const [u8; FLASH_LEN as usize]) }
}

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

struct FsmSlot(UnsafeCell<MaybeUninit<Fsm<SpiMaster, RomIdentity>>>);

// SAFETY: `start_fsm` writes the cell once per boot, before anything reads it.
unsafe impl Sync for FsmSlot {}

static FSM: FsmSlot = FsmSlot(UnsafeCell::new(MaybeUninit::uninit()));
static BINDING: StaticCell<Binding> = StaticCell::new();
static ERR_FLAGS: AtomicU8 = AtomicU8::new(0);
static LINK_FLAGS: AtomicU8 = AtomicU8::new(0);

pub(crate) fn err_flags() -> u8 {
    ERR_FLAGS.load(Ordering::Relaxed)
        | LINK_FLAGS.load(Ordering::Relaxed)

}

fn ensure_hse() {
    fn rw(addr: u32) -> *mut u32 {
        addr as *mut u32
    }
    // SAFETY: RCC sits in a fixed peripheral window; only HSEON is touched here.
    unsafe {
        let ctlr = rw(RCC_CTLR).read_volatile();
        if ctlr & (1 << 16) == 0 {
            rw(RCC_CTLR).write_volatile(ctlr | (1 << 16));
        }
        for _ in 0..2_000_000 {
            if rw(RCC_CTLR).read_volatile() & (1 << 17) != 0 {
                return;
            }
        }
    }
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

const RCC_CTLR: u32 = 0x4002_1000;
const RCC_APB1PCENR: u32 = 0x4002_101C;
const RCC_BDCTLR: u32 = 0x4002_1020;
const PWR_CTLR: u32 = 0x4000_7000;
const RTC_CTLRL: u32 = 0x4000_2804;
const RTC_PSCH: u32 = 0x4000_2808;
const RTC_PSCL: u32 = 0x4000_280C;
const RTC_LSI_DIV: u32 = 39;

fn rtc_start() -> bool {
    fn rw(addr: u32) -> *mut u32 {
        addr as *mut u32
    }
    // SAFETY: RCC, PWR and RTC live in fixed peripheral windows; the sequence is the
    // reference manual's backup-domain enable order. The clock source is the internal
    // LSI so the entropy sampler never waits on an external crystal.
    unsafe {
        rw(RCC_CTLR).write_volatile(rw(RCC_CTLR).read_volatile() | 1);
        let mut lsi_ready = false;
        for _ in 0..200_000 {
            if rw(RCC_CTLR).read_volatile() & 2 != 0 {
                lsi_ready = true;
                break;
            }
        }
        if !lsi_ready {
            return false;
        }
        rw(RCC_APB1PCENR).write_volatile(rw(RCC_APB1PCENR).read_volatile() | (1 << 28) | (1 << 27));
        rw(PWR_CTLR).write_volatile(rw(PWR_CTLR).read_volatile() | (1 << 8));
        let mut bd = rw(RCC_BDCTLR).read_volatile();
        bd &= !(1 << 15);
        bd = (bd & !(3 << 8)) | (2 << 8);
        rw(RCC_BDCTLR).write_volatile(bd);
        riscv::asm::delay(200_000);
        rw(RCC_BDCTLR).write_volatile(bd | (1 << 15));
        riscv::asm::delay(200_000);

        let mut synced = false;
        for _ in 0..100_000 {
            if rw(RTC_CTLRL).read_volatile() & (1 << 3) != 0 {
                synced = true;
                break;
            }
        }
        if !synced {
            return false;
        }
        rw(RTC_CTLRL).write_volatile(rw(RTC_CTLRL).read_volatile() | (1 << 4));
        rw(RTC_PSCH).write_volatile(0);
        rw(RTC_PSCL).write_volatile(RTC_LSI_DIV);
        rw(RTC_CTLRL).write_volatile(rw(RTC_CTLRL).read_volatile() & !(1 << 4));
        for _ in 0..100_000 {
            if rw(RTC_CTLRL).read_volatile() & (1 << 5) != 0 {
                return true;
            }
        }
        false
    }
}

fn clock_entropy() -> [u8; 256] {
    let mut buf = [0u8; 256];
    let rtc_ok = rtc_start();
    let rtc = ch32_hal::pac::RTC;
    let mut i = 0;
    for _ in 0..128 {
        let d0 = if rtc_ok { rtc.divl().read().divl() } else { 0 };
        let t0 = riscv::register::mcycle::read();
        let mut d1 = d0;
        let mut spins = 0u32;
        while d1 == d0 && spins < 4_000 {
            d1 = if rtc_ok { rtc.divl().read().divl() } else { 0 };
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

#[inline(never)]
fn start_fsm(
    bus: SpiMaster,
    binding: &Binding,
    seeds: KemSeeds,
    identity: RomIdentity,
) -> &'static mut Fsm<SpiMaster, RomIdentity> {
    write_data_plane(&bus, binding);
    let cfg = Config::from_parts(binding, seeds, identity);
    // SAFETY: `start_fsm` runs once per boot and hands out the only reference.
    let slot = unsafe { (*FSM.0.get()).as_mut_ptr() };
    unsafe { &mut *Fsm::init_in_place(slot, cfg, bus) }
}

async fn run_forever(
    fsm: &'static mut Fsm<SpiMaster, RomIdentity>,
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
        if let FsmOutcome::Sa(sa) = fsm.poll_ms(elapsed, None) {
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
        Timer::after_millis(1).await;
    }
}

fn fix_uart_baud() {
    const RCC_CFGR0: u32 = 0x4002_1004;
    const USART1_BRR: u32 = 0x4001_3808;
    let cfgr0 = unsafe { (RCC_CFGR0 as *const u32).read_volatile() };
    if cfgr0 & (1 << 16) == 0 {
        unsafe { (USART1_BRR as *mut u32).write_volatile(120_000_000 / 115_200) };
    }
}

fn system_reset() -> ! {
    ch32_hal::pac::PFIC.sctlr().modify(|w| w.set_sysreset(true));
    loop {
        core::hint::spin_loop();
    }
}

pub type ActionSignal = Signal<CriticalSectionRawMutex, Action>;

fn uart_faulted() -> bool {
    let regs = ch32_hal::pac::USART1;
    let statr = regs.statr().read();
    let faulted = statr.ore() || statr.ne() || statr.fe() || statr.pe();
    if faulted {
        let _ = regs.datar().read();
    }
    faulted
}

fn poll_read(buf: &mut [u8]) -> usize {
    let regs = ch32_hal::pac::USART1;
    let mut n = 0;
    while n < buf.len() {
        if !regs.statr().read().rxne() {
            break;
        }
        buf[n] = regs.datar().read().dr() as u8;
        n += 1;
    }
    n
}

pub async fn serve<F: NorFlash, P: PhyAccess>(
    pins: uart::UartPins,
    console: &mut Console,
    flash: &mut F,
    phy: &P,
    signal: &ActionSignal,
) -> ! {
    let mut uart = uart::open_blocking(pins.usart, pins.rx, pins.tx);
    fix_uart_baud();
    let mut buf = [0u8; 64];
    loop {
        if uart_faulted() {
            console.abandon_line();
            continue;
        }
        let n = poll_read(&mut buf);
        if n == 0 {
            embassy_futures::yield_now().await;
            continue;
        }
        console.set_err(err_flags());
        for &byte in &buf[..n] {
            let action = console.push_with(byte, flash, phy);
            if let Some(reply) = console.take_reply() {
                let _ = uart.blocking_write(reply.as_bytes());
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
    ensure_hse();
    let p = ch32_hal::init(clock_config());
    for _ in 0..10 {
        Timer::after_millis(10).await;
    }

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
        phy_rst: p.PC9,
        phy_mdc: p.PC6,
        wan_mdio: p.PC7,
        lan_mdio: p.PC8,
    };

    let mut board = Board::new(pins.fpga_rst, pins.fpga_recfg, pins.phy_rst, pins.fpga_done);

    let mut flash = FlashPort(Flash::new_blocking(p.FLASH));
    let mut uart_pins = Some(uart::UartPins {
        usart: p.USART1,
        tx: pins.uart_tx,
        rx: pins.uart_rx,
        tx_dma: p.DMA1_CH4,
        rx_dma: p.DMA1_CH5,
    });
    let (binding, identity) = match load_device(&mut flash) {
        Ok(loaded) => loaded,
        Err(_) => provisioning(&mut flash, uart_pins.take().unwrap()).await,
    };

    let mut spi_config = SpiConfig::default();
    spi_config.frequency = Hertz::khz(500);
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
        bus.write_reg(REG_SCRATCH, SEQ_PROBE & 0xFF);
        bus.read_reg(REG_SCRATCH) & 0xFF == SEQ_PROBE & 0xFF
    })
    .await;
    let fpga_ready = up.as_ref().map(|o| o.ready).unwrap_or(false);
    if !fpga_ready {
        provisioning(&mut flash, uart_pins.take().unwrap()).await
    }
    let phys = up.as_ref().ok().map(|out| &out.phys);
    let binding: &'static Binding = BINDING.init(binding);
    let fsm = start_fsm(bus, binding, seeds, identity);
    let mut console = Console::new(Mode::Running);
    let signal = ActionSignal::new();
    let console_phy = mdio::PhyConsole::new(phys);
    let link = serve(
        uart_pins.take().unwrap(),
        &mut console,
        &mut flash,
        &console_phy,
        &signal,
    );
    match join(
        link,
        run_forever(fsm, &mut board, binding, phys, &signal),
    )
    .await {}
}
