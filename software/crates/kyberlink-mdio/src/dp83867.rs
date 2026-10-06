use crate::bus::{MdioError, MdioPins};
use crate::clause45;
use crate::frame;
use crate::regs::{self, PHY_ID, PHY_ID_MASK};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Speed {
    Mbit10,
    Mbit100,
    Mbit1000,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Duplex {
    Half,
    Full,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DelayNs {
    Ns0_25 = 0,
    Ns0_50 = 1,
    Ns0_75 = 2,
    Ns1_00 = 3,
    Ns1_25 = 4,
    Ns1_50 = 5,
    Ns1_75 = 6,
    Ns2_00 = 7,
    Ns2_25 = 8,
    Ns2_50 = 9,
    Ns2_75 = 10,
    Ns3_00 = 11,
    Ns3_25 = 12,
    Ns3_50 = 13,
    Ns3_75 = 14,
    Ns4_00 = 15,
}

impl DelayNs {
    pub const fn code(self) -> u16 {
        self as u16
    }

    pub const fn from_code(c: u16) -> Self {
        match c & 0xF {
            0 => Self::Ns0_25,
            1 => Self::Ns0_50,
            2 => Self::Ns0_75,
            3 => Self::Ns1_00,
            4 => Self::Ns1_25,
            5 => Self::Ns1_50,
            6 => Self::Ns1_75,
            7 => Self::Ns2_00,
            8 => Self::Ns2_25,
            9 => Self::Ns2_50,
            10 => Self::Ns2_75,
            11 => Self::Ns3_00,
            12 => Self::Ns3_25,
            13 => Self::Ns3_50,
            14 => Self::Ns3_75,
            _ => Self::Ns4_00,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Led {
    Led0,
    Led1,
    Led2,
    Gpio,
}

impl Led {
    const fn shift(self) -> u16 {
        match self {
            Self::Led0 => 0,
            Self::Led1 => 4,
            Self::Led2 => 8,
            Self::Gpio => 12,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LedSource {
    LinkUp,
    Activity,
    TxActivity,
    RxActivity,
    Collision,
    Link1000,
    Link100Base,
    Link10Base,
    Link10_100,
    Link100_1000,
    FullDuplex,
    LinkBlinkActivity,
    RxTxError,
    RxError,
}

impl LedSource {
    pub const fn code(self) -> u16 {
        match self {
            Self::LinkUp => 0b0000,
            Self::Activity => 0b0001,
            Self::TxActivity => 0b0010,
            Self::RxActivity => 0b0011,
            Self::Collision => 0b0100,
            Self::Link1000 => 0b0101,
            Self::Link100Base => 0b0110,
            Self::Link10Base => 0b0111,
            Self::Link10_100 => 0b1000,
            Self::Link100_1000 => 0b1001,
            Self::FullDuplex => 0b1010,
            Self::LinkBlinkActivity => 0b1011,
            Self::RxTxError => 0b1101,
            Self::RxError => 0b1110,
        }
    }

    pub const fn from_code(c: u16) -> Option<Self> {
        Some(match c & 0xF {
            0b0000 => Self::LinkUp,
            0b0001 => Self::Activity,
            0b0010 => Self::TxActivity,
            0b0011 => Self::RxActivity,
            0b0100 => Self::Collision,
            0b0101 => Self::Link1000,
            0b0110 => Self::Link100Base,
            0b0111 => Self::Link10Base,
            0b1000 => Self::Link10_100,
            0b1001 => Self::Link100_1000,
            0b1010 => Self::FullDuplex,
            0b1011 => Self::LinkBlinkActivity,
            0b1101 => Self::RxTxError,
            0b1110 => Self::RxError,
            _ => return None,
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LedForce {
    Normal,
    ForceOn,
    ForceOff,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BlinkRate {
    Hz20 = 0b00,
    Hz10 = 0b01,
    Hz5 = 0b10,
    Hz2 = 0b11,
}

pub struct Dp83867<B> {
    bus: B,
    phy: u8,
}

impl<B: MdioPins> Dp83867<B> {
    pub const fn new(bus: B, phy: u8) -> Self {
        Self { bus, phy }
    }

    pub fn bus(&self) -> &B {
        &self.bus
    }

    pub fn address(&self) -> u8 {
        self.phy
    }

    fn rd(&self, reg: u16) -> Result<u16, MdioError> {
        frame::read(&self.bus, self.phy, reg as u8)
    }

    fn wr(&self, reg: u16, val: u16) -> Result<(), MdioError> {
        frame::write(&self.bus, self.phy, reg as u8, val)
    }

    fn rd_ext(&self, addr: u16) -> Result<u16, MdioError> {
        clause45::read(&self.bus, self.phy, addr)
    }

    fn modify_ext(&self, addr: u16, mask: u16, val: u16) -> Result<(), MdioError> {
        clause45::modify(&self.bus, self.phy, addr, mask, val)
    }

    fn modify(&self, reg: u16, mask: u16, val: u16) -> Result<(), MdioError> {
        let cur = self.rd(reg)?;
        let next = (cur & !mask) | (val & mask);
        if next != cur {
            self.wr(reg, next)?;
        }
        Ok(())
    }

    pub fn identify(&self) -> Result<u32, MdioError> {
        let hi = self.rd(regs::PHYIDR1)? as u32;
        let lo = self.rd(regs::PHYIDR2)? as u32;
        Ok((hi << 16) | lo)
    }

    pub fn soft_reset(&self) -> Result<(), MdioError> {
        self.wr(regs::BMCR, regs::bmcr::RESET)
    }

    pub fn reset_done(&self) -> Result<bool, MdioError> {
        Ok(self.rd(regs::BMCR)? & regs::bmcr::RESET == 0)
    }

    pub fn link_up(&self) -> Result<bool, MdioError> {
        Ok(self.rd(regs::BMSR)? & regs::bmsr::LINK_UP != 0)
    }

    pub fn autoneg_done(&self) -> Result<bool, MdioError> {
        Ok(self.rd(regs::BMSR)? & regs::bmsr::AUTONEG_DONE != 0)
    }

    pub fn speed(&self) -> Result<Speed, MdioError> {
        Ok(match self.rd(regs::PHYSTS)? & regs::physts::SPEED_MASK {
            regs::physts::SPEED_10 => Speed::Mbit10,
            regs::physts::SPEED_100 => Speed::Mbit100,
            _ => Speed::Mbit1000,
        })
    }

    pub fn duplex(&self) -> Result<Duplex, MdioError> {
        Ok(if self.rd(regs::PHYSTS)? & regs::physts::DUPLEX != 0 {
            Duplex::Full
        } else {
            Duplex::Half
        })
    }

    pub fn autoneg_enable(&self, on: bool) -> Result<(), MdioError> {
        self.modify(
            regs::BMCR,
            regs::bmcr::AUTONEG_EN,
            if on { regs::bmcr::AUTONEG_EN } else { 0 },
        )
    }

    pub fn restart_autoneg(&self) -> Result<(), MdioError> {
        self.wr(regs::BMCR, regs::bmcr::AUTONEG_EN | regs::bmcr::RESTART_AUTONEG)
    }

    pub fn set_led_source(&self, led: Led, src: LedSource) -> Result<(), MdioError> {
        self.modify(
            regs::LEDCR1,
            regs::ledcr1::SEL_MASK << led.shift(),
            src.code() << led.shift(),
        )
    }

    pub fn led_source(&self, led: Led) -> Result<Option<LedSource>, MdioError> {
        let raw = (self.rd(regs::LEDCR1)? >> led.shift()) & regs::ledcr1::SEL_MASK;
        Ok(LedSource::from_code(raw))
    }

    pub fn set_led_force(&self, led: Led, force: LedForce) -> Result<(), MdioError> {
        let bits = match force {
            LedForce::Normal => 0,
            LedForce::ForceOff => regs::ledcr2::DRV_EN,
            LedForce::ForceOn => regs::ledcr2::DRV_EN | regs::ledcr2::DRV_VAL,
        };
        self.modify(
            regs::LEDCR2,
            regs::ledcr2::FIELD_MASK << led.shift(),
            bits << led.shift(),
        )
    }

    pub fn set_led_polarity(&self, led: Led, active_high: bool) -> Result<(), MdioError> {
        self.modify(
            regs::LEDCR2,
            regs::ledcr2::POLARITY << led.shift(),
            if active_high {
                regs::ledcr2::POLARITY << led.shift()
            } else {
                0
            },
        )
    }

    pub fn set_led_blink_rate(&self, rate: BlinkRate) -> Result<(), MdioError> {
        self.modify(regs::LEDCR3, regs::ledcr3::BLINK_RATE, rate as u16)
    }

    pub fn set_rgmii_delay(&self, tx: DelayNs, rx: DelayNs) -> Result<(), MdioError> {
        let mask = regs::rgmiidctl::TX_MASK | regs::rgmiidctl::RX_MASK;
        let val = tx.code() << regs::rgmiidctl::TX_SHIFT | rx.code() << regs::rgmiidctl::RX_SHIFT;
        self.modify_ext(regs::RGMIIDCTL, mask, val)
    }

    pub fn rgmii_delay(&self) -> Result<(DelayNs, DelayNs), MdioError> {
        let v = self.rd_ext(regs::RGMIIDCTL)?;
        Ok((
            DelayNs::from_code(v >> regs::rgmiidctl::TX_SHIFT),
            DelayNs::from_code(v >> regs::rgmiidctl::RX_SHIFT),
        ))
    }

    pub fn set_rgmii_clock_delay(&self, shifted: bool) -> Result<(), MdioError> {
        self.modify_ext(
            regs::RGMIICTL,
            regs::rgmiictl::CLK_DELAY_MASK,
            if shifted {
                regs::rgmiictl::CLK_DELAY_MASK
            } else {
                0
            },
        )
    }

    pub fn set_rgmii_enable(&self, on: bool) -> Result<(), MdioError> {
        self.modify_ext(
            regs::RGMIICTL,
            regs::rgmiictl::ENABLE,
            if on { regs::rgmiictl::ENABLE } else { 0 },
        )
    }

    pub fn strap_status1(&self) -> Result<u16, MdioError> {
        self.rd_ext(regs::STRAP_STS1)
    }

    pub fn strap_status2(&self) -> Result<u16, MdioError> {
        self.rd_ext(regs::STRAP_STS2)
    }

    pub fn address_from_strap(&self) -> Result<u8, MdioError> {
        Ok((self.strap_status1()? & regs::strap_sts1::PHY_ADD) as u8)
    }

    pub fn read_reg(&self, addr: u16) -> Result<u16, MdioError> {
        if addr <= regs::DIRECT_MAX {
            self.rd(addr)
        } else {
            self.rd_ext(addr)
        }
    }

    pub fn write_reg_raw(&self, addr: u16, val: u16) -> Result<(), MdioError> {
        if addr <= regs::DIRECT_MAX {
            self.wr(addr, val)
        } else {
            clause45::write(&self.bus, self.phy, addr, val)
        }
    }
}

pub fn is_expected_id(id: u32) -> bool {
    id & PHY_ID_MASK == PHY_ID & PHY_ID_MASK
}

pub fn scan<B: MdioPins>(bus: &B) -> Option<u8> {
    for addr in 0..=crate::ADDR_MAX {
        let dev = Dp83867::new(bus, addr);
        if let Ok(id) = dev.identify() {
            if is_expected_id(id) {
                return Some(addr);
            }
        }
    }
    None
}

pub struct PhyPair<A, B> {
    pub lan: Dp83867<A>,
    pub wan: Dp83867<B>,
}

impl<A: MdioPins, B: MdioPins> PhyPair<A, B> {
    pub const fn new(lan: A, wan: B, phy: u8) -> Self {
        Self {
            lan: Dp83867::new(lan, phy),
            wan: Dp83867::new(wan, phy),
        }
    }

    pub fn identify_both(&self) -> Result<(u32, u32), MdioError> {
        Ok((self.lan.identify()?, self.wan.identify()?))
    }

    pub fn link_status(&self) -> Result<(bool, bool), MdioError> {
        Ok((self.lan.link_up()?, self.wan.link_up()?))
    }

    pub fn set_rgmii_delay_both(&self, tx: DelayNs, rx: DelayNs) -> Result<(), MdioError> {
        self.lan.set_rgmii_delay(tx, rx)?;
        self.wan.set_rgmii_delay(tx, rx)
    }

    pub fn set_rgmii_clock_delay_both(&self, shifted: bool) -> Result<(), MdioError> {
        self.lan.set_rgmii_clock_delay(shifted)?;
        self.wan.set_rgmii_clock_delay(shifted)
    }

    pub fn set_led_source_both(&self, led: Led, src: LedSource) -> Result<(), MdioError> {
        self.lan.set_led_source(led, src)?;
        self.wan.set_led_source(led, src)
    }

    pub fn set_led_force_both(&self, led: Led, force: LedForce) -> Result<(), MdioError> {
        self.lan.set_led_force(led, force)?;
        self.wan.set_led_force(led, force)
    }

    pub fn set_led_polarity_both(&self, led: Led, active_high: bool) -> Result<(), MdioError> {
        self.lan.set_led_polarity(led, active_high)?;
        self.wan.set_led_polarity(led, active_high)
    }

    pub fn set_led_blink_rate_both(&self, rate: BlinkRate) -> Result<(), MdioError> {
        self.lan.set_led_blink_rate(rate)?;
        self.wan.set_led_blink_rate(rate)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::MockPhy;

    fn dev(phy: &MockPhy) -> Dp83867<&MockPhy> {
        Dp83867::new(phy, 0)
    }

    #[test]
    fn identify_reads_both_halves() {
        let phy = MockPhy::new();
        phy.poke(regs::PHYIDR1 as u8, 0x2000);
        phy.poke(regs::PHYIDR2 as u8, 0xA231);
        let id = dev(&phy).identify().unwrap();
        assert_eq!(id, PHY_ID);
        assert!(is_expected_id(id));
    }

    #[test]
    fn identify_rejects_other_vendor() {
        let phy = MockPhy::new();
        phy.poke(regs::PHYIDR1 as u8, 0x001C);
        phy.poke(regs::PHYIDR2 as u8, 0xC916);
        assert!(!is_expected_id(dev(&phy).identify().unwrap()));
    }

    #[test]
    fn link_and_speed_decode() {
        let phy = MockPhy::new();
        phy.poke(regs::BMSR as u8, regs::bmsr::LINK_UP | regs::bmsr::AUTONEG_DONE);
        phy.poke(regs::PHYSTS as u8, regs::physts::SPEED_1000 | regs::physts::DUPLEX);
        let d = dev(&phy);
        assert!(d.link_up().unwrap());
        assert!(d.autoneg_done().unwrap());
        assert_eq!(d.speed().unwrap(), Speed::Mbit1000);
        assert_eq!(d.duplex().unwrap(), Duplex::Full);
    }

    #[test]
    fn led_source_round_trips() {
        let phy = MockPhy::new();
        phy.poke(regs::LEDCR1 as u8, 0x615B);
        let d = dev(&phy);
        assert_eq!(
            d.led_source(Led::Led0).unwrap(),
            Some(LedSource::LinkBlinkActivity)
        );
        assert_eq!(d.led_source(Led::Led1).unwrap(), Some(LedSource::Link1000));
        d.set_led_source(Led::Led0, LedSource::LinkUp).unwrap();
        assert_eq!(phy.peek(regs::LEDCR1 as u8), 0x6150);
    }

    #[test]
    fn led_source_reserved_codes_are_none() {
        assert_eq!(LedSource::from_code(0b1100), None);
        assert_eq!(LedSource::from_code(0b1111), None);
    }

    #[test]
    fn led_force_sets_three_bits_only() {
        let phy = MockPhy::new();
        let d = dev(&phy);
        d.set_led_force(Led::Led0, LedForce::ForceOn).unwrap();
        assert_eq!(phy.peek(regs::LEDCR2 as u8) & 0x7, 0b011);
        d.set_led_force(Led::Led0, LedForce::ForceOff).unwrap();
        assert_eq!(phy.peek(regs::LEDCR2 as u8) & 0x7, 0b001);
        d.set_led_force(Led::Led0, LedForce::Normal).unwrap();
        assert_eq!(phy.peek(regs::LEDCR2 as u8) & 0x7, 0);
    }

    #[test]
    fn rgmii_delay_round_trips() {
        let phy = MockPhy::new();
        let d = dev(&phy);
        d.set_rgmii_delay(DelayNs::Ns2_00, DelayNs::Ns2_00).unwrap();
        assert_eq!(phy.peek_ext(regs::RGMIIDCTL), 0x0077);
        assert_eq!(d.rgmii_delay().unwrap(), (DelayNs::Ns2_00, DelayNs::Ns2_00));
    }

    #[test]
    fn rgmii_delay_preserves_reserved_upper_byte() {
        let phy = MockPhy::new();
        clause45::write(&phy, 0, regs::RGMIIDCTL, 0xFF00).unwrap();
        dev(&phy)
            .set_rgmii_delay(DelayNs::Ns1_00, DelayNs::Ns0_50)
            .unwrap();
        assert_eq!(phy.peek_ext(regs::RGMIIDCTL), 0xFF31);
    }

    #[test]
    fn scan_finds_the_responding_phy() {
        let phy = MockPhy::new();
        phy.poke(regs::PHYIDR1 as u8, 0x2000);
        phy.poke(regs::PHYIDR2 as u8, 0xA231);
        assert_eq!(scan(&phy), Some(0));

        let silent = MockPhy::new();
        assert_eq!(scan(&silent), None);
    }

    #[test]
    fn pair_applies_to_both() {
        let lan = MockPhy::new();
        let wan = MockPhy::new();
        let pair = PhyPair::new(&lan, &wan, 0);
        pair.set_rgmii_delay_both(DelayNs::Ns2_00, DelayNs::Ns2_00)
            .unwrap();
        assert_eq!(lan.peek_ext(regs::RGMIIDCTL), 0x0077);
        assert_eq!(wan.peek_ext(regs::RGMIIDCTL), 0x0077);
    }

    #[test]
    fn rgmii_clock_delay_toggles_both_bits() {
        let phy = MockPhy::new();
        let d = dev(&phy);
        d.set_rgmii_clock_delay(false).unwrap();
        assert_eq!(d.rd_ext(regs::RGMIICTL).unwrap() & 0x3, 0);
        d.set_rgmii_clock_delay(true).unwrap();
        assert_eq!(d.rd_ext(regs::RGMIICTL).unwrap() & 0x3, 0x3);
    }

    #[test]
    fn strap_address_reads_low_nibble() {
        let phy = MockPhy::new();
        clause45::write(&phy, 0, regs::STRAP_STS1, 0x1FF0).unwrap();
        assert_eq!(dev(&phy).address_from_strap().unwrap(), 0);
    }

    #[test]
    fn delay_code_boundaries() {
        assert_eq!(DelayNs::Ns0_25.code(), 0);
        assert_eq!(DelayNs::Ns4_00.code(), 15);
        assert_eq!(DelayNs::from_code(0), DelayNs::Ns0_25);
        assert_eq!(DelayNs::from_code(15), DelayNs::Ns4_00);
    }

    #[test]
    fn reset_requests_and_clears() {
        let phy = MockPhy::new();
        let d = dev(&phy);
        assert!(d.reset_done().unwrap());
        d.soft_reset().unwrap();
        phy.poke(regs::BMCR as u8, regs::bmcr::RESET);
        assert!(!d.reset_done().unwrap());
        phy.poke(regs::BMCR as u8, 0);
        assert!(d.reset_done().unwrap());
    }
}
