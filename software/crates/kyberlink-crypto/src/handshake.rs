pub use crate::kem_internal::{
    decaps_internal, encaps_internal, keygen_internal as kem_keygen, CT_LEN, DK_LEN, EK_LEN,
};
pub use crate::mldsa_internal::{
    sign_precomp_into, sign_precomp_kk_into, verify_internal, verify_precomp, SignPrecomp,
    VerifyPrecomp, SIG_LEN, SK_LEN, VK_LEN,
};
use crate::shake;

pub const NONCE_LEN: usize = 32;
pub const M1_LEN: usize = NONCE_LEN + EK_LEN + VK_LEN;
pub const M2_LEN: usize = NONCE_LEN + EK_LEN + VK_LEN + SIG_LEN;
pub const M3_LEN: usize = CT_LEN + 4 + SIG_LEN;
pub const M4_LEN: usize = CT_LEN + 4 + SIG_LEN;
pub const SPI_OFF: usize = CT_LEN;

const H0: &[u8] = b"KyberLink-v1";
const INFO: &[u8] = b"KyberLink-v1-SA";
const BLOCK: usize = 136;

pub struct SaParams {
    pub spi_i: u32,
    pub spi_r: u32,
    pub sk_ei: [u8; 32],
    pub sk_er: [u8; 32],
    pub sa_salt: [u8; 32],
}

pub fn fingerprint(vk: &[u8]) -> [u8; 32] {
    shake::sha3_256(vk)
}

fn sign_stage<I: Identity + ?Sized>(id: &I, tag: u8, h: &[u8; 32]) -> [u8; SIG_LEN] {
    let mut smsg = [0u8; 33];
    smsg[0] = tag;
    smsg[1..].copy_from_slice(h);
    let mut mu_b = [0u8; 64];
    shake::shake256_squeeze(&[id.tr(), &[0x00], &[0u8], &smsg], &mut mu_b);
    sign_precomp_kk_into(id.spc(), id.kk(), &mu_b, &[0u8; 32])
}

fn verify_stage(
    vk: &[u8; VK_LEN],
    tag: u8,
    h: &[u8; 32],
    sig: &[u8; SIG_LEN],
    precomp: Option<&VerifyPrecomp>,
) -> bool {
    let mut smsg = [0u8; 33];
    smsg[0] = tag;
    smsg[1..].copy_from_slice(h);
    match precomp {
        Some(pc) => verify_precomp(pc, &smsg, b"", sig),
        None => verify_internal(vk, &smsg, b"", sig),
    }
}

pub const KK_LEN: usize = 32;
pub const TR_LEN: usize = 64;

pub fn kk_of(sk: &[u8; SK_LEN]) -> [u8; KK_LEN] {
    sk[32..64].try_into().unwrap()
}

pub fn tr_of(sk: &[u8; SK_LEN]) -> [u8; TR_LEN] {
    sk[64..128].try_into().unwrap()
}

pub trait Identity {
    fn vk(&self) -> &[u8; VK_LEN];
    fn kk(&self) -> &[u8; KK_LEN];
    fn tr(&self) -> &[u8; TR_LEN];
    fn spc(&self) -> &SignPrecomp;

    fn fingerprint(&self) -> [u8; 32] {
        fingerprint(self.vk())
    }
}

pub struct RomIdentity {
    pub vk: &'static [u8; VK_LEN],
    pub kk: &'static [u8; KK_LEN],
    pub tr: &'static [u8; TR_LEN],
    pub spc: &'static SignPrecomp,
}

impl Identity for RomIdentity {
    fn vk(&self) -> &[u8; VK_LEN] {
        self.vk
    }
    fn kk(&self) -> &[u8; KK_LEN] {
        self.kk
    }
    fn tr(&self) -> &[u8; TR_LEN] {
        self.tr
    }
    fn spc(&self) -> &SignPrecomp {
        self.spc
    }
}

fn hmac_sha3_256(key: &[u8], msg: &[u8]) -> [u8; 32] {
    let mut ipad = [0x36u8; BLOCK];
    let mut opad = [0x5cu8; BLOCK];
    for (i, k) in key.iter().take(BLOCK).enumerate() {
        ipad[i] ^= k;
        opad[i] ^= k;
    }
    let inner = shake::sha3_256_parts(&[&ipad, msg]);
    shake::sha3_256_parts(&[&opad, &inner])
}

pub fn hkdf_extract(salt: &[u8], ikm: &[u8]) -> [u8; 32] {
    hmac_sha3_256(salt, ikm)
}

fn encap_m(seed_d: &[u8; 32], seed_z: &[u8; 32], h: &[u8; 32]) -> [u8; 32] {
    shake::sha3_256_parts(&[seed_d, seed_z, h, b"KyberLink-m1"])
}

pub fn hkdf_expand(prk: &[u8; 32], info: &[u8], out: &mut [u8]) {
    let mut t = [0u8; 32];
    let mut t_len = 0usize;
    let mut buf = [0u8; 64];
    let mut done = 0usize;
    let mut counter = 1u8;
    while done < out.len() {
        buf[..t_len].copy_from_slice(&t[..t_len]);
        buf[t_len..t_len + info.len()].copy_from_slice(info);
        let n = t_len + info.len();
        buf[n] = counter;
        t = hmac_sha3_256(prk, &buf[..n + 1]);
        t_len = 32;
        let take = core::cmp::min(32, out.len() - done);
        out[done..done + take].copy_from_slice(&t[..take]);
        done += take;
        counter += 1;
    }
}

fn hkdf_derive(h4: &[u8; 32], ss: &[u8; 64], spi_i: u32, spi_r: u32) -> SaParams {
    let prk = hkdf_extract(h4, ss);
    let mut info = [0u8; 15 + 8];
    info[..15].copy_from_slice(INFO);
    info[15..19].copy_from_slice(&spi_i.to_be_bytes());
    info[19..23].copy_from_slice(&spi_r.to_be_bytes());
    let mut okm = [0u8; 96];
    hkdf_expand(&prk, &info[..23], &mut okm);
    let mut sk_ei = [0u8; 32];
    let mut sk_er = [0u8; 32];
    let mut sa_salt = [0u8; 32];
    sk_ei.copy_from_slice(&okm[0..32]);
    sk_er.copy_from_slice(&okm[32..64]);
    sa_salt.copy_from_slice(&okm[64..96]);
    SaParams {
        spi_i,
        spi_r,
        sk_ei,
        sk_er,
        sa_salt,
    }
}

pub struct InitiatorState {
    pub nonce_i: [u8; 32],
    dk_i: [u8; DK_LEN],
    vk_r: [u8; VK_LEN],
    ss_i: [u8; 32],
    h: [u8; 32],
    m_i: [u8; 32],
}

pub fn initiator_start<I: Identity + ?Sized>(
    id: &I,
    seed_kem_d: &[u8; 32],
    seed_kem_z: &[u8; 32],
    nonce: &[u8; 32],
) -> (InitiatorState, [u8; M1_LEN]) {
    let (ek, dk) = kem_keygen(seed_kem_d, seed_kem_z);
    let vk = id.vk();
    let mut m1 = [0u8; M1_LEN];
    m1[..32].copy_from_slice(nonce);
    m1[32..32 + EK_LEN].copy_from_slice(&ek);
    m1[32 + EK_LEN..].copy_from_slice(vk);
    let mut hbuf = [0u8; 64 + M1_LEN];
    hbuf[..H0.len()].copy_from_slice(H0);
    hbuf[H0.len()..H0.len() + M1_LEN].copy_from_slice(&m1);
    let h1 = shake::sha3_256(&hbuf[..H0.len() + M1_LEN]);
    (
        InitiatorState {
            nonce_i: *nonce,
            dk_i: dk,
            vk_r: [0u8; VK_LEN],
            ss_i: [0u8; 32],
            h: h1,
            m_i: encap_m(seed_kem_d, seed_kem_z, &h1),
        },
        m1,
    )
}

pub fn initiator_recv_m2<I: Identity + ?Sized>(
    st: &mut InitiatorState,
    id: &I,
    m2: &[u8],
    fp_r: &[u8; 32],
    precomp: Option<&VerifyPrecomp>,
) -> Result<([u8; M3_LEN], u32), &'static str> {
    if m2.len() != M2_LEN {
        return Err("bad m2 len");
    }
    let nonce_r = &m2[..32];
    let ek_rb = &m2[32..32 + EK_LEN];
    let vk_rb = &m2[32 + EK_LEN..32 + EK_LEN + VK_LEN];
    let sigb: &[u8; SIG_LEN] = m2[32 + EK_LEN + VK_LEN..].try_into().unwrap();
    if fingerprint(vk_rb) != *fp_r {
        return Err("fp_r mismatch");
    }
    let mut hbuf = [0u8; 32 + NONCE_LEN + EK_LEN + VK_LEN];
    hbuf[..32].copy_from_slice(&st.h);
    hbuf[32..32 + NONCE_LEN].copy_from_slice(nonce_r);
    hbuf[32 + NONCE_LEN..32 + NONCE_LEN + EK_LEN].copy_from_slice(ek_rb);
    hbuf[32 + NONCE_LEN + EK_LEN..].copy_from_slice(vk_rb);
    let h2 = shake::sha3_256(&hbuf);
    let vk_bytes: [u8; VK_LEN] = vk_rb.try_into().unwrap();
    let ok = verify_stage(&vk_bytes, 0x01, &h2, sigb, precomp);
    if !ok {
        return Err("m2 verify fail");
    }
    st.h = h2;
    st.vk_r.copy_from_slice(vk_rb);
    let (ss, ct) = encaps_internal(ek_rb.try_into().unwrap(), &st.m_i);
    st.ss_i = ss;
    let spi_i: u32 = (0x1000_0001u32
        ^ u32::from_be_bytes([st.nonce_i[0], st.nonce_i[1], st.nonce_i[2], st.nonce_i[3]]))
        | 1;
    let mut m3 = [0u8; M3_LEN];
    m3[..CT_LEN].copy_from_slice(&ct);
    m3[CT_LEN..CT_LEN + 4].copy_from_slice(&spi_i.to_be_bytes());
    let mut hbuf3 = [0u8; 32 + CT_LEN + 4];
    hbuf3[..32].copy_from_slice(&st.h);
    hbuf3[32..32 + CT_LEN].copy_from_slice(&ct);
    hbuf3[32 + CT_LEN..].copy_from_slice(&spi_i.to_be_bytes());
    let h3 = shake::sha3_256(&hbuf3);
    let sig3 = sign_stage(id, 0x02, &h3);
    m3[CT_LEN + 4..].copy_from_slice(&sig3);
    st.h = h3;
    Ok((m3, spi_i))
}

pub fn initiator_recv_m4(
    st: &mut InitiatorState,
    m4: &[u8],
    spi_i: u32,
    precomp: Option<&VerifyPrecomp>,
) -> Result<SaParams, &'static str> {
    if m4.len() != M4_LEN {
        return Err("bad m4 len");
    }
    let ctb: &[u8; CT_LEN] = m4[..CT_LEN].try_into().unwrap();
    let spi_r = u32::from_be_bytes(m4[CT_LEN..CT_LEN + 4].try_into().unwrap());
    let sigb: &[u8; SIG_LEN] = m4[CT_LEN + 4..].try_into().unwrap();
    let mut hbuf = [0u8; 32 + CT_LEN + 4];
    hbuf[..32].copy_from_slice(&st.h);
    hbuf[32..32 + CT_LEN].copy_from_slice(ctb);
    hbuf[32 + CT_LEN..].copy_from_slice(&spi_r.to_be_bytes());
    let h4 = shake::sha3_256(&hbuf);
    let ok = verify_stage(&st.vk_r, 0x03, &h4, sigb, precomp);
    if !ok {
        return Err("m4 verify fail");
    }
    let ss_r = decaps_internal(&st.dk_i, ctb);
    let mut ss = [0u8; 64];
    ss[..32].copy_from_slice(&st.ss_i);
    ss[32..].copy_from_slice(&ss_r);
    Ok(hkdf_derive(&h4, &ss, spi_i, spi_r))
}

pub struct ResponderState {
    pub nonce_r: [u8; 32],
    dk_r: [u8; DK_LEN],
    vk_i: [u8; VK_LEN],
    ek_i: [u8; EK_LEN],
    ss_r: [u8; 32],
    h: [u8; 32],
    m_r: [u8; 32],
}

pub fn responder_start<I: Identity + ?Sized>(
    id: &I,
    seed_kem_d: &[u8; 32],
    seed_kem_z: &[u8; 32],
    nonce: &[u8; 32],
    m1: &[u8],
    fp_i: &[u8; 32],
) -> Result<(ResponderState, [u8; M2_LEN]), &'static str> {
    if m1.len() != M1_LEN {
        return Err("bad m1 len");
    }
    let nonce_i = &m1[..32];
    let ek_ib: &[u8; EK_LEN] = m1[32..32 + EK_LEN].try_into().unwrap();
    let vk_ib: &[u8; VK_LEN] = m1[32 + EK_LEN..].try_into().unwrap();
    if fingerprint(vk_ib) != *fp_i {
        return Err("fp_i mismatch");
    }
    let mut hbuf = [0u8; 64 + M1_LEN];
    hbuf[..H0.len()].copy_from_slice(H0);
    hbuf[H0.len()..H0.len() + M1_LEN].copy_from_slice(m1);
    let h1 = shake::sha3_256(&hbuf[..H0.len() + M1_LEN]);
    let (ek_r, dk_r) = kem_keygen(seed_kem_d, seed_kem_z);
    let vk_r = id.vk();
    let mut m2 = [0u8; M2_LEN];
    m2[..32].copy_from_slice(nonce);
    m2[32..32 + EK_LEN].copy_from_slice(&ek_r);
    m2[32 + EK_LEN..32 + EK_LEN + VK_LEN].copy_from_slice(vk_r);
    let mut hbuf2 = [0u8; 32 + NONCE_LEN + EK_LEN + VK_LEN];
    hbuf2[..32].copy_from_slice(&h1);
    hbuf2[32..32 + NONCE_LEN].copy_from_slice(nonce);
    hbuf2[32 + NONCE_LEN..32 + NONCE_LEN + EK_LEN].copy_from_slice(&ek_r);
    hbuf2[32 + NONCE_LEN + EK_LEN..].copy_from_slice(vk_r);
    let h2 = shake::sha3_256(&hbuf2);
    let sig = sign_stage(id, 0x01, &h2);
    m2[32 + EK_LEN + VK_LEN..].copy_from_slice(&sig);
    let _ = nonce_i;
    Ok((
        ResponderState {
            nonce_r: *nonce,
            dk_r,
            vk_i: *vk_ib,
            ek_i: *ek_ib,
            ss_r: [0u8; 32],
            h: h2,
            m_r: encap_m(seed_kem_d, seed_kem_z, &h1),
        },
        m2,
    ))
}

pub fn responder_recv_m3<I: Identity + ?Sized>(
    st: &mut ResponderState,
    id: &I,
    m3: &[u8],
    spi_i: u32,
    precomp: Option<&VerifyPrecomp>,
) -> Result<([u8; M4_LEN], SaParams), &'static str> {
    if m3.len() != M3_LEN {
        return Err("bad m3 len");
    }
    let ctb: &[u8; CT_LEN] = m3[..CT_LEN].try_into().unwrap();
    let sigb: &[u8; SIG_LEN] = m3[CT_LEN + 4..].try_into().unwrap();
    let mut hbuf = [0u8; 32 + CT_LEN + 4];
    hbuf[..32].copy_from_slice(&st.h);
    hbuf[32..32 + CT_LEN].copy_from_slice(ctb);
    hbuf[32 + CT_LEN..].copy_from_slice(&spi_i.to_be_bytes());
    let h3 = shake::sha3_256(&hbuf);
    let ok = verify_stage(&st.vk_i, 0x02, &h3, sigb, precomp);
    if !ok {
        return Err("m3 verify fail");
    }
    st.h = h3;
    let ss_i = decaps_internal(&st.dk_r, ctb);
    let (ss_r, ct_r) = encaps_internal(&st.ek_i, &st.m_r);
    st.ss_r = ss_r;
    let spi_r = spi_i.wrapping_add(0x20000001u32);
    let mut m4 = [0u8; M4_LEN];
    m4[..CT_LEN].copy_from_slice(&ct_r);
    m4[CT_LEN..CT_LEN + 4].copy_from_slice(&spi_r.to_be_bytes());
    let mut hbuf4 = [0u8; 32 + CT_LEN + 4];
    hbuf4[..32].copy_from_slice(&st.h);
    hbuf4[32..32 + CT_LEN].copy_from_slice(&ct_r);
    hbuf4[32 + CT_LEN..].copy_from_slice(&spi_r.to_be_bytes());
    let h4 = shake::sha3_256(&hbuf4);
    let sig4 = sign_stage(id, 0x03, &h4);
    m4[CT_LEN + 4..].copy_from_slice(&sig4);
    let mut ss = [0u8; 64];
    ss[..32].copy_from_slice(&ss_i);
    ss[32..].copy_from_slice(&st.ss_r);
    Ok((m4, hkdf_derive(&h4, &ss, spi_i, spi_r)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mldsa_internal::{sign_precomp_new_into, SignPrecomp};
    use std::vec::Vec;

    struct TestIdentity {
        vk: [u8; VK_LEN],
        kk: [u8; KK_LEN],
        tr: [u8; TR_LEN],
        spc: SignPrecomp,
    }

    impl TestIdentity {
        fn new(seed: [u8; 32]) -> Self {
            let (vk, sk) = crate::mldsa_internal::keygen_internal(&seed);
            let mut spc = SignPrecomp::default();
            sign_precomp_new_into(&mut spc, &sk);
            TestIdentity {
                vk,
                kk: kk_of(&sk),
                tr: tr_of(&sk),
                spc,
            }
        }
    }

    impl Identity for TestIdentity {
        fn vk(&self) -> &[u8; VK_LEN] {
            &self.vk
        }
        fn kk(&self) -> &[u8; KK_LEN] {
            &self.kk
        }
        fn tr(&self) -> &[u8; TR_LEN] {
            &self.tr
        }
        fn spc(&self) -> &SignPrecomp {
            &self.spc
        }
    }

    #[test]
    fn m1_m4_handshake() {
        let id_i = TestIdentity::new([3u8; 32]);
        let id_r = TestIdentity::new([7u8; 32]);
        let fp_i = id_i.fingerprint();
        let fp_r = id_r.fingerprint();

        let (mut ia, m1) = initiator_start(&id_i, &[1u8; 32], &[2u8; 32], &[4u8; 32]);
        let (mut rb, m2) =
            responder_start(&id_r, &[5u8; 32], &[6u8; 32], &[8u8; 32], &m1, &fp_i).unwrap();
        let (m3, spi_i) = initiator_recv_m2(&mut ia, &id_i, &m2, &fp_r, None).unwrap();
        let (m4, sa_r) = responder_recv_m3(&mut rb, &id_r, &m3, spi_i, None).unwrap();
        let sa_i = initiator_recv_m4(&mut ia, &m4, spi_i, None).unwrap();
        assert_eq!(sa_i.spi_i, sa_r.spi_i);
        assert_eq!(sa_i.spi_r, sa_r.spi_r);
        assert_eq!(sa_i.sk_ei, sa_r.sk_ei);
        assert_eq!(sa_i.sk_er, sa_r.sk_er);
        assert_eq!(sa_i.sa_salt, sa_r.sa_salt);
    }

    #[test]
    fn hmac_sha3_256_kat() {
        let key: Vec<u8> = (1u8..=32).collect();
        let mac = hkdf_extract(&key, b"attack at dawn");
        assert_eq!(
            mac,
            [
                0x5a, 0xc7, 0x03, 0x80, 0xad, 0x1c, 0x10, 0x9a, 0xbb, 0xef, 0xd8, 0x4d, 0x59, 0x3c,
                0x6a, 0x0a, 0x40, 0x36, 0xeb, 0xf6, 0x37, 0xee, 0xca, 0xed, 0x3a, 0x70, 0x57, 0x94,
                0x81, 0xe3, 0x07, 0x27
            ]
        );
    }

    #[test]
    fn hkdf_kat() {
        let h4: Vec<u8> = (32u8..64).collect();
        let ss_i: Vec<u8> = (64u8..96).collect();
        let ss_r: Vec<u8> = (96u8..128).collect();
        let mut ikm = Vec::with_capacity(64);
        ikm.extend_from_slice(&ss_i);
        ikm.extend_from_slice(&ss_r);
        let prk = hkdf_extract(&h4, &ikm);
        assert_eq!(
            prk,
            [
                0x53, 0x9f, 0xc7, 0x43, 0x83, 0x00, 0x8f, 0x43, 0xb5, 0x49, 0x7a, 0xf1, 0xf0, 0xb5,
                0xeb, 0xda, 0xde, 0xf3, 0xf2, 0x0b, 0x85, 0x9b, 0xd3, 0x19, 0x3d, 0xf6, 0x76, 0x24,
                0xf4, 0x8a, 0x8e, 0xbc
            ]
        );
        let mut info = Vec::new();
        info.extend_from_slice(b"KyberLink-v1-SA");
        info.extend_from_slice(&0x11223344u32.to_be_bytes());
        info.extend_from_slice(&0xaabbccddu32.to_be_bytes());
        let mut okm = [0u8; 96];
        hkdf_expand(&prk, &info, &mut okm);
        assert_eq!(
            &okm,
            &[
                0x6c, 0x50, 0x78, 0xc2, 0x39, 0x65, 0xc6, 0x6b, 0xd1, 0xcf, 0x13, 0xda, 0xdb, 0xab,
                0xd5, 0xda, 0x19, 0x92, 0x32, 0x61, 0x1b, 0xf9, 0x4f, 0x1a, 0x89, 0x20, 0x1c, 0xfc,
                0x64, 0x8e, 0x44, 0xad, 0x90, 0x45, 0xdc, 0x93, 0x2b, 0x0c, 0xb3, 0xac, 0xfe, 0xbd,
                0xc6, 0x9d, 0x5a, 0xcc, 0xd0, 0xfc, 0x4e, 0xc9, 0x72, 0xcb, 0x5e, 0x42, 0x48, 0x5c,
                0xbf, 0x6e, 0x01, 0x86, 0x02, 0xc8, 0xe8, 0xc2, 0x8e, 0xde, 0xaa, 0x04, 0xf1, 0xbe,
                0xff, 0x43, 0xe6, 0xaa, 0x54, 0x98, 0xcd, 0xef, 0x14, 0xd1, 0x93, 0x0a, 0x82, 0xda,
                0xd4, 0xba, 0x28, 0x51, 0x1d, 0x85, 0x19, 0xfb, 0x26, 0x6d, 0xb4, 0x5d
            ]
        );
    }

    #[test]
    fn tamper_m2_fails() {
        let id_i = TestIdentity::new([3u8; 32]);
        let id_r = TestIdentity::new([7u8; 32]);
        let fp_i = id_i.fingerprint();
        let fp_r = id_r.fingerprint();
        let (mut ia, m1) = initiator_start(&id_i, &[1u8; 32], &[2u8; 32], &[4u8; 32]);
        let (_, mut m2) =
            responder_start(&id_r, &[5u8; 32], &[6u8; 32], &[8u8; 32], &m1, &fp_i).unwrap();
        m2[100] ^= 0xff;
        assert!(initiator_recv_m2(&mut ia, &id_i, &m2, &fp_r, None).is_err());
    }

    #[test]
    fn wrong_fp_rejected() {
        let id_i = TestIdentity::new([3u8; 32]);
        let (_, m1) = initiator_start(&id_i, &[1u8; 32], &[2u8; 32], &[4u8; 32]);
        assert!(responder_start(
            &TestIdentity::new([7u8; 32]),
            &[5u8; 32],
            &[6u8; 32],
            &[8u8; 32],
            &m1,
            &[0xffu8; 32]
        )
        .is_err());
    }
}
