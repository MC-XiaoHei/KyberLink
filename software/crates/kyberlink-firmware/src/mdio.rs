use ch32_hal::gpio::{Output, OutputOpenDrain};
use core::cell::RefCell;
use embassy_time::{block_for, Duration};
use kyberlink_core::dispatch::{PhyAccess, PhyDev};
use kyberlink_mdio::bus::{MdioError, MdioPins};
use kyberlink_mdio::dp83867::{self, BlinkRate, DelayNs, Dp83867, Led, LedSource, PhyPair};

const HALF_PERIOD_CYCLES: usize = 72;

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
    let start = riscv::register::mcycle::read();
    while riscv::register::mcycle::read().wrapping_sub(start) < HALF_PERIOD_CYCLES {
        core::hint::spin_loop();
    }
}

impl MdioPins for BitBangMdio<'_> {
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
        let mut pin = self.mdio.borrow_mut();
        if level {
            pin.set_high();
        } else {
            pin.set_low();
        }
    }

    fn mdio_level(&self) -> bool {
        self.mdio.borrow().is_high()
    }
}

pub fn init_pair<'d>(
    lan: BitBangMdio<'d>,
    wan: BitBangMdio<'d>,
    phy_rst: &mut Output<'d>,
) -> Result<PhyPair<BitBangMdio<'d>, BitBangMdio<'d>>, MdioError> {
    phy_rst.set_low();
    block_for(Duration::from_millis(1));
    phy_rst.set_high();
    block_for(Duration::from_millis(200));

    let lan_addr = dp83867::scan(&lan).ok_or(MdioError::NoResponse)?;
    let wan_addr = dp83867::scan(&wan).ok_or(MdioError::NoResponse)?;
    if lan_addr != wan_addr {
        return Err(MdioError::BadAddress);
    }

    let pair = PhyPair::new(lan, wan, lan_addr);
    for dev in [&pair.lan, &pair.wan] {
        if !dp83867::is_expected_id(dev.identify()?) {
            return Err(MdioError::NoResponse);
        }
        if dev.address_from_strap()? != dev.address() {
            return Err(MdioError::BadAddress);
        }
    }

    pair.set_rgmii_delay_both(DelayNs::Ns2_00, DelayNs::Ns2_00)?;
    pair.set_rgmii_clock_delay_both(true)?;
    pair.set_led_source_both(Led::Led0, LedSource::LinkBlinkActivity)?;
    pair.set_led_source_both(Led::Led1, LedSource::Link1000)?;
    for led in [Led::Led0, Led::Led1, Led::Led2, Led::Gpio] {
        pair.set_led_polarity_both(led, true)?;
    }
    pair.set_led_blink_rate_both(BlinkRate::Hz5)?;
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
