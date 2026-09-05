/// 40-bit 帧编码（MSB first，bit39=R/W 标志，bit38..32=7 位地址，bit31..0=数据）。
/// 与硬件 spi_slave 以及测试端字节序列保持一致。
pub fn write_frame(addr: u8, data: u32) -> [u8; 5] {
    [
        addr & 0x7F,
        (data >> 24) as u8,
        (data >> 16) as u8,
        (data >> 8) as u8,
        data as u8,
    ]
}

/// 读帧：bit39=1 标志 + 7 位地址，其后 4 字节为从机回读槽位。
pub fn read_frame(addr: u8) -> [u8; 5] {
    [0x80 | (addr & 0x7F), 0, 0, 0, 0]
}

#[cfg(target_arch = "riscv32")]
mod hw {
    use core::cell::RefCell;

    use ch32_hal::gpio::Output;
    use ch32_hal::mode::Blocking;
    use ch32_hal::peripherals::SPI1;
    use ch32_hal::spi::Spi;

    use super::{read_frame, write_frame};

    pub struct SpiMaster {
        spi: RefCell<Spi<'static, SPI1, Blocking>>,
        cs: RefCell<Output<'static>>,
    }

    impl SpiMaster {
        pub fn new(spi: Spi<'static, SPI1, Blocking>, cs: Output<'static>) -> Self {
            SpiMaster {
                spi: RefCell::new(spi),
                cs: RefCell::new(cs),
            }
        }

        unsafe fn xfer(&self, bytes: &mut [u8]) {
            let _ = self.spi.borrow_mut().blocking_transfer_in_place(bytes);
        }
    }

    impl crate::handshake_fsm::SpiBus for SpiMaster {
        unsafe fn write_reg(&self, addr: u8, data: u32) {
            self.cs.borrow_mut().set_low();
            let mut buf = write_frame(addr, data);
            self.xfer(&mut buf);
            self.cs.borrow_mut().set_high();
        }

        unsafe fn read_reg(&self, addr: u8) -> u32 {
            self.cs.borrow_mut().set_low();
            let mut buf = [0u8; 9];
            buf[..5].copy_from_slice(&read_frame(addr));
            self.xfer(&mut buf);
            let v = u32::from_be_bytes([buf[5], buf[6], buf[7], buf[8]]);
            self.cs.borrow_mut().set_high();
            v
        }
    }
}

#[cfg(target_arch = "riscv32")]
pub use hw::SpiMaster;

#[cfg(not(target_arch = "riscv32"))]
pub struct SpiMaster;

#[cfg(not(target_arch = "riscv32"))]
impl crate::handshake_fsm::SpiBus for SpiMaster {
    unsafe fn write_reg(&self, _addr: u8, _data: u32) {}
    unsafe fn read_reg(&self, _addr: u8) -> u32 {
        0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn write_frame_matches_master_sequence() {
        let f = write_frame(0x14, 0xDEADBEEF);
        let word = (0x14u64 << 32) | 0xDEADBEEFu64;
        let expect: [u8; 5] = [
            (word >> 32) as u8,
            (word >> 24) as u8,
            (word >> 16) as u8,
            (word >> 8) as u8,
            word as u8,
        ];
        assert_eq!(f, expect);
        assert_eq!(f[0] & 0x80, 0, "write flag must be 0");
    }

    #[test]
    fn read_frame_sets_flag_and_7bit_addr() {
        let f = read_frame(0x34);
        assert_eq!(f[0], 0x80 | 0x34);
        let f2 = read_frame(0x00);
        assert_eq!(f2[0], 0x80);
        assert_eq!(f2[1..], [0, 0, 0, 0]);
    }

    #[test]
    fn frames_roundtrip_through_slave_bit_positions() {
        for (addr, data) in [(0x00u8, 0u32), (0x3C, 0x1234ABCD), (0x64, 0xFFFFFFFF)] {
            let f = write_frame(addr, data);
            assert_eq!(f[0] << 1 >> 1 & 0x7F, addr & 0x7F);
            assert_eq!(
                u32::from_be_bytes([f[1], f[2], f[3], f[4]]),
                data,
                "data must be big-endian after address"
            );
        }
    }
}
