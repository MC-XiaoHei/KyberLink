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
    if !h.is_null() {
        drop(unsafe { Box::from_raw(h) });
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
            write_sa(&*h.qbus, &sa, h.cfg.role_initiator, 1);
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
