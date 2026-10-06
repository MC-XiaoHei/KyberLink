use crate::bus::{MdioError, MdioPins};
use crate::frame;
use crate::regs::{ADDAR, DEVAD, REGCR};

const FN_ADDR: u16 = 0b00 << 14;
const FN_DATA: u16 = 0b01 << 14;

pub fn set_addr(pins: &impl MdioPins, phy: u8, addr: u16) -> Result<(), MdioError> {
    frame::write(pins, phy, REGCR as u8, FN_ADDR | DEVAD)?;
    frame::write(pins, phy, ADDAR as u8, addr)
}

pub fn read(pins: &impl MdioPins, phy: u8, addr: u16) -> Result<u16, MdioError> {
    set_addr(pins, phy, addr)?;
    frame::write(pins, phy, REGCR as u8, FN_DATA | DEVAD)?;
    frame::read(pins, phy, ADDAR as u8)
}

pub fn write(pins: &impl MdioPins, phy: u8, addr: u16, val: u16) -> Result<(), MdioError> {
    set_addr(pins, phy, addr)?;
    frame::write(pins, phy, REGCR as u8, FN_DATA | DEVAD)?;
    frame::write(pins, phy, ADDAR as u8, val)
}

pub fn modify(
    pins: &impl MdioPins,
    phy: u8,
    addr: u16,
    mask: u16,
    val: u16,
) -> Result<(), MdioError> {
    let cur = read(pins, phy, addr)?;
    let next = (cur & !mask) | (val & mask);
    if next != cur {
        write(pins, phy, addr, next)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::MockPhy;

    #[test]
    fn extended_write_then_read() {
        let phy = MockPhy::new();
        write(&phy, 0, 0x0086, 0x0077).unwrap();
        assert_eq!(phy.peek_ext(0x0086), 0x0077);
        assert_eq!(read(&phy, 0, 0x0086).unwrap(), 0x0077);
    }

    #[test]
    fn extended_access_reaches_both_halves() {
        let phy = MockPhy::new();
        write(&phy, 0, 0x0170, 0x0C50).unwrap();
        write(&phy, 0, 0x0032, 0x0003).unwrap();
        assert_eq!(read(&phy, 0, 0x0170).unwrap(), 0x0C50);
        assert_eq!(read(&phy, 0, 0x0032).unwrap(), 0x0003);
    }

    #[test]
    fn modify_preserves_untouched_bits() {
        let phy = MockPhy::new();
        write(&phy, 0, 0x0032, 0xFF61).unwrap();
        modify(&phy, 0, 0x0032, 0x0003, 0x0003).unwrap();
        assert_eq!(read(&phy, 0, 0x0032).unwrap(), 0xFF63);
    }

    #[test]
    fn modify_of_unchanged_value_writes_nothing() {
        let phy = MockPhy::new();
        write(&phy, 0, 0x0032, 0x0003).unwrap();
        modify(&phy, 0, 0x0032, 0x0003, 0x0003).unwrap();
        assert_eq!(read(&phy, 0, 0x0032).unwrap(), 0x0003);
    }

    #[test]
    fn missing_device_propagates() {
        let phy = MockPhy::new();
        phy.set_responding(false);
        assert_eq!(read(&phy, 0, 0x0086), Err(MdioError::NoResponse));
    }
}
