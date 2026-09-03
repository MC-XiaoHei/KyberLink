const SPI1_BASE: usize = 0x40013000;
const CTLR1: *mut u32 = SPI1_BASE as *mut u32;
const CTLR2: *mut u32 = (SPI1_BASE + 0x04) as *mut u32;
const STATR: *mut u32 = (SPI1_BASE + 0x08) as *mut u32;
const DATAR: *mut u32 = (SPI1_BASE + 0x0C) as *mut u32;

const CTLR1_MSTR: u32 = 1 << 2;
const CTLR1_SPE: u32 = 1 << 6;
const CTLR1_BR_SHIFT: u32 = 3;
const STATR_TXE: u32 = 1 << 1;
const STATR_RXNE: u32 = 1 << 0;

pub struct SpiMaster {
    pub gpio_csn: *mut u32,
}

impl SpiMaster {
    pub fn new() -> Self {
        unsafe {
            CTLR1.write_volatile(CTLR1_MSTR | (6 << CTLR1_BR_SHIFT));
            CTLR2.write_volatile(0);
            STATR.read_volatile();
            CTLR1.write_volatile(CTLR1_MSTR | (6 << CTLR1_BR_SHIFT) | CTLR1_SPE);
        }
        SpiMaster {
            gpio_csn: core::ptr::null_mut(),
        }
    }

    unsafe fn xfer_byte(&self, b: u8) -> u8 {
        while STATR.read_volatile() & STATR_TXE == 0 {}
        DATAR.write_volatile(b as u32);
        while STATR.read_volatile() & STATR_RXNE == 0 {}
        DATAR.read_volatile() as u8
    }

    /// # Safety
    /// SPI bus must not be concurrently accessed.
    pub unsafe fn cs_low(&self) {
        if !self.gpio_csn.is_null() {
            self.gpio_csn.write_volatile(0);
        }
    }

    /// # Safety
    /// SPI bus must not be concurrently accessed.
    pub unsafe fn cs_high(&self) {
        if !self.gpio_csn.is_null() {
            self.gpio_csn.write_volatile(1);
        }
    }
}

impl Default for SpiMaster {
    fn default() -> Self {
        Self::new()
    }
}

impl crate::handshake_fsm::SpiBus for SpiMaster {
    unsafe fn write_reg(&self, addr: u8, data: u32) {
        self.cs_low();
        self.xfer_byte(addr & 0x7F);
        self.xfer_byte((data >> 24) as u8);
        self.xfer_byte((data >> 16) as u8);
        self.xfer_byte((data >> 8) as u8);
        self.xfer_byte(data as u8);
        self.cs_high();
    }

    unsafe fn read_reg(&self, addr: u8) -> u32 {
        self.cs_low();
        self.xfer_byte(0x80 | (addr & 0x7F));
        let mut v: u32 = 0;
        for _ in 0..4 {
            v = (v << 8) | (self.xfer_byte(0) as u32);
        }
        self.cs_high();
        v
    }
}
