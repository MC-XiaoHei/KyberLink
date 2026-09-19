use kyberlink_crypto::handshake as hs;
use kyberlink_crypto::mldsa_internal::{keygen_internal, sign_precomp_new_into};

pub(crate) struct TestIdentity {
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

pub(crate) fn from_seed(seed: &[u8]) -> TestIdentity {
    let (vk, sk) = keygen_internal(seed.try_into().unwrap());
    let mut spc = hs::SignPrecomp::default();
    sign_precomp_new_into(&mut spc, &sk);
    TestIdentity {
        vk,
        kk: hs::kk_of(&sk),
        tr: hs::tr_of(&sk),
        spc,
    }
}
