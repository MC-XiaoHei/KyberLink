use kyberlink_core::handshake_fsm::{write_sa, FsmOutcome};
use kyberlink_crypto::handshake as hs;
use kyberlink_crypto::mldsa_internal::keygen_internal;

use crate::handle::{self, FsmHandle};

const FP_LEN: usize = 32;

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
        handle::create(
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
    if h.is_null() {
        return;
    }
    unsafe {
        let b = Box::from_raw(h);
        let (cfg, qbus, identity) = (b.cfg_ptr, b.qbus_ptr, b.identity_ptr);
        drop(b);
        drop(Box::from_raw(cfg));
        drop(Box::from_raw(qbus));
        drop(Box::from_raw(identity));
    }
}

#[no_mangle]
pub unsafe extern "C" fn kyb_simnode_set_status(h: *mut FsmHandle, value: u32) {
    let h = unsafe { &*h };
    h.qbus.set_status(value);
}

#[no_mangle]
pub unsafe extern "C" fn kyb_fsm_poll(h: *mut FsmHandle) -> u32 {
    let h = unsafe { &*h };
    match h.fsm.lock().poll() {
        FsmOutcome::Sa(sa) => {
            write_sa(h.qbus, &sa, h.cfg.role_initiator, 1);
            1
        }
        FsmOutcome::Wait => 0,
    }
}

#[no_mangle]
pub unsafe extern "C" fn kyb_fsm_take_writes(h: *mut FsmHandle, out: *mut u64, cap: u32) -> u32 {
    let (h, slot) = unsafe { (&*h, std::slice::from_raw_parts_mut(out, cap as usize)) };
    let sunk = h.qbus.take_writes_n(cap as usize);
    for (i, (addr, data)) in sunk.iter().enumerate() {
        slot[i] = ((*data as u64) << 32) | *addr as u64;
    }
    sunk.len() as u32
}

#[no_mangle]
pub unsafe extern "C" fn kyb_fsm_push_rx(h: *mut FsmHandle, data: *const u8, len: u32) {
    let (h, payload) = unsafe { (&*h, std::slice::from_raw_parts(data, len as usize)) };
    h.qbus.push_rx(payload);
}

#[no_mangle]
pub unsafe extern "C" fn kyb_fsm_fingerprint(seed: *const u8, out: *mut u8) {
    unsafe {
        let seed = std::slice::from_raw_parts(seed, 32);
        let (vk, _) = keygen_internal(seed.try_into().unwrap());
        let fp = hs::fingerprint(&vk);
        std::ptr::copy_nonoverlapping(fp.as_ptr(), out, FP_LEN);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use kyberlink_core::handshake_fsm::{REG_CTRL, REG_HSK_TX_DATA, REG_HSK_TX_LEN};

    const M1_TOTAL: u32 = 3168;
    const CHUNK_BYTES: u32 = 1012;

    fn seed(v: u8) -> [u8; 32] {
        [v; 32]
    }

    fn open(role: u32) -> *mut FsmHandle {
        unsafe {
            kyb_fsm_new(
                role,
                seed(0).as_ptr(),
                seed(0x21).as_ptr(),
                seed(0x31).as_ptr(),
                seed(0x41).as_ptr(),
                seed(0x51).as_ptr(),
            )
        }
    }

    fn writes(h: *mut FsmHandle, cap: usize) -> Vec<(u32, u32)> {
        let mut buf = vec![0u64; cap];
        let n = unsafe { kyb_fsm_take_writes(h, buf.as_mut_ptr(), cap as u32) } as usize;
        buf.truncate(n);
        buf.into_iter().map(|w| ((w >> 32) as u32, w as u32)).collect()
    }

    fn pump_with(h: *mut FsmHandle, rounds: usize, cap: usize, status: u32) -> Vec<(u32, u32)> {
        let mut all = Vec::new();
        for _ in 0..rounds {
            unsafe { kyb_simnode_set_status(h, status) };
            unsafe { kyb_fsm_poll(h) };
            all.extend(writes(h, cap));
        }
        all
    }

    fn pump(h: *mut FsmHandle, rounds: usize, cap: usize) -> Vec<(u32, u32)> {
        pump_with(h, rounds, cap, 0b01)
    }

    #[test]
    fn poll_emits_m1_chunk() {
        let h = open(0);
        assert!(!h.is_null());
        let w = pump(h, 4, 4096);
        assert!(w.contains(&(CHUNK_BYTES, REG_HSK_TX_LEN as u32)));
        assert!(w.contains(&(M1_TOTAL, REG_HSK_TX_DATA as u32)));
        assert!(w.contains(&(0, REG_HSK_TX_DATA as u32)));
        assert!(w.contains(&(2, REG_CTRL as u32)));
        unsafe { kyb_fsm_free(h) };
    }

    #[test]
    fn take_writes_cap_preserves_stream() {
        let whole = open(0);
        let split = open(0);
        let mut all = Vec::new();
        let mut parts = Vec::new();
        for _ in 0..4 {
            unsafe {
                kyb_fsm_poll(whole);
                kyb_fsm_poll(split);
            }
            all.extend(writes(whole, 4096));
            parts.extend(writes(split, 4));
            parts.extend(writes(split, 4096));
        }
        assert!(!all.is_empty());
        assert_eq!(parts, all);
        unsafe {
            kyb_fsm_free(whole);
            kyb_fsm_free(split);
        }
    }

    #[test]
    fn busy_status_blocks_tx() {
        let h = open(0);
        assert!(pump_with(h, 4, 4096, 0b10).is_empty());
        assert!(!pump(h, 4, 4096).is_empty());
        unsafe { kyb_fsm_free(h) };
    }

    #[test]
    fn push_rx_ack_advances_chunk() {
        let h = open(0);
        let first = pump(h, 4, 4096);
        assert!(first.contains(&(0, REG_HSK_TX_DATA as u32)));
        let ack = [0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0];
        unsafe { kyb_fsm_push_rx(h, ack.as_ptr(), ack.len() as u32) };
        assert!(pump(h, 4, 4096).contains(&(1004, REG_HSK_TX_DATA as u32)));
        unsafe { kyb_fsm_free(h) };
    }

    #[test]
    fn fingerprint_is_seed_deterministic() {
        let mut a = [0u8; 32];
        let mut b = [0u8; 32];
        let mut c = [0u8; 32];
        unsafe {
            kyb_fsm_fingerprint(seed(1).as_ptr(), a.as_mut_ptr());
            kyb_fsm_fingerprint(seed(1).as_ptr(), b.as_mut_ptr());
            kyb_fsm_fingerprint(seed(2).as_ptr(), c.as_mut_ptr());
        }
        assert_eq!(a, b);
        assert_ne!(a, c);
    }

    #[test]
    fn free_accepts_null() {
        unsafe { kyb_fsm_free(std::ptr::null_mut()) };
    }
}
