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
use static_cell::StaticCell;

use crate::pinmap::Pins;
use crate::usb;

const FLASH_BASE: u32 = 0x0800_0000;
const FLASH_LEN: u32 = 0x7_8000;
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
        debug_assert!(off as usize + len <= FLASH_LEN as usize);
        Some(unsafe { core::slice::from_raw_parts((FLASH_BASE + off) as *const u8, len) })
    }
}

static SPI: StaticCell<SpiMaster> = StaticCell::new();
static CONFIG: StaticCell<Config> = StaticCell::new();
static IDENTITY: StaticCell<RomIdentity> = StaticCell::new();
static FSM: StaticCell<Fsm<'static, SpiMaster>> = StaticCell::new();
static FPGA_RST: StaticCell<Output<'static>> = StaticCell::new();
static BINDING: StaticCell<Binding> = StaticCell::new();
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
    if !binding.is_configured() {
        return Err(CfgError::Value);
    }
    let identity = cfg_msg::load_identity(flash)?;
    Ok((binding, identity))
}

fn sample_entropy(adc: &mut Adc<'_, ADC1>, chans: &mut [AnyAdcChannel<ADC1>]) -> KemSeeds {
    let mut raw = [0u8; 256];
    let mut i = 0;
    for _ in 0..64 {
        for ch in chans.iter_mut() {
            let v = adc.convert(ch, SampleTime::CYCLES239_5, Pga::X1);
            raw[i] = (v as u8) ^ (riscv::register::mcycle::read() as u8);
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
            system_reset();
        }
    }
}

fn start_fsm(
    spi: Spi<'static, SPI1, Blocking>,
    cs: Output<'static>,
    binding: &Binding,
    seeds: &KemSeeds,
    identity: RomIdentity,
) -> &'static mut Fsm<'static, SpiMaster> {
    let identity = IDENTITY.init(identity);
    let bus: &'static SpiMaster = SPI.init(SpiMaster::new(spi, cs));
    write_data_plane(bus, binding);
    let cfg: &'static Config = CONFIG.init(Config::from_parts(binding, seeds, identity));
    FSM.init(Fsm::new(cfg, bus))
}

async fn run_forever(
    fsm: &'static mut Fsm<'static, SpiMaster>,
    rst: &'static mut Output<'static>,
    binding: &'static Binding,
    signal: &usb::ActionSignal,
) -> ! {
    let mut ticks = 0u32;
    let mut last = embassy_time::Instant::now();
    loop {
        let now = embassy_time::Instant::now();
        let elapsed = ((now - last).as_millis() as u32).max(1);
        last = now;
        if let FsmOutcome::Sa(sa) = fsm.poll_ms(elapsed) {
            write_sa(fsm.spi, &sa, binding.role_initiator, SA_SEQ_INIT);
        }
        if signal.signaled() {
            match signal.wait().await {
                Action::Rekey => {
                    let (cfg, spi) = (fsm.cfg, fsm.spi);
                    *fsm = Fsm::new(cfg, spi);
                }
                Action::Resume => write_data_plane(fsm.spi, binding),
                Action::Reboot => {
                    rst.set_low();
                    embassy_time::block_for(embassy_time::Duration::from_millis(10));
                    system_reset();
                }
                _ => {}
            }
        }
        ticks += 1;
        if ticks.is_multiple_of(ERR_POLL_TICKS) {
            ERR_FLAGS.store(fsm.spi.read_reg(REG_ERR) as u8, Ordering::Relaxed);
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

#[embassy_executor::main(entry = "ch32_hal::entry")]
async fn main(_spawner: Spawner) -> ! {
    let p = ch32_hal::init(clock_config());

    let mut pins = Pins {
        spi_sck: p.PA5,
        spi_mosi: p.PA7,
        spi_miso: p.PA6,
        spi_cs: p.PA4,
        fpga_rst: p.PA8,
        usb_dm: p.PA11,
        usb_dp: p.PA12,
        adc: [
            p.PA0.degrade_adc(),
            p.PA1.degrade_adc(),
            p.PA2.degrade_adc(),
            p.PA3.degrade_adc(),
        ],
    };

    let mut flash = FlashPort(Flash::new_blocking(p.FLASH));
    let (binding, identity) = match load_device(&mut flash) {
        Ok(loaded) => loaded,
        Err(_) => provisioning(&mut flash, p.USBD, pins.usb_dp, pins.usb_dm).await,
    };

    watchdog_start();

    let mut spi_config = SpiConfig::default();
    spi_config.frequency = Hertz::khz(2250);
    let spi = Spi::new_blocking::<0>(p.SPI1, pins.spi_sck, pins.spi_mosi, pins.spi_miso, spi_config);
    let cs = Output::new(pins.spi_cs, Level::High, Default::default());

    let mut adc = Adc::new(p.ADC1, Default::default());
    let seeds = sample_entropy(&mut adc, &mut pins.adc);

    let rst = FPGA_RST.init(Output::new(pins.fpga_rst, Level::High, Default::default()));
    embassy_time::block_for(embassy_time::Duration::from_millis(10));
    let binding: &'static Binding = BINDING.init(binding);
    let fsm = start_fsm(spi, cs, binding, &seeds, identity);
    let mut console = Console::new(Mode::Running);
    let signal = usb::ActionSignal::new();
    let usb = usb::serve(p.USBD, pins.usb_dp, pins.usb_dm, &mut console, &mut flash, &signal);
    match join(usb, run_forever(fsm, rst, binding, &signal)).await {}
}
