use core::cell::RefCell;
use std::rc::Rc;
use std::vec::Vec;

use kyberlink_core::handshake_fsm::{
    SpiBus, REG_CTRL, REG_HSK_RX_DATA, REG_HSK_RX_LEN, REG_HSK_TX_DATA, REG_HSK_TX_LEN, REG_STATUS,
};

const CTRL_KEY_LOAD: u32 = 1 << 0;
const CTRL_HSK_SEND: u32 = 1 << 1;
const STATUS_RX_PENDING: u32 = 1 << 0;
const FIFO_WORDS: usize = 512;
const LENQ_DEPTH: usize = 16;
const REGS: usize = 0x80;

struct State {
    regs: [u32; REGS],
    tx: Vec<u32>,
    tx_len: usize,
    rx: Vec<u32>,
    lens: Vec<(usize, usize)>,
    outbox: Vec<Vec<u8>>,
    key_loads: u32,
}

impl Default for State {
    fn default() -> Self {
        State {
            regs: [0; REGS],
            tx: Vec::new(),
            tx_len: 0,
            rx: Vec::new(),
            lens: Vec::new(),
            outbox: Vec::new(),
            key_loads: 0,
        }
    }
}

#[derive(Clone)]
pub struct PeerBus {
    st: Rc<RefCell<State>>,
}

impl Default for PeerBus {
    fn default() -> Self {
        Self::new()
    }
}

impl PeerBus {
    pub fn new() -> Self {
        PeerBus {
            st: Rc::new(RefCell::new(State::default())),
        }
    }

    pub fn take_datagram(&self) -> Option<Vec<u8>> {
        let mut s = self.st.borrow_mut();
        if s.outbox.is_empty() {
            None
        } else {
            Some(s.outbox.remove(0))
        }
    }

    pub fn push_datagram(&self, payload: &[u8]) -> bool {
        let mut s = self.st.borrow_mut();
        let words = payload.len().div_ceil(4);
        if payload.len() < 8 || s.rx.len() + words > FIFO_WORDS || s.lens.len() >= LENQ_DEPTH {
            return false;
        }
        for chunk in payload.chunks(4) {
            let mut b = [0u8; 4];
            b[..chunk.len()].copy_from_slice(chunk);
            s.rx.push(u32::from_be_bytes(b));
        }
        s.lens.push((payload.len(), words));
        true
    }

    pub fn key_loads(&self) -> u32 {
        self.st.borrow().key_loads
    }

    pub fn rx_pending(&self) -> bool {
        !self.st.borrow().rx.is_empty()
    }

    pub fn rx_len(&self) -> u32 {
        self.st.borrow().lens.first().map_or(0, |e| e.0 as u32)
    }

    pub fn reg(&self, addr: u8) -> u32 {
        self.st.borrow().regs[(addr & 0x7F) as usize]
    }

    fn flush(&self) {
        let mut s = self.st.borrow_mut();
        if s.tx.is_empty() {
            return;
        }
        let declared = s.tx_len.min(s.tx.len() * 4);
        let mut bytes = Vec::with_capacity(s.tx.len() * 4);
        for w in s.tx.drain(..) {
            bytes.extend_from_slice(&w.to_be_bytes());
        }
        s.tx_len = 0;
        if declared >= 8 {
            s.outbox.push(bytes[..declared].to_vec());
        }
    }
}

impl SpiBus for PeerBus {
    fn write_reg(&self, addr: u8, data: u32) {
        match addr {
            REG_CTRL => {
                let mut s = self.st.borrow_mut();
                s.regs[REG_CTRL as usize] = data;
                if data & CTRL_KEY_LOAD != 0 {
                    s.key_loads += 1;
                }
                if data & CTRL_HSK_SEND == 0 {
                    return;
                }
                drop(s);
                self.flush();
            }
            REG_HSK_TX_LEN => {
                self.st.borrow_mut().tx_len = data as usize;
            }
            REG_HSK_TX_DATA => {
                self.st.borrow_mut().tx.push(data);
            }
            _ => {
                self.st.borrow_mut().regs[(addr & 0x7F) as usize] = data;
            }
        }
    }

    fn read_reg(&self, addr: u8) -> u32 {
        let mut s = self.st.borrow_mut();
        match addr {
            REG_STATUS => {
                if s.rx.is_empty() {
                    0
                } else {
                    STATUS_RX_PENDING
                }
            }
            REG_HSK_RX_LEN => s.lens.first().map_or(0, |e| e.0 as u32),
            REG_HSK_RX_DATA => {
                if s.rx.is_empty() {
                    return 0;
                }
                let w = s.rx.remove(0);
                if let Some(e) = s.lens.first_mut() {
                    e.1 -= 1;
                    if e.1 == 0 {
                        s.lens.remove(0);
                    }
                }
                w
            }
            _ => s.regs[(addr & 0x7F) as usize],
        }
    }
}
