use crate::bus::MdioPins;
use crate::frame::{DATA_FIRST, PREAMBLE_BITS, TA_FIRST, TA_SECOND};
use crate::regs::{ADDAR, REGCR};
use core::cell::{Cell, RefCell};

const EXT_LEN: usize = 512;

pub struct MockPhy {
    regs: RefCell<[u16; 32]>,
    ext: RefCell<[u16; EXT_LEN]>,
    regcr: Cell<u16>,
    ext_addr: Cell<u16>,
    responds: Cell<bool>,
    master_drive: Cell<bool>,
    slave_out: RefCell<Option<bool>>,
    header: RefCell<u32>,
    data: RefCell<u32>,
    idx: Cell<usize>,
}

impl MockPhy {
    pub fn new() -> Self {
        Self {
            regs: RefCell::new([0u16; 32]),
            ext: RefCell::new([0u16; EXT_LEN]),
            regcr: Cell::new(0),
            ext_addr: Cell::new(0),
            responds: Cell::new(true),
            master_drive: Cell::new(true),
            slave_out: RefCell::new(None),
            header: RefCell::new(0),
            data: RefCell::new(0),
            idx: Cell::new(0),
        }
    }

    pub fn set_responding(&self, on: bool) {
        self.responds.set(on);
    }

    pub fn poke(&self, reg: u8, val: u16) {
        self.regs.borrow_mut()[reg as usize] = val;
    }

    pub fn peek(&self, reg: u8) -> u16 {
        self.regs.borrow()[reg as usize]
    }

    pub fn peek_ext(&self, addr: u16) -> u16 {
        self.ext.borrow()[addr as usize & (EXT_LEN - 1)]
    }

    fn ext_selected(&self) -> bool {
        self.regcr.get() >> 14 == 0b01
    }

    fn header_field(&self, shift: u32, mask: u32) -> u32 {
        *self.header.borrow() >> shift & mask
    }

    fn is_read(&self) -> bool {
        self.header_field(10, 0b11) == crate::frame::OP_READ as u32
    }

    fn addressed(&self) -> bool {
        self.responds.get() && self.header_field(5, 0x1F) == 0
    }

    fn reg_index(&self) -> usize {
        self.header_field(0, 0x1F) as usize
    }

    fn reg_value(&self, i: usize) -> u16 {
        if i == ADDAR as usize && self.ext_selected() {
            self.ext.borrow()[self.ext_addr.get() as usize & (EXT_LEN - 1)]
        } else {
            self.regs.borrow()[i]
        }
    }

    fn store(&self, i: usize, v: u16) {
        if i == REGCR as usize {
            self.regcr.set(v);
        } else if i == ADDAR as usize {
            if self.ext_selected() {
                self.ext.borrow_mut()[self.ext_addr.get() as usize & (EXT_LEN - 1)] = v;
            } else {
                self.ext_addr.set(v);
            }
        } else {
            self.regs.borrow_mut()[i] = v;
        }
    }
}

impl MdioPins for MockPhy {
    fn mdc(&self, level: bool) {
        if !level {
            return;
        }
        let i = self.idx.get();
        self.idx.set((i + 1) % 64);
        let d = self.master_drive.get();
        match i {
            0 => {
                self.slave_out.replace(None);
                self.header.replace(0);
                self.data.replace(0);
            }
            1..=PREAMBLE_BITS => {}
            _ if i < TA_FIRST => {
                let h = *self.header.borrow();
                self.header.replace((h << 1) | d as u32);
            }
            TA_FIRST => {}
            TA_SECOND => {
                self.slave_out
                    .replace(if self.is_read() && self.addressed() {
                        Some(false)
                    } else {
                        None
                    });
            }
            _ if i >= DATA_FIRST => {
                if self.is_read() {
                    self.slave_out.replace(if self.addressed() {
                        Some(self.reg_value(self.reg_index()) >> (63 - i) & 1 != 0)
                    } else {
                        None
                    });
                } else {
                    let acc = (*self.data.borrow() << 1) | d as u32;
                    self.data.replace(acc);
                    if i == 63 && self.addressed() {
                        self.store(self.reg_index(), acc as u16);
                    }
                }
            }
            _ => {}
        }
    }

    fn mdio(&self, level: bool) {
        self.master_drive.set(level);
    }

    fn mdio_level(&self) -> bool {
        match *self.slave_out.borrow() {
            Some(v) => v,
            None => self.master_drive.get(),
        }
    }
}
