use crate::bus::{MdioError, MdioPins};
use crate::{ADDR_BITS, ADDR_MAX};

pub(crate) const PREAMBLE_BITS: usize = 32;

#[cfg(test)]
pub(crate) const HEADER_BITS: usize = 2 + 2 + 2 * ADDR_BITS as usize;
#[cfg(test)]
pub(crate) const TA_FIRST: usize = PREAMBLE_BITS + HEADER_BITS;
#[cfg(test)]
pub(crate) const TA_SECOND: usize = TA_FIRST + 1;
#[cfg(test)]
pub(crate) const DATA_FIRST: usize = TA_SECOND + 1;

pub(crate) const OP_READ: u8 = 0b10;
pub(crate) const OP_WRITE: u8 = 0b01;

fn tx_bit(pins: &impl MdioPins, bit: bool) {
    pins.mdio(bit);
    pins.mdc(true);
    pins.mdc(false);
}

fn rx_bit(pins: &impl MdioPins) -> bool {
    pins.mdc(true);
    let v = pins.mdio_level();
    pins.mdc(false);
    v
}

fn tx_addr(pins: &impl MdioPins, v: u8) {
    for i in (0..ADDR_BITS).rev() {
        tx_bit(pins, (v >> i) & 1 != 0);
    }
}

fn tx_header(pins: &impl MdioPins, op: u8) {
    for _ in 0..PREAMBLE_BITS {
        tx_bit(pins, true);
    }
    tx_bit(pins, false);
    tx_bit(pins, true);
    tx_bit(pins, op & 0b10 != 0);
    tx_bit(pins, op & 0b01 != 0);
}

fn check(phy: u8, reg: u8) -> Result<(), MdioError> {
    if phy > ADDR_MAX || reg > ADDR_MAX {
        return Err(MdioError::BadAddress);
    }
    Ok(())
}

pub fn read(pins: &impl MdioPins, phy: u8, reg: u8) -> Result<u16, MdioError> {
    check(phy, reg)?;
    tx_header(pins, OP_READ);
    tx_addr(pins, phy);
    tx_addr(pins, reg);
    pins.mdio(true);
    pins.mdc(true);
    pins.mdc(false);
    let mut v = 0u16;
    for _ in 0..16 {
        v = (v << 1) | rx_bit(pins) as u16;
    }
    pins.mdio(true);
    if v == u16::MAX {
        return Err(MdioError::NoResponse);
    }
    Ok(v)
}

pub fn write(pins: &impl MdioPins, phy: u8, reg: u8, val: u16) -> Result<(), MdioError> {
    check(phy, reg)?;
    tx_header(pins, OP_WRITE);
    tx_addr(pins, phy);
    tx_addr(pins, reg);
    tx_bit(pins, true);
    tx_bit(pins, false);
    for i in (0..16).rev() {
        tx_bit(pins, val >> i & 1 != 0);
    }
    pins.mdio(true);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::bus::mock::Recorder;
    use crate::test_support::MockPhy;

    #[test]
    fn write_frame_bit_layout() {
        let pins = Recorder::new();
        write(&pins, 0x00, 0x18, 0x615B).unwrap();
        let bits = pins.sampled_bits();
        assert_eq!(bits.len(), DATA_FIRST + 16);
        assert!(bits[..PREAMBLE_BITS].iter().all(|b| *b));
        assert_eq!(&bits[PREAMBLE_BITS..PREAMBLE_BITS + 2], &[false, true]);
        assert_eq!(&bits[PREAMBLE_BITS + 2..PREAMBLE_BITS + 4], &[false, true]);
        let addrs = &bits[PREAMBLE_BITS + 4..TA_FIRST];
        assert_eq!(&addrs[..ADDR_BITS as usize], &[false; 5]);
        let reg = addrs[ADDR_BITS as usize..]
            .iter()
            .fold(0u8, |a, b| (a << 1) | *b as u8);
        assert_eq!(reg, 0x18);
        assert_eq!(&bits[TA_FIRST..TA_SECOND], &[true]);
        assert_eq!(&bits[TA_SECOND..DATA_FIRST], &[false]);
        let decoded = bits[DATA_FIRST..]
            .iter()
            .fold(0u16, |a, b| (a << 1) | *b as u16);
        assert_eq!(decoded, 0x615B);
    }

    #[test]
    fn read_returns_register_value() {
        let phy = MockPhy::new();
        phy.poke(0x02, 0x2000);
        assert_eq!(read(&phy, 0x00, 0x02).unwrap(), 0x2000);
        assert_eq!(phy.peek(0x02), 0x2000);
    }

    #[test]
    fn read_reports_missing_device() {
        let phy = MockPhy::new();
        phy.set_responding(false);
        assert_eq!(read(&phy, 0x00, 0x02), Err(MdioError::NoResponse));
    }

    #[test]
    fn wrong_phy_address_looks_like_missing_device() {
        let phy = MockPhy::new();
        assert_eq!(read(&phy, 0x01, 0x02), Err(MdioError::NoResponse));
    }

    #[test]
    fn address_range_is_checked() {
        let pins = Recorder::new();
        assert_eq!(read(&pins, 32, 0), Err(MdioError::BadAddress));
        assert_eq!(write(&pins, 0, 32, 0), Err(MdioError::BadAddress));
    }

    #[test]
    fn write_then_read_round_trips() {
        let phy = MockPhy::new();
        write(&phy, 0x00, 0x18, 0x615B).unwrap();
        assert_eq!(read(&phy, 0x00, 0x18).unwrap(), 0x615B);
    }
}
