use core::cell::UnsafeCell;
use core::mem::MaybeUninit;
use core::sync::atomic::{AtomicU8, Ordering};

use ch32_hal::flash::{Blocking as FlashBlocking, Flash};
use embassy_executor::Spawner;
use embassy_futures::join::join;
use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::signal::Signal;
use embassy_time::{Instant, Timer};
use kyberlink_board::bringup;
use kyberlink_board::clock;
use kyberlink_board::mdio;
use kyberlink_board::pinmap::{self, Board, MdioPins};
use kyberlink_board::reset;
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
const SPI_KHZ: u32 = 500;
const SEQ_PROBE: u32 = 0x5A5A_5A5A;
const SA_SEQ_INIT: u32 = 1;
const ERR_POLL_TICKS: u32 = 100;
const ENTROPY_SAMPLES: usize = 128;
const RTC_SPINS: u32 = 4_000;

pub type ActionSignal = Signal<CriticalSectionRawMutex, Action>;

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
    ERR_FLAGS.load(Ordering::Relaxed) | LINK_FLAGS.load(Ordering::Relaxed)
}

#[embassy_executor::main(entry = "ch32_hal::entry")]
async fn main(_spawner: Spawner) -> ! {
    let p = ch32_hal::init(clock::config());
    Timer::after_millis(100).await;

    let parts = pinmap::take(p);
    let mut flash = FlashPort(parts.flash);
    let uart = uart::Port::open(parts.uart);
    let bus = SpiMaster::open(parts.spi, SPI_KHZ);

    let (binding, identity) = match load_device(&mut flash) {
        Ok(loaded) => loaded,
        Err(_) => provisioning(&mut flash, uart).await,
    };

    let mut board = parts.board;
    let outcome = bring_up(&mut board, parts.mdio, &bus).await;
    if !outcome.as_ref().is_some_and(|o| o.ready) {
        provisioning(&mut flash, uart).await
    }

    let phys = outcome.as_ref().map(|o| &o.phys);
    let binding: &'static Binding = BINDING.init(binding);
    let fsm = start_fsm(bus, binding, sample_entropy(), identity);
    let mut console = Console::new(Mode::Running);
    let phy = mdio::PhyConsole::new(phys);
    let signal = ActionSignal::new();

    match join(
        serve(uart, &mut console, &mut flash, &phy, &signal),
        run_forever(fsm, &mut board, binding, phys, &signal),
    )
    .await
    {}
}

async fn bring_up(
    board: &mut Board<'static>,
    pins: MdioPins,
    bus: &SpiMaster,
) -> Option<bringup::Outcome<'static>> {
    let (lan, wan) = mdio::open(pins);
    bringup::bring_up(board, lan, wan, || probe(bus)).await.ok()
}

fn probe(bus: &SpiMaster) -> bool {
    bus.write_reg(REG_SCRATCH, SEQ_PROBE & 0xFF);
    bus.read_reg(REG_SCRATCH) & 0xFF == SEQ_PROBE & 0xFF
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

fn flash_window() -> &'static [u8; FLASH_LEN as usize] {
    // SAFETY: the flash window is memory-mapped at a fixed address and stays
    // valid for the entire program run.
    unsafe { &*(FLASH_BASE as *const [u8; FLASH_LEN as usize]) }
}

fn sample_entropy() -> KemSeeds {
    let mut buf = [0u8; 268];
    buf[..256].copy_from_slice(&clock_entropy());
    buf[256..].copy_from_slice(&ch32_hal::signature::unique_id());
    derive_kem_seeds(&buf)
}

fn clock_entropy() -> [u8; 256] {
    let rtc_ready = clock::start_rtc();
    let rtc = ch32_hal::pac::RTC;
    let counter = || {
        if rtc_ready {
            rtc.divl().read().divl()
        } else {
            0
        }
    };
    let mut buf = [0u8; 256];
    for i in 0..ENTROPY_SAMPLES {
        let start = counter();
        let start_cycle = riscv::register::mcycle::read();
        let mut spins = 0;
        while counter() == start && spins < RTC_SPINS {
            spins += 1;
        }
        let delta = riscv::register::mcycle::read().wrapping_sub(start_cycle) as u16;
        buf[2 * i] = delta as u8;
        buf[2 * i + 1] = (delta >> 8) as u8;
    }
    buf
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
    binding: &Binding,
    phys: Option<&mdio::PhysPair<'_>>,
    signal: &ActionSignal,
) -> ! {
    let mut ticks = 0u32;
    let mut last = Instant::now();
    loop {
        let now = Instant::now();
        let elapsed = ((now - last).as_millis() as u32).max(1);
        last = now;

        if let FsmOutcome::Sa(sa) = fsm.poll_ms(elapsed, None) {
            write_sa(&fsm.spi, &sa, fsm.role == Role::Initiator, SA_SEQ_INIT);
        }
        if signal.signaled() {
            handle(signal.wait().await, fsm, board, binding).await;
        }
        ticks += 1;
        if ticks.is_multiple_of(ERR_POLL_TICKS) {
            publish_status(fsm, phys);
        }
        Timer::after_millis(1).await;
    }
}

async fn handle(
    action: Action,
    fsm: &mut Fsm<SpiMaster, RomIdentity>,
    board: &mut Board<'_>,
    binding: &Binding,
) {
    match action {
        Action::Rekey => fsm.reseed(sample_entropy()),
        Action::Resume => write_data_plane(&fsm.spi, binding),
        Action::Reboot => {
            board.fpga_reset.enable();
            Timer::after_millis(10).await;
            reset::system_reset();
        }
        Action::None | Action::Spill | Action::Halt => {}
    }
}

fn publish_status(
    fsm: &Fsm<SpiMaster, RomIdentity>,
    phys: Option<&mdio::PhysPair<'_>>,
) {
    ERR_FLAGS.store(fsm.spi.read_reg(REG_ERR) as u8, Ordering::Relaxed);
    LINK_FLAGS.store(phys.map_or(0, mdio::link_flags), Ordering::Relaxed);
}

async fn provisioning(flash: &mut FlashPort<'_>, uart: uart::Port) -> ! {
    let mut console = Console::new(Mode::Configure);
    let signal = ActionSignal::new();
    let phy = mdio::PhyConsole::new(None);
    match join(
        serve(uart, &mut console, flash, &phy, &signal),
        reboot_watch(&signal),
    )
    .await
    {}
}

async fn reboot_watch(signal: &ActionSignal) -> ! {
    loop {
        if let Action::Reboot = signal.wait().await {
            reset::system_reset();
        }
    }
}

async fn serve<F: NorFlash, P: PhyAccess>(
    mut uart: uart::Port,
    console: &mut Console,
    flash: &mut F,
    phy: &P,
    signal: &ActionSignal,
) -> ! {
    let mut buf = [0u8; 64];
    loop {
        let n = match uart.read(&mut buf) {
            uart::Read::Framing => {
                console.abandon_line();
                continue;
            }
            uart::Read::Idle => {
                embassy_futures::yield_now().await;
                continue;
            }
            uart::Read::Bytes(n) => n,
        };
        console.set_err(err_flags());
        for &byte in &buf[..n] {
            let action = console.push_with(byte, flash, phy);
            if let Some(reply) = console.take_reply() {
                uart.write(reply);
            }
            if matches!(action, Action::Rekey | Action::Reboot) {
                signal.signal(action);
            }
        }
    }
}
