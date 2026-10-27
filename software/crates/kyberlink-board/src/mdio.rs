use ch32_hal::gpio::{Output, OutputOpenDrain};
use core::cell::RefCell;
use embassy_time::Timer;
use kyberlink_core::dispatch::{PhyAccess, PhyDev};
use kyberlink_mdio::bus::{MdioError, MdioPins as MdioBus};
use kyberlink_mdio::dp83867::{self, BlinkRate, DelayNs, Dp83867, Led, LedSource, PhyPair};

use crate::pinmap::{ActiveLow, MdioPins};

const HALF_PERIOD_TICKS: u32 = 720;

pub type PhysPair<'d> = PhyPair<BitBangMdio<'d>, BitBangMdio<'d>>;

pub struct MdcPin<'d> {
    pin: RefCell<Output<'d>>,
}

impl<'d> MdcPin<'d> {
    pub fn new(pin: Output<'d>) -> Self {
        Self {
            pin: RefCell::new(pin),
        }
    }
}

pub struct BitBangMdio<'d> {
    mdc: &'d MdcPin<'d>,
    mdio: RefCell<OutputOpenDrain<'d>>,
}

impl<'d> BitBangMdio<'d> {
    pub fn new(mdc: &'d MdcPin<'d>, mdio: OutputOpenDrain<'d>) -> Self {
        Self {
            mdc,
            mdio: RefCell::new(mdio),
        }
    }
}

fn delay_half_period() {
    riscv::asm::delay(HALF_PERIOD_TICKS);
}

impl MdioBus for BitBangMdio<'_> {
    fn mdc(&self, level: bool) {
        {
            let mut pin = self.mdc.pin.borrow_mut();
            if level {
                pin.set_high();
            } else {
                pin.set_low();
            }
        }
        delay_half_period();
    }

    fn mdio(&self, level: bool) {
        {
            let mut pin = self.mdio.borrow_mut();
            if level {
                pin.set_high();
            } else {
                pin.set_low();
            }
        }
        delay_half_period();
    }

    fn mdio_level(&self) -> bool {
        self.mdio.borrow().is_high()
    }
}

const PHY_RESET_HOLD_MS: u64 = 500;
const PHY_RESET_ATTEMPTS: u32 = 3;
const MDIO_READY_TIMEOUT_MS: u64 = 1000;
const MDIO_READY_INTERVAL_MS: u64 = 10;
const CONFIG_ATTEMPTS: u32 = 5;
const RGMIIDCTL: u16 = 0x0086;
const RGMII_DELAY_2NS: u16 = 0x0077;
const RGMII_DELAY_MASK: u16 = 0x00FF;

fn retry<T>(mut op: impl FnMut() -> Result<T, MdioError>) -> Result<T, MdioError> {
    let mut last = MdioError::NoResponse;
    for _ in 0..CONFIG_ATTEMPTS {
        match op() {
            Ok(value) => return Ok(value),
            Err(err) => last = err,
        }
    }
    Err(last)
}

async fn wait_for_pair(lan: &BitBangMdio<'_>, wan: &BitBangMdio<'_>) -> Result<u8, MdioError> {
    let mut waited = 0u64;
    loop {
        if let (Some(a), Some(b)) = (dp83867::scan(lan), dp83867::scan(wan)) {
            if a == b {
                return Ok(a);
            }
        }
        if waited >= MDIO_READY_TIMEOUT_MS {
            return Err(MdioError::NoResponse);
        }
        Timer::after_millis(MDIO_READY_INTERVAL_MS).await;
        waited += MDIO_READY_INTERVAL_MS;
    }
}

fn verify_rgmii_delay(pair: &PhysPair<'_>) -> Result<(), MdioError> {
    for dev in [&pair.lan, &pair.wan] {
        if retry(|| dev.read_reg(RGMIIDCTL))? & RGMII_DELAY_MASK != RGMII_DELAY_2NS {
            return Err(MdioError::NoResponse);
        }
    }
    Ok(())
}

fn verify_identity<'d>(
    lan: &BitBangMdio<'d>,
    wan: &BitBangMdio<'d>,
    addr: u8,
) -> Result<(), MdioError> {
    for bus in [lan, wan] {
        let dev = Dp83867::new(bus, addr);
        if !dp83867::is_expected_id(retry(|| dev.identify())?) {
            return Err(MdioError::NoResponse);
        }
        if retry(|| dev.address_from_strap())? != addr {
            return Err(MdioError::BadAddress);
        }
    }
    Ok(())
}

async fn power_on_pair<'d>(
    lan: &BitBangMdio<'d>,
    wan: &BitBangMdio<'d>,
    phy_reset: &mut ActiveLow<'d>,
) -> Result<u8, MdioError> {
    let mut last = MdioError::NoResponse;
    for _ in 0..PHY_RESET_ATTEMPTS {
        phy_reset.enable();
        Timer::after_millis(PHY_RESET_HOLD_MS).await;
        phy_reset.disable();
        let outcome = match wait_for_pair(lan, wan).await {
            Ok(addr) => verify_identity(lan, wan, addr).map(|()| addr),
            Err(err) => Err(err),
        };
        match outcome {
            Ok(addr) => return Ok(addr),
            Err(err) => last = err,
        }
    }
    Err(last)
}

pub async fn init_pair<'d>(
    lan: BitBangMdio<'d>,
    wan: BitBangMdio<'d>,
    phy_reset: &mut ActiveLow<'d>,
) -> Result<PhyPair<BitBangMdio<'d>, BitBangMdio<'d>>, MdioError> {
    let addr = power_on_pair(&lan, &wan, phy_reset).await?;
    let pair = PhyPair::new(lan, wan, addr);

    retry(|| pair.set_rgmii_delay_both(DelayNs::Ns2_00, DelayNs::Ns2_00))?;
    verify_rgmii_delay(&pair)?;
    retry(|| pair.set_rgmii_clock_delay_both(true))?;
    retry(|| pair.set_led_source_both(Led::Led0, LedSource::LinkBlinkActivity))?;
    retry(|| pair.set_led_source_both(Led::Led1, LedSource::Link1000))?;
    for led in [Led::Led0, Led::Led1, Led::Led2, Led::Gpio] {
        retry(|| pair.set_led_polarity_both(led, true))?;
    }
    retry(|| pair.set_led_blink_rate_both(BlinkRate::Hz5))?;
    Ok(pair)
}

pub struct PhyConsole<'a, 'd> {
    phys: Option<&'a PhysPair<'d>>,
}

impl<'a, 'd> PhyConsole<'a, 'd> {
    pub const fn new(phys: Option<&'a PhysPair<'d>>) -> Self {
        Self { phys }
    }

    fn pick(&self, dev: PhyDev) -> Option<&Dp83867<BitBangMdio<'d>>> {
        let pair = self.phys?;
        Some(match dev {
            PhyDev::Lan => &pair.lan,
            PhyDev::Wan => &pair.wan,
        })
    }
}

impl PhyAccess for PhyConsole<'_, '_> {
    fn read(&self, dev: PhyDev, addr: u16) -> Option<u16> {
        self.pick(dev)?.read_reg(addr).ok()
    }

    fn write(&self, dev: PhyDev, addr: u16, val: u16) -> bool {
        self.pick(dev)
            .is_some_and(|d| d.write_reg_raw(addr, val).is_ok())
    }
}

pub fn link_flags(phys: &PhysPair<'_>) -> u8 {
    match phys.link_status() {
        Ok((lan, wan)) => (lan as u8) << 5 | (wan as u8) << 6,
        Err(_) => 0,
    }
}

static MDC: static_cell::StaticCell<MdcPin<'static>> = static_cell::StaticCell::new();

pub fn open(pins: MdioPins) -> (BitBangMdio<'static>, BitBangMdio<'static>) {
    let mdc = MDC.init(MdcPin::new(Output::new(pins.mdc, ch32_hal::gpio::Level::Low, Default::default())));
    let lan = BitBangMdio::new(mdc, OutputOpenDrain::new(pins.lan, ch32_hal::gpio::Level::High, ch32_hal::gpio::Speed::Low));
    let wan = BitBangMdio::new(mdc, OutputOpenDrain::new(pins.wan, ch32_hal::gpio::Level::High, ch32_hal::gpio::Speed::Low));
    (lan, wan)
}
