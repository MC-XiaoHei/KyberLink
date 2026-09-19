use core::cell::RefCell;

use embassy_sync::blocking_mutex::CriticalSectionMutex;
use parking_lot::Mutex;

use kyberlink_core::handshake_fsm::{Config, Fsm};
use kyberlink_crypto::entropy::KemSeeds;
use kyberlink_crypto::handshake as hs;

use crate::identity::{self, TestIdentity};
use crate::qbus::QBus;

pub(crate) struct FsmHandle {
    pub(crate) fsm: Mutex<Fsm<QBus, TestIdentity>>,
}

pub(crate) fn create(
    peer_fp: &[u8],
    seed_identity: &[u8],
    seed_d: &[u8],
    seed_z: &[u8],
    nonce: &[u8],
) -> *mut FsmHandle {
    let identity = identity::from_seed(seed_identity);
    let peer_fp_arr: [u8; 32] = if peer_fp.iter().any(|&x| x != 0) {
        peer_fp.try_into().unwrap()
    } else {
        hs::Identity::fingerprint(&identity)
    };
    let cfg = Config {
        peer_fp: peer_fp_arr,
        seeds: CriticalSectionMutex::new(RefCell::new(KemSeeds {
            d: seed_d.try_into().unwrap(),
            z: seed_z.try_into().unwrap(),
            nonce: nonce.try_into().unwrap(),
        })),
        identity,
    };
    Box::into_raw(Box::new(FsmHandle {
        fsm: Mutex::new(Fsm::new(cfg, QBus::new())),
    }))
}
