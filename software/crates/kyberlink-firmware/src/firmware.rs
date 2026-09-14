#![allow(static_mut_refs)]

use core::sync::atomic::{AtomicU8, Ordering};

use ch32_hal::adc::{Adc, AdcChannel, AnyAdcChannel, Pga, SampleTime};
use ch32_hal::flash::{Blocking as FlashBlocking, Flash};
use ch32_hal::gpio::{Level, Output};
use ch32_hal::mode::Blocking;
use ch32_hal::peripherals::{ADC1, PA11, PA12, SPI1, USBD};
use ch32_hal::spi::{Config as SpiConfig, Spi};
use ch32_hal::time::Hertz;
use ch32_hal::Peri;
use embassy_executor::Spawner;
use embassy_futures::join::join;
use embassy_time::Timer;
use kyberlink_core::cfg_msg::{self, Binding};
use kyberlink_core::cfg_store::{CfgError, NorFlash};
use kyberlink_core::console::Console;
use kyberlink_core::dispatch::{Action, Mode};
use kyberlink_core::handshake_fsm::{
    write_data_plane, write_sa, Config, Fsm, FsmOutcome, SpiBus, REG_ERR,
};
use kyberlink_crypto::entropy::{derive_kem_seeds, KemSeeds};
use kyberlink_crypto::handshake::RomIdentity;
use kyberlink_firmware::spi::SpiMaster;

use crate::usb;

const FLASH_BASE: u32 = 0x0800_0000;
const SA_SEQ_INIT: u32 = 1;
const ERR_POLL_TICKS: u32 = 100;

const IWDG_BASE: u32 = 0x4000_3000;
const IWDG_UNLOCK: u32 = 0x5555;
const IWDG_START: u32 = 0xcccc;
const IWDG_FEED: u32 = 0xaaaa;
const IWDG_DIV64: u32 = 4;
const IWDG_PERIOD: u32 = 4095;

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

    fn map(&mut self, off: u32, len: usize) -> Option<&'static [u8]> {
        Some(unsafe { core::slice::from_raw_parts((FLASH_BASE + off) as *const u8, len) })
    }
}

static mut SPI: Option<SpiMaster> = None;
static mut CONFIG: core::mem::MaybeUninit<Config> = core::mem::MaybeUninit::uninit();
static mut FSM: core::mem::MaybeUninit<Fsm<SpiMaster>> = core::mem::MaybeUninit::uninit();
static mut IDENTITY: core::mem::MaybeUninit<RomIdentity> = core::mem::MaybeUninit::uninit();
static ERR_FLAGS: AtomicU8 = AtomicU8::new(0);

pub(crate) fn err_flags() -> u8 {
    ERR_FLAGS.load(Ordering::Relaxed)
}

fn watchdog_start() {
    unsafe {
        let ctlr = IWDG_BASE as *mut u32;
        ctlr.write_volatile(IWDG_UNLOCK);
        ((IWDG_BASE + 4) as *mut u32).write_volatile(IWDG_DIV64);
        ((IWDG_BASE + 8) as *mut u32).write_volatile(IWDG_PERIOD);
        ctlr.write_volatile(IWDG_START);
    }
}

fn watchdog_feed() {
    unsafe { (IWDG_BASE as *mut u32).write_volatile(IWDG_FEED) };
}

fn clock_config() -> ch32_hal::Config {
    ch32_hal::Config {
        rcc: ch32_hal::rcc::Config::SYSCLK_FREQ_144MHZ_HSI,
        ..Default::default()
    }
}

fn load_device(flash: &mut FlashPort) -> Result<(Binding, RomIdentity), CfgError> {
    let binding = Binding::load(flash)?;
    let identity = cfg_msg::load_identity(flash)?;
    Ok((binding, identity))
}

fn sample_entropy(adc: &mut Adc<'_, ADC1>, chans: &mut [AnyAdcChannel<ADC1>]) -> KemSeeds {
    let mut raw = [0u8; 256];
    let mut i = 0;
    for _ in 0..64 {
        for ch in chans.iter_mut() {
            let v = adc.convert(ch, SampleTime::CYCLES239_5, Pga::X1);
            let c: u32;
            unsafe { core::arch::asm!("csrr {}, mcycle", out(reg) c) };
            raw[i] = (v as u8) ^ (c as u8);
            i += 1;
        }
    }
    derive_kem_seeds(&raw)
}

async fn provisioning(
    flash: &mut FlashPort<'_>,
    usbd: Peri<'static, USBD>,
    dp: Peri<'static, PA12>,
    dm: Peri<'static, PA11>,
) -> ! {
    let mut console = Console::new(Mode::Configure);
    let signal = usb::ActionSignal::new();
    let usb = usb::serve(usbd, dp, dm, &mut console, flash, &signal);
    match join(usb, reboot_watch(&signal)).await {}
}

async fn reboot_watch(signal: &usb::ActionSignal) -> ! {
    loop {
        if let Action::Reboot = signal.wait().await {
            reset();
        }
    }
}

unsafe fn start_fsm(
    spi: Spi<'static, SPI1, Blocking>,
    cs: Output<'static>,
    binding: &Binding,
    seeds: &KemSeeds,
    identity: RomIdentity,
) -> &'static mut Fsm<'static, SpiMaster> {
    IDENTITY.write(identity);
    SPI = Some(SpiMaster::new(spi, cs));
    let spi_ref = SPI.as_ref().unwrap();
    write_data_plane(spi_ref, binding);
    CONFIG.write(Config::from_parts(
        binding,
        seeds,
        IDENTITY.assume_init_ref(),
    ));
    FSM.write(Fsm::new(CONFIG.assume_init_ref(), spi_ref));
    FSM.assume_init_mut()
}

async fn run_forever(
    fsm: &'static mut Fsm<'static, SpiMaster>,
    initiator: bool,
    signal: &usb::ActionSignal,
) -> ! {
    let mut ticks = 0u32;
    loop {
        if let FsmOutcome::Sa(sa) = fsm.poll() {
            if let Some(spi) = unsafe { SPI.as_ref() } {
                write_sa(spi, &sa, initiator, SA_SEQ_INIT);
            }
        }
        if signal.signaled() {
            match signal.wait().await {
                Action::Rekey => unsafe {
                    let cfg = CONFIG.assume_init_ref();
                    if let Some(spi) = SPI.as_ref() {
                        *fsm = Fsm::new(cfg, spi);
                    }
                },
                Action::Reboot => reset(),
                _ => {}
            }
        }
        ticks += 1;
        if ticks.is_multiple_of(ERR_POLL_TICKS) {
            if let Some(spi) = unsafe { SPI.as_ref() } {
                ERR_FLAGS.store(spi.read_reg(REG_ERR) as u8, Ordering::Relaxed);
            }
        }
        watchdog_feed();
        Timer::after_millis(1).await;
    }
}

fn reset() -> ! {
    ch32_hal::pac::PFIC.sctlr().modify(|w| w.set_sysreset(true));
    loop {
        core::hint::spin_loop();
    }
}

#[embassy_executor::main(entry = "ch32_hal::entry")]
async fn main(_spawner: Spawner) -> ! {
    let p = ch32_hal::init(clock_config());

    let mut flash = FlashPort(Flash::new_blocking(p.FLASH));
    let (binding, identity) = match load_device(&mut flash) {
        Ok(loaded) => loaded,
        Err(_) => provisioning(&mut flash, p.USBD, p.PA12, p.PA11).await,
    };

    watchdog_start();

    let mut spi_config = SpiConfig::default();
    spi_config.frequency = Hertz::khz(2250);
    let spi = Spi::new_blocking::<0>(p.SPI1, p.PA5, p.PA7, p.PA6, spi_config);
    let cs = Output::new(p.PA4, Level::High, Default::default());

    let mut adc = Adc::new(p.ADC1, Default::default());
    let mut chans = [
        p.PA0.degrade_adc(),
        p.PA1.degrade_adc(),
        p.PA2.degrade_adc(),
        p.PA3.degrade_adc(),
    ];
    let seeds = sample_entropy(&mut adc, &mut chans);

    let fsm = unsafe { start_fsm(spi, cs, &binding, &seeds, identity) };
    let mut console = Console::new(Mode::Running);
    let signal = usb::ActionSignal::new();
    let usb = usb::serve(p.USBD, p.PA12, p.PA11, &mut console, &mut flash, &signal);
    match join(usb, run_forever(fsm, binding.role_initiator, &signal)).await {}
}
