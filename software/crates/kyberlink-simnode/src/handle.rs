use core::cell::RefCell;

use embassy_sync::blocking_mutex::CriticalSectionMutex;
use parking_lot::Mutex;

use kyberlink_core::handshake_fsm::{Config, Fsm};
use kyberlink_crypto::entropy::KemSeeds;
use kyberlink_crypto::handshake as hs;

use crate::identity::{self, TestIdentity};
use crate::qbus::QBus;

pub(crate) struct FsmHandle {
    pub(crate) fsm: Mutex<Fsm<'static, QBus>>,
    pub(crate) cfg: &'static Config,
    pub(crate) qbus: &'static QBus,
    pub(crate) cfg_ptr: *mut Config,
    pub(crate) qbus_ptr: *mut QBus,
    pub(crate) identity_ptr: *mut TestIdentity,
}

pub(crate) fn create(
    role: u32,
    peer_fp: &[u8],
    seed_identity: &[u8],
    seed_d: &[u8],
    seed_z: &[u8],
    nonce: &[u8],
) -> *mut FsmHandle {
    let identity_ptr = Box::into_raw(identity::from_seed(seed_identity));
    let identity = unsafe { &*identity_ptr };
    let fp = hs::Identity::fingerprint(identity);
    let peer_fp_arr: [u8; 32] = if peer_fp.iter().any(|&x| x != 0) {
        peer_fp.try_into().unwrap()
    } else {
        fp
    };
    let cfg_ptr = Box::into_raw(Box::new(Config {
        role_initiator: role == 0,
        peer_fp: peer_fp_arr,
        seeds: CriticalSectionMutex::new(RefCell::new(KemSeeds {
            d: seed_d.try_into().unwrap(),
            z: seed_z.try_into().unwrap(),
            nonce: nonce.try_into().unwrap(),
        })),
        identity,
    }));
    let qbus_ptr = Box::into_raw(Box::new(QBus::new()));
    let (cfg, qbus) = unsafe { (&*cfg_ptr, &*qbus_ptr) };
    let fsm = Fsm::new(cfg, qbus);
    Box::into_raw(Box::new(FsmHandle {
        fsm: Mutex::new(fsm),
        cfg,
        qbus,
        cfg_ptr,
        qbus_ptr,
        identity_ptr,
    }))
}
