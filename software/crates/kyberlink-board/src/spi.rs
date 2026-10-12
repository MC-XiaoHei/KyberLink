use core::cell::RefCell;

use ch32_hal::gpio::Output;
use ch32_hal::mode::Blocking;
use ch32_hal::peripherals::SPI1;
use ch32_hal::spi::Spi;
use kyberlink_core::spi_frames::{read_frame, write_frame};

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

    fn xfer(&self, bytes: &mut [u8]) {
        let _ = self.spi.borrow_mut().blocking_transfer_in_place(bytes);
    }
}

impl kyberlink_core::handshake_fsm::SpiBus for SpiMaster {
    fn write_reg(&self, addr: u8, data: u32) {
        self.cs.borrow_mut().set_low();
        let mut buf = write_frame(addr, data);
        self.xfer(&mut buf);
        self.cs.borrow_mut().set_high();
    }

    fn read_reg(&self, addr: u8) -> u32 {
        self.cs.borrow_mut().set_low();
        let mut buf = read_frame(addr);
        self.xfer(&mut buf);
        self.cs.borrow_mut().set_high();
        u32::from_be_bytes([buf[1], buf[2], buf[3], buf[4]])
    }
}
