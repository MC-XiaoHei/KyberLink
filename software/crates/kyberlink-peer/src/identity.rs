use kyberlink_crypto::handshake as hs;
use kyberlink_crypto::mldsa_internal::{keygen_internal, sign_precomp_new_into};

pub struct MemIdentity {
    vk: [u8; hs::VK_LEN],
    kk: [u8; hs::KK_LEN],
    tr: [u8; hs::TR_LEN],
    spc: Box<hs::SignPrecomp>,
}

impl hs::Identity for MemIdentity {
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

impl MemIdentity {
    pub fn from_seed(seed: &[u8; 32]) -> Self {
        let (vk, sk) = keygen_internal(seed);
        let mut spc = Box::new(hs::SignPrecomp::default());
        sign_precomp_new_into(&mut spc, &sk);
        MemIdentity {
            vk,
            kk: hs::kk_of(&sk),
            tr: hs::tr_of(&sk),
            spc,
        }
    }

    pub fn fingerprint(&self) -> [u8; 32] {
        hs::Identity::fingerprint(self)
    }
}
