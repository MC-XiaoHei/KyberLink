#![allow(unsafe_code)]
#![allow(clippy::missing_safety_doc)]

use parking_lot::Mutex;

use crate::handshake_fsm::{write_sa, Config, Fsm, FsmOutcome, SpiBus};
use kyberlink_crypto::handshake as hs;
use kyberlink_crypto::mldsa_internal::{keygen_internal, sign_precomp_new_into};

const VK_LEN: usize = 32;

pub struct FsmHandle {
    fsm: Mutex<Fsm<'static, QBus>>,
    cfg: &'static Config,
    qbus: &'static QBus,
}

pub const RX_FIFO_WORDS: usize = 512;
pub const RX_LENQ_DEPTH: usize = 16;
pub const TX_FIFO_WORDS: usize = 512;
/// UDP 发送引擎每字 4 拍出队（8 bit/拍）。
pub const DRAIN_CYCLES_PER_WORD: u32 = 4;

#[derive(Default)]
struct QBusInner {
    outbox: Vec<u64>,
    rx: Vec<u32>,
    lens: Vec<(usize, usize)>,
    tx: Vec<u32>,
    tx_len: u16,
    tx_len_r: u16,
    tx_dump: bool,
    tx_dump_left: u32,
    tx_phase: u32,
}

/// 仿真里的 FPGA 侧 SPI 从机模型，语义对齐 spi_regs.v。
pub struct QBus {
    inner: Mutex<QBusInner>,
}

impl QBus {
    fn new() -> Self {
        QBus {
            inner: Mutex::new(QBusInner::default()),
        }
    }

    fn push_rx(&self, payload: &[u8]) {
        let words = payload.len().div_ceil(4);
        let mut w = Vec::with_capacity(words);
        for chunk in payload.chunks(4) {
            let mut b = [0u8; 4];
            b[..chunk.len()].copy_from_slice(chunk);
            w.push(u32::from_be_bytes(b));
        }
        let mut s = self.inner.lock();
        if payload.len() < 8 || s.rx.len() + words > RX_FIFO_WORDS || s.lens.len() >= RX_LENQ_DEPTH
        {
            return;
        }
        s.rx.extend_from_slice(&w);
        s.lens.push((payload.len(), words));
    }

    fn tick(&self, n: u32) {
        let mut s = self.inner.lock();
        s.tx_phase += n;
        let mut words = s.tx_phase / DRAIN_CYCLES_PER_WORD;
        s.tx_phase %= DRAIN_CYCLES_PER_WORD;
        while words > 0 && !s.tx.is_empty() {
            s.tx.remove(0);
            words -= 1;
            if s.tx_dump_left > 0 {
                s.tx_dump_left -= 1;
            }
        }
        if s.tx_dump_left == 0 {
            s.tx_dump = false;
        }
    }

    fn take_writes_n(&self, cap: usize) -> Vec<(u8, u32)> {
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
    unsafe fn write_reg(&self, addr: u8, data: u32) {
        {
            let mut s = self.inner.lock();
            match addr {
                0x3C => s.tx_len = data as u16,
                0x40 => {
                    if s.tx.len() < TX_FIFO_WORDS {
                        s.tx.push(data);
                    }
                }
                0x00 if data & (1 << 1) != 0 => {
                    s.tx_len_r = s.tx_len;
                    s.tx_dump = true;
                    s.tx_dump_left = (s.tx_len_r as usize).div_ceil(4) as u32;
                }
                _ => {}
            }
            s.outbox.push(((data as u64) << 32) | addr as u64);
        }
    }

    unsafe fn read_reg(&self, addr: u8) -> u32 {
        let mut s = self.inner.lock();
        match addr {
            0x04 => {
                let p = if s.lens.is_empty() { 0 } else { 1 };
                let b = if !s.tx.is_empty() || s.tx_dump { 2 } else { 0 };
                p | b
            }
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

impl SpiBus for &QBus {
    unsafe fn write_reg(&self, addr: u8, data: u32) {
        QBus::write_reg(self, addr, data)
    }
    unsafe fn read_reg(&self, addr: u8) -> u32 {
        QBus::read_reg(self, addr)
    }
}

struct TestIdentity {
    vk: [u8; hs::VK_LEN],
    kk: [u8; hs::KK_LEN],
    tr: [u8; hs::TR_LEN],
    spc: hs::SignPrecomp,
}

impl hs::Identity for TestIdentity {
    fn vk(&self) -> &[u8; hs::VK_LEN] {
        &self.vk
    }
    fn kk(&self) -> &[u8; hs::KK_LEN] {
        &self.kk
    }
    fn tr(&self) -> &[u8; hs::TR_LEN] {
        &self.tr
    }
    fn spc(&self) -> &hs::SignPrecomp {
        &self.spc
    }
}

fn identity_from_seed(seed: &[u8]) -> &'static TestIdentity {
    let (vk, sk) = keygen_internal(seed.try_into().unwrap());
    let mut spc = hs::SignPrecomp::default();
    sign_precomp_new_into(&mut spc, &sk);
    Box::leak(Box::new(TestIdentity {
        vk,
        kk: hs::kk_of(&sk),
        tr: hs::tr_of(&sk),
        spc,
    }))
}

fn fsm_create(
    role: u32,
    peer_fp: &[u8],
    seed_identity: &[u8],
    seed_d: &[u8],
    seed_z: &[u8],
    nonce: &[u8],
) -> *mut FsmHandle {
    let id = identity_from_seed(seed_identity);
    let fp = hs::fingerprint(&id.vk);
    let peer_fp_arr: [u8; 32] = if peer_fp.iter().any(|&x| x != 0) {
        peer_fp.try_into().unwrap()
    } else {
        fp
    };
    let cfg: &'static Config = Box::leak(Box::new(Config {
        role_initiator: role == 0,
        peer_fp: peer_fp_arr,
        seed_kem_d: seed_d.try_into().unwrap(),
        seed_kem_z: seed_z.try_into().unwrap(),
        nonce: nonce.try_into().unwrap(),
        identity: id,
    }));
    let qbus: &'static QBus = Box::leak(Box::new(QBus::new()));
    let fsm = Fsm::new(cfg, qbus);
    Box::into_raw(Box::new(FsmHandle {
        fsm: Mutex::new(fsm),
        cfg,
        qbus,
    }))
}

#[no_mangle]
pub unsafe extern "C" fn kyb_fsm_new(
    role: u32,
    peer_fp: *const u8,
    seed_identity: *const u8,
    seed_d: *const u8,
    seed_z: *const u8,
    nonce: *const u8,
) -> *mut FsmHandle {
    unsafe {
        fsm_create(
            role,
            std::slice::from_raw_parts(peer_fp, 32),
            std::slice::from_raw_parts(seed_identity, 32),
            std::slice::from_raw_parts(seed_d, 32),
            std::slice::from_raw_parts(seed_z, 32),
            std::slice::from_raw_parts(nonce, 32),
        )
    }
}

#[no_mangle]
pub unsafe extern "C" fn kyb_fsm_free(h: *mut FsmHandle) {
    if !h.is_null() {
        unsafe {
            drop(Box::from_raw(h));
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn kyb_qbus_tick(h: *mut FsmHandle, n: u32) {
    unsafe {
        let h = &*h;
        h.qbus.tick(n);
    }
}

#[no_mangle]
pub unsafe extern "C" fn kyb_fsm_poll(h: *mut FsmHandle) -> u32 {
    unsafe {
        let h = &*h;
        let outcome = h.fsm.lock().poll();
        match outcome {
            FsmOutcome::Sa(sa) => {
                write_sa(&h.qbus, &sa, h.cfg.role_initiator, 1);
                1
            }
            FsmOutcome::Wait => 0,
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn kyb_fsm_take_writes(h: *mut FsmHandle, out: *mut u64, cap: u32) -> u32 {
    unsafe {
        let h = &*h;
        let writes = h.qbus.take_writes_n(cap as usize);
        let n = writes.len();
        for (i, (addr, data)) in writes.iter().enumerate() {
            *out.add(i) = ((*data as u64) << 32) | *addr as u64;
        }
        n as u32
    }
}

#[no_mangle]
pub unsafe extern "C" fn kyb_fsm_push_rx(h: *mut FsmHandle, data: *const u8, len: u32) {
    unsafe {
        let h = &*h;
        h.qbus
            .push_rx(std::slice::from_raw_parts(data, len as usize));
    }
}

#[no_mangle]
pub unsafe extern "C" fn kyb_fsm_fingerprint(seed: *const u8, out: *mut u8) {
    unsafe {
        let (vk, _) = keygen_internal(std::slice::from_raw_parts(seed, 32).try_into().unwrap());
        let fp = hs::fingerprint(&vk);
        std::ptr::copy_nonoverlapping(fp.as_ptr(), out, VK_LEN);
    }
}
