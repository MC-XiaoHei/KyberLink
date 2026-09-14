use parking_lot::Mutex;

use kyberlink_core::handshake_fsm::SpiBus;

pub(crate) const RX_FIFO_WORDS: usize = 512;
pub(crate) const RX_LENQ_DEPTH: usize = 16;

#[derive(Default)]
struct QBusInner {
    outbox: Vec<u64>,
    status: u32,
    rx: Vec<u32>,
    lens: Vec<(usize, usize)>,
}

pub(crate) struct QBus {
    inner: Mutex<QBusInner>,
}

impl QBus {
    pub(crate) fn new() -> Self {
        QBus {
            inner: Mutex::new(QBusInner::default()),
        }
    }

    pub(crate) fn set_status(&self, value: u32) {
        self.inner.lock().status = value;
    }

    pub(crate) fn push_rx(&self, payload: &[u8]) {
        let words = payload.len().div_ceil(4);
        let mut s = self.inner.lock();
        if payload.len() < 8 || s.rx.len() + words > RX_FIFO_WORDS || s.lens.len() >= RX_LENQ_DEPTH
        {
            return;
        }
        for chunk in payload.chunks(4) {
            let mut b = [0u8; 4];
            b[..chunk.len()].copy_from_slice(chunk);
            s.rx.push(u32::from_be_bytes(b));
        }
        s.lens.push((payload.len(), words));
    }

    pub(crate) fn take_writes_n(&self, cap: usize) -> Vec<(u8, u32)> {
        let mut s = self.inner.lock();
        let n = cap.min(s.outbox.len());
        let rest = s.outbox.split_off(n);
        let head = core::mem::replace(&mut s.outbox, rest);
        head.into_iter()
            .map(|tx| (tx as u8, (tx >> 32) as u32))
            .collect()
    }
}

impl SpiBus for QBus {
    fn write_reg(&self, addr: u8, data: u32) {
        self.inner
            .lock()
            .outbox
            .push(((data as u64) << 32) | addr as u64);
    }

    fn read_reg(&self, addr: u8) -> u32 {
        let mut s = self.inner.lock();
        match addr {
            0x04 => s.status,
            0x34 => s.lens.first().map_or(0, |e| e.0 as u32),
            0x38 => {
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
            _ => 0,
        }
    }
}
