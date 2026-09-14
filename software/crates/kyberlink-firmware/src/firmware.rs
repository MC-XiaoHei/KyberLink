#![allow(static_mut_refs)]

use ch32_hal::adc::{Adc, AdcChannel, AnyAdcChannel, Pga, SampleTime};
use ch32_hal::flash::{Blocking as FlashBlocking, Flash};
use ch32_hal::gpio::{Level, Output};
use ch32_hal::mode::Blocking;
use ch32_hal::peripherals::{ADC1, SPI1};
use ch32_hal::spi::{Config as SpiConfig, Spi};
use ch32_hal::time::Hertz;
use embassy_executor::Spawner;
use embassy_time::Timer;
use kyberlink_core::cfg_msg::{self, Binding};
use kyberlink_core::cfg_store::{CfgError, NorFlash};
use kyberlink_core::handshake_fsm::{write_data_plane, write_sa, Config, Fsm, FsmOutcome};
use kyberlink_crypto::entropy::{derive_kem_seeds, KemSeeds};
use kyberlink_crypto::handshake::RomIdentity;
use kyberlink_firmware::spi::SpiMaster;

const FLASH_BASE: u32 = 0x0800_0000;
const SA_SEQ_INIT: u32 = 1;

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

async fn provisioning_hold() -> ! {
    loop {
        Timer::after_millis(1000).await;
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

async fn run_forever(fsm: &'static mut Fsm<'static, SpiMaster>, initiator: bool) -> ! {
    loop {
        if let FsmOutcome::Sa(sa) = fsm.poll() {
            if let Some(spi) = unsafe { SPI.as_ref() } {
                write_sa(spi, &sa, initiator, SA_SEQ_INIT);
            }
        }
        Timer::after_millis(1).await;
    }
}

#[embassy_executor::main(entry = "ch32_hal::entry")]
async fn main(_spawner: Spawner) -> ! {
    let p = ch32_hal::init(clock_config());

    let mut spi_config = SpiConfig::default();
    spi_config.frequency = Hertz::khz(2250);
    let spi = Spi::new_blocking::<0>(p.SPI1, p.PA5, p.PA7, p.PA6, spi_config);
    let cs = Output::new(p.PA4, Level::High, Default::default());
    let mut flash = FlashPort(Flash::new_blocking(p.FLASH));

    let (binding, identity) = match load_device(&mut flash) {
        Ok(loaded) => loaded,
        Err(_) => provisioning_hold().await,
    };

    let mut adc = Adc::new(p.ADC1, Default::default());
    let mut chans = [
        p.PA0.degrade_adc(),
        p.PA1.degrade_adc(),
        p.PA2.degrade_adc(),
        p.PA3.degrade_adc(),
    ];
    let seeds = sample_entropy(&mut adc, &mut chans);

    let fsm = unsafe { start_fsm(spi, cs, &binding, &seeds, identity) };
    run_forever(fsm, binding.role_initiator).await
}
