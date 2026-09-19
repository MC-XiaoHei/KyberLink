use kyberlink_core::handshake_fsm::{write_sa, FsmOutcome, Role};
use kyberlink_crypto::handshake as hs;
use kyberlink_crypto::mldsa_internal::keygen_internal;

use crate::handle::{self, FsmHandle};

#[no_mangle]
pub unsafe extern "C" fn kyb_fsm_new(
    peer_fp: &[u8; 32],
    seed_identity: &[u8; 32],
    seed_d: &[u8; 32],
    seed_z: &[u8; 32],
    nonce: &[u8; 32],
) -> *mut FsmHandle {
    handle::create(peer_fp, seed_identity, seed_d, seed_z, nonce)
}

#[no_mangle]
pub unsafe extern "C" fn kyb_fsm_free(h: *mut FsmHandle) {
    if h.is_null() {
        return;
    }
    drop(unsafe { Box::from_raw(h) });
}

#[no_mangle]
pub unsafe extern "C" fn kyb_simnode_set_status(h: &mut FsmHandle, value: u32) {
    h.fsm.spi.set_status(value);
}

#[no_mangle]
pub unsafe extern "C" fn kyb_fsm_poll(h: &mut FsmHandle) -> u32 {
    match h.fsm.poll(&mut h.pc) {
        FsmOutcome::Sa(sa) => {
            write_sa(&h.fsm.spi, &sa, h.fsm.role == Role::Initiator, 1);
            1
        }
        FsmOutcome::Wait => 0,
    }
}

#[no_mangle]
pub unsafe extern "C" fn kyb_fsm_role(h: &mut FsmHandle) -> u32 {
    match h.fsm.role {
        Role::Undecided => 0,
        Role::Initiator => 1,
        Role::Responder => 2,
    }
}

#[no_mangle]
pub unsafe extern "C" fn kyb_fsm_take_writes(h: &mut FsmHandle, out: *mut u64, cap: u32) -> u32 {
    let sunk = h.fsm.spi.take_writes_n(cap as usize);
    let slot = unsafe { std::slice::from_raw_parts_mut(out, cap as usize) };
    for (i, (addr, data)) in sunk.iter().enumerate() {
        slot[i] = ((*data as u64) << 32) | *addr as u64;
    }
    sunk.len() as u32
}

#[no_mangle]
pub unsafe extern "C" fn kyb_fsm_push_rx(h: &mut FsmHandle, data: *const u8, len: u32) {
    let payload = unsafe { std::slice::from_raw_parts(data, len as usize) };
    h.fsm.spi.push_rx(payload);
}

#[no_mangle]
pub unsafe extern "C" fn kyb_fsm_fingerprint(seed: &[u8; 32], out: &mut [u8; 32]) {
    let (vk, _) = keygen_internal(seed);
    *out = hs::fingerprint(&vk);
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

    fn open() -> *mut FsmHandle {
        unsafe { kyb_fsm_new(&seed(0), &seed(0x21), &seed(0x31), &seed(0x41), &seed(0x51)) }
    }

    fn writes(h: *mut FsmHandle, cap: usize) -> Vec<(u32, u32)> {
        let mut buf = vec![0u64; cap];
        let n = unsafe { kyb_fsm_take_writes(&mut *h, buf.as_mut_ptr(), cap as u32) } as usize;
        buf.truncate(n);
        buf.into_iter()
            .map(|w| ((w >> 32) as u32, w as u32))
            .collect()
    }

    fn pump_with(h: *mut FsmHandle, rounds: usize, cap: usize, status: u32) -> Vec<(u32, u32)> {
        let mut all = Vec::new();
        for _ in 0..rounds {
            unsafe {
                kyb_simnode_set_status(&mut *h, status);
                kyb_fsm_poll(&mut *h);
            }
            all.extend(writes(h, cap));
        }
        all
    }

    fn pump(h: *mut FsmHandle, rounds: usize, cap: usize) -> Vec<(u32, u32)> {
        pump_with(h, rounds, cap, 0b01)
    }

    #[test]
    fn poll_emits_m1_chunk() {
        let h = open();
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
        let whole = open();
        let split = open();
        let mut all = Vec::new();
        let mut parts = Vec::new();
        for _ in 0..4 {
            unsafe {
                kyb_fsm_poll(&mut *whole);
                kyb_fsm_poll(&mut *split);
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
        let h = open();
        assert!(pump_with(h, 4, 4096, 0b10).is_empty());
        assert!(!pump(h, 4, 4096).is_empty());
        unsafe { kyb_fsm_free(h) };
    }

    #[test]
    fn push_rx_ack_advances_chunk() {
        let h = open();
        let first = pump(h, 4, 4096);
        assert!(first.contains(&(0, REG_HSK_TX_DATA as u32)));
        let ack = [0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0];
        unsafe { kyb_fsm_push_rx(&mut *h, ack.as_ptr(), ack.len() as u32) };
        assert!(pump(h, 4, 4096).contains(&(1004, REG_HSK_TX_DATA as u32)));
        unsafe { kyb_fsm_free(h) };
    }

    #[test]
    fn fingerprint_is_seed_deterministic() {
        let mut a = [0u8; 32];
        let mut b = [0u8; 32];
        let mut c = [0u8; 32];
        unsafe {
            kyb_fsm_fingerprint(&seed(1), &mut a);
            kyb_fsm_fingerprint(&seed(1), &mut b);
            kyb_fsm_fingerprint(&seed(2), &mut c);
        }
        assert_eq!(a, b);
        assert_ne!(a, c);
    }

    #[test]
    fn free_accepts_null() {
        unsafe { kyb_fsm_free(std::ptr::null_mut()) };
    }
}
