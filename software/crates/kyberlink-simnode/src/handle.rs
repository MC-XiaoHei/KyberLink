use parking_lot::Mutex;

use kyberlink_core::handshake_fsm::{Config, Fsm};
use kyberlink_crypto::handshake as hs;

use crate::identity::{self, TestIdentity};
use crate::qbus::QBus;

pub(crate) struct FsmHandle {
    pub(crate) fsm: Mutex<Fsm<'static, QBus>>,
    _identity: Box<TestIdentity>,
    pub(crate) cfg: Box<Config>,
    pub(crate) qbus: Box<QBus>,
}

pub(crate) fn create(
    role: u32,
    peer_fp: &[u8],
    seed_identity: &[u8],
    seed_d: &[u8],
    seed_z: &[u8],
    nonce: &[u8],
) -> *mut FsmHandle {
    let identity = identity::from_seed(seed_identity);
    let fp = hs::Identity::fingerprint(&*identity);
    let peer_fp_arr: [u8; 32] = if peer_fp.iter().any(|&x| x != 0) {
        peer_fp.try_into().unwrap()
    } else {
        fp
    };
    let cfg = Box::new(Config {
        role_initiator: role == 0,
        peer_fp: peer_fp_arr,
        seed_kem_d: seed_d.try_into().unwrap(),
        seed_kem_z: seed_z.try_into().unwrap(),
        nonce: nonce.try_into().unwrap(),
        identity: unsafe { &*(&*identity as *const TestIdentity) },
    });
    let qbus = Box::new(QBus::new());
    let fsm = Fsm::new(unsafe { &*(&*cfg as *const Config) }, unsafe {
        &*(&*qbus as *const QBus)
    });
    Box::into_raw(Box::new(FsmHandle {
        fsm: Mutex::new(fsm),
        _identity: identity,
        cfg,
        qbus,
    }))
}
