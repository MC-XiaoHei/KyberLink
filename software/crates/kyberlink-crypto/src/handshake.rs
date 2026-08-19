use crate::kem_internal::{decaps_internal, encaps_internal, keygen_internal as kem_keygen};
use crate::mldsa_internal::{
    keygen_internal as dsa_keygen, sign_internal, verify_internal,
};
use crate::shake;

pub const EK_LEN: usize = crate::kem_internal::EK_LEN;
pub const VK_LEN: usize = crate::mldsa_internal::VK_LEN;

fn fingerprint(ek: &[u8], vk: &[u8]) -> [u8; 32] {
    let mut buf = [0u8; EK_LEN + VK_LEN];
    buf[..ek.len()].copy_from_slice(ek);
    buf[ek.len()..ek.len() + vk.len()].copy_from_slice(vk);
    shake::sha3_256(&buf[..ek.len() + vk.len()])
}

pub struct HandshakeKeys {
    pub session: [u8; 32],
    pub fp_i: [u8; 32],
    pub fp_r: [u8; 32],
}

pub fn run_handshake(seed_i: &[u8; 32], seed_r: &[u8; 32]) -> Option<HandshakeKeys> {
    let (ek_i, dk_i) = kem_keygen(&[seed_i[0]; 32], &[seed_i[1]; 32]);
    let (vk_i, sk_i) = dsa_keygen(&[seed_i[2]; 32]);
    let (ek_r, dk_r) = kem_keygen(&[seed_r[0]; 32], &[seed_r[1]; 32]);
    let (vk_r, sk_r) = dsa_keygen(&[seed_r[2]; 32]);

    let fp_i = fingerprint(&ek_i, &vk_i);
    let fp_r = fingerprint(&ek_r, &vk_r);
    if fp_i != fingerprint(&ek_i, &vk_i) || fp_r != fingerprint(&ek_r, &vk_r) {
        return None;
    }

    let (k_i, ct) = encaps_internal(&ek_r, &[0x77u8; 32]);
    let k_r = decaps_internal(&dk_r, &ct);
    if k_i != k_r {
        return None;
    }

    let sig = sign_internal(&sk_i, &k_i, b"kyberlink-handshake");
    if !verify_internal(&vk_i, &k_i, b"kyberlink-handshake", &sig) {
        return None;
    }

    let mut session_i = [0u8; 32];
    shake::shake256_squeeze(&[&k_i, b"KyberLink-session-v1", &fp_i, &fp_r], &mut session_i);
    let mut session_r = [0u8; 32];
    shake::shake256_squeeze(&[&k_r, b"KyberLink-session-v1", &fp_i, &fp_r], &mut session_r);
    if session_i != session_r {
        return None;
    }

    Some(HandshakeKeys {
        session: session_i,
        fp_i,
        fp_r,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn handshake_succeeds() {
        let r = run_handshake(&[1u8; 32], &[2u8; 32]).unwrap();
        let r2 = run_handshake(&[1u8; 32], &[2u8; 32]).unwrap();
        assert_eq!(r.session, r2.session);
        assert_ne!(r.fp_i, r.fp_r);
        let r3 = run_handshake(&[1u8; 32], &[3u8; 32]).unwrap();
        assert_ne!(r.session, r3.session);
    }
}
