#![allow(unsafe_code)]

use parking_lot::Mutex;

use crate::handshake_fsm::{write_sa, Config, Fsm, FsmOutcome, SpiBus};
use kyberlink_crypto::handshake as hs;
use kyberlink_crypto::mldsa_internal::{keygen_internal, sign_precomp_new_into};

const VK_LEN: usize = 32;
const RX_CHUNK: usize = 6528;

pub struct FsmHandle {
    fsm: Mutex<Fsm<'static, QBus>>,
    cfg: &'static Config,
    qbus: &'static QBus,
}

pub struct QBus {
    outbox: Mutex<Vec<u64>>,
    inbox: Mutex<Vec<u32>>,
    rx_len: Mutex<usize>,
    last_writes: Mutex<Vec<(u8, u32)>>,
}

impl QBus {
    fn new() -> Self {
        QBus {
            outbox: Mutex::new(Vec::new()),
            inbox: Mutex::new(Vec::new()),
            rx_len: Mutex::new(0),
            last_writes: Mutex::new(Vec::new()),
        }
    }

    fn drain_writes(&self) -> Vec<(u8, u32)> {
        let mut w = self.outbox.lock();
        let mut v = Vec::new();
        while let Some(tx) = w.pop() {
            v.push((tx as u8, (tx >> 32) as u32));
        }
        v.reverse();
        v
    }

    fn push_rx(&self, data: &[u8]) {
        let mut words = Vec::new();
        for chunk in data.chunks(4) {
            let mut b = [0u8; 4];
            b[..chunk.len()].copy_from_slice(chunk);
            words.push(u32::from_be_bytes(b));
        }
        self.inbox.lock().extend(words);
        *self.rx_len.lock() = data.len();
    }

    fn has_rx(&self) -> bool {
        !self.inbox.lock().is_empty()
    }

    fn take_writes_n(&self, cap: usize) -> Vec<(u8, u32)> {
        let mut w = self.outbox.lock();
        let mut v: Vec<u64> = Vec::new();
        while let Some(tx) = w.pop() {
            v.push(tx);
        }
        v.reverse();
        let rest: Vec<u64> = v.split_off(cap.min(v.len()));
        for tx in rest.into_iter().rev() {
            w.push(tx);
        }
        v.into_iter().map(|tx| (tx as u8, (tx >> 32) as u32)).collect()
    }
}

impl SpiBus for QBus {
    unsafe fn write_reg(&self, addr: u8, data: u32) {
        self.outbox.lock().push(((data as u64) << 32) | addr as u64);
    }

    unsafe fn read_reg(&self, addr: u8) -> u32 {
        match addr {
            0x04 => {
                if self.has_rx() {
                    1
                } else {
                    0
                }
            }
            0x34 => *self.rx_len.lock() as u32,
            0x38 => self.inbox.lock().remove(0),
            _ => 0,
        }
    }
}

impl<'a> SpiBus for &'a QBus {
    unsafe fn write_reg(&self, addr: u8, data: u32) {
        self.outbox.lock().push(((data as u64) << 32) | addr as u64);
    }

    unsafe fn read_reg(&self, addr: u8) -> u32 {
        match addr {
            0x04 => {
                if self.has_rx() {
                    1
                } else {
                    0
                }
            }
            0x34 => *self.rx_len.lock() as u32,
            0x38 => self.inbox.lock().remove(0),
            _ => 0,
        }
    }
}

struct TestIdentity {
    vk: [u8; hs::VK_LEN],
    sk: [u8; hs::SK_LEN],
    spc: hs::SignPrecomp,
}

impl hs::Identity for TestIdentity {
    fn vk(&self) -> &[u8; hs::VK_LEN] {
        &self.vk
    }
    fn sk(&self) -> &[u8; hs::SK_LEN] {
        &self.sk
    }
    fn spc(&self) -> &hs::SignPrecomp {
        &self.spc
    }
}

fn identity_from_seed(seed: &[u8]) -> &'static TestIdentity {
    let (vk, sk) = keygen_internal(seed.try_into().unwrap());
    let mut spc = hs::SignPrecomp::default();
    sign_precomp_new_into(&mut spc, &sk);
    Box::leak(Box::new(TestIdentity { vk, sk, spc }))
}

fn fsm_create(role: u32, peer_fp: &[u8], seed_identity: &[u8], seed_d: &[u8], seed_z: &[u8], nonce: &[u8]) -> *mut FsmHandle {
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
pub extern "C" fn kyb_fsm_new(
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
pub extern "C" fn kyb_fsm_free(h: *mut FsmHandle) {
    if !h.is_null() {
        unsafe {
            drop(Box::from_raw(h));
        }
    }
}

#[no_mangle]
pub extern "C" fn kyb_fsm_poll(h: *mut FsmHandle) -> u32 {
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
pub extern "C" fn kyb_fsm_take_writes(h: *mut FsmHandle, out: *mut u64, cap: u32) -> u32 {
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
pub extern "C" fn kyb_fsm_push_rx(h: *mut FsmHandle, data: *const u8, len: u32) {
    unsafe {
        let h = &*h;
        h.qbus
            .push_rx(std::slice::from_raw_parts(data, len as usize));
    }
}

#[no_mangle]
pub extern "C" fn kyb_fsm_fingerprint(seed: *const u8, out: *mut u8) {
    unsafe {
        let (vk, _) = keygen_internal(std::slice::from_raw_parts(seed, 32).try_into().unwrap());
        let fp = hs::fingerprint(&vk);
        std::ptr::copy_nonoverlapping(fp.as_ptr(), out, VK_LEN);
    }
}
