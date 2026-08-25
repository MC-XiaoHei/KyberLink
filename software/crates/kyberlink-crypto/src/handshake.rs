use crate::kem_internal::{
    decaps_internal, encaps_internal, keygen_internal as kem_keygen, CT_LEN, DK_LEN, EK_LEN,
};
use crate::mldsa_internal::{
    keygen_internal as dsa_keygen, sign_internal, verify_internal, SIG_LEN, SK_LEN, VK_LEN,
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

fn hmac_sha3_256(key: &[u8], msg: &[u8]) -> [u8; 32] {
    let mut ipad = [0x36u8; BLOCK];
    let mut opad = [0x5cu8; BLOCK];
    for (i, k) in key.iter().take(BLOCK).enumerate() {
        ipad[i] ^= k;
        opad[i] ^= k;
    }
    let mut buf = [0u8; BLOCK + 8192];
    buf[..BLOCK].copy_from_slice(&ipad);
    buf[BLOCK..BLOCK + msg.len()].copy_from_slice(msg);
    let inner = shake::sha3_256(&buf[..BLOCK + msg.len()]);
    buf[..BLOCK].copy_from_slice(&opad);
    buf[BLOCK..BLOCK + 32].copy_from_slice(&inner);
    shake::sha3_256(&buf[..BLOCK + 32])
}

pub fn hkdf_extract(salt: &[u8], ikm: &[u8]) -> [u8; 32] {
    hmac_sha3_256(salt, ikm)
}

pub fn hkdf_expand(prk: &[u8; 32], info: &[u8], out: &mut [u8]) {
    let mut t = [0u8; 32];
    let mut buf = [0u8; 64];
    let mut done = 0usize;
    let mut counter = 1u8;
    while done < out.len() {
        buf[..32].copy_from_slice(&t);
        buf[32..32 + info.len()].copy_from_slice(info);
        let n = 32 + info.len();
        buf[n] = counter;
        t = hmac_sha3_256(prk, &buf[..n + 1]);
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
    sk_i: [u8; SK_LEN],
    pub vk_i: [u8; VK_LEN],
    vk_r: [u8; VK_LEN],
    ek_r: [u8; EK_LEN],
    ss_i: [u8; 32],
    h: [u8; 32],
}

pub fn initiator_start(
    seed_kem_d: &[u8; 32],
    seed_kem_z: &[u8; 32],
    seed_dsa: &[u8; 32],
    nonce: &[u8; 32],
) -> (InitiatorState, [u8; M1_LEN]) {
    let (ek, dk) = kem_keygen(seed_kem_d, seed_kem_z);
    let (vk, sk) = dsa_keygen(seed_dsa);
    let mut m1 = [0u8; M1_LEN];
    m1[..32].copy_from_slice(nonce);
    m1[32..32 + EK_LEN].copy_from_slice(&ek);
    m1[32 + EK_LEN..].copy_from_slice(&vk);
    let mut hbuf = [0u8; 64 + M1_LEN];
    hbuf[..H0.len()].copy_from_slice(H0);
    hbuf[H0.len()..H0.len() + M1_LEN].copy_from_slice(&m1);
    let h1 = shake::sha3_256(&hbuf[..H0.len() + M1_LEN]);
    (
        InitiatorState {
            nonce_i: *nonce,
            dk_i: dk,
            sk_i: sk,
            vk_i: vk,
            vk_r: [0u8; VK_LEN],
            ek_r: [0u8; EK_LEN],
            ss_i: [0u8; 32],
            h: h1,
        },
        m1,
    )
}

pub fn initiator_recv_m2(
    st: &mut InitiatorState,
    m2: &[u8],
    fp_r: &[u8; 32],
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
    let mut smsg = [0u8; 33];
    smsg[0] = 0x01;
    smsg[1..].copy_from_slice(&h2);
    if !verify_internal(vk_rb.try_into().unwrap(), &smsg, b"", sigb) {
        return Err("m2 verify fail");
    }
    st.h = h2;
    st.ek_r.copy_from_slice(ek_rb);
    st.vk_r.copy_from_slice(vk_rb);
    let (ss, ct) = encaps_internal(ek_rb.try_into().unwrap(), &st.nonce_i);
    st.ss_i = ss;
    let spi_i: u32 = 0x10000001u32.wrapping_add(st.nonce_i[0] as u32);
    let mut m3 = [0u8; M3_LEN];
    m3[..CT_LEN].copy_from_slice(&ct);
    m3[CT_LEN..CT_LEN + 4].copy_from_slice(&spi_i.to_be_bytes());
    let mut hbuf3 = [0u8; 32 + CT_LEN + 4];
    hbuf3[..32].copy_from_slice(&st.h);
    hbuf3[32..32 + CT_LEN].copy_from_slice(&ct);
    hbuf3[32 + CT_LEN..].copy_from_slice(&spi_i.to_be_bytes());
    let h3 = shake::sha3_256(&hbuf3);
    let mut smsg3 = [0u8; 33];
    smsg3[0] = 0x02;
    smsg3[1..].copy_from_slice(&h3);
    let sig3 = sign_internal(&st.sk_i, &smsg3, b"");
    m3[CT_LEN + 4..].copy_from_slice(&sig3);
    st.h = h3;
    Ok((m3, spi_i))
}

pub fn initiator_recv_m4(st: &mut InitiatorState, m4: &[u8], spi_i: u32) -> Result<SaParams, &'static str> {
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
    let mut smsg = [0u8; 33];
    smsg[0] = 0x03;
    smsg[1..].copy_from_slice(&h4);
    if !verify_internal(&st.vk_r, &smsg, b"", sigb) {
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
    sk_r: [u8; SK_LEN],
    pub vk_r: [u8; VK_LEN],
    vk_i: [u8; VK_LEN],
    ek_i: [u8; EK_LEN],
    ss_r: [u8; 32],
    h: [u8; 32],
}

pub fn responder_start(
    seed_kem_d: &[u8; 32],
    seed_kem_z: &[u8; 32],
    seed_dsa: &[u8; 32],
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
    let (vk_r, sk_r) = dsa_keygen(seed_dsa);
    let mut m2 = [0u8; M2_LEN];
    m2[..32].copy_from_slice(nonce);
    m2[32..32 + EK_LEN].copy_from_slice(&ek_r);
    m2[32 + EK_LEN..32 + EK_LEN + VK_LEN].copy_from_slice(&vk_r);
    let mut hbuf2 = [0u8; 32 + NONCE_LEN + EK_LEN + VK_LEN];
    hbuf2[..32].copy_from_slice(&h1);
    hbuf2[32..32 + NONCE_LEN].copy_from_slice(nonce);
    hbuf2[32 + NONCE_LEN..32 + NONCE_LEN + EK_LEN].copy_from_slice(&ek_r);
    hbuf2[32 + NONCE_LEN + EK_LEN..].copy_from_slice(&vk_r);
    let h2 = shake::sha3_256(&hbuf2);
    let mut smsg = [0u8; 33];
    smsg[0] = 0x01;
    smsg[1..].copy_from_slice(&h2);
    let sig = sign_internal(&sk_r, &smsg, b"");
    m2[32 + EK_LEN + VK_LEN..].copy_from_slice(&sig);
    let _ = nonce_i;
    Ok((
        ResponderState {
            nonce_r: *nonce,
            dk_r,
            sk_r,
            vk_r,
            vk_i: *vk_ib,
            ek_i: *ek_ib,
            ss_r: [0u8; 32],
            h: h2,
        },
        m2,
    ))
}

pub fn responder_recv_m3(
    st: &mut ResponderState,
    m3: &[u8],
    spi_i: u32,
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
    let mut smsg = [0u8; 33];
    smsg[0] = 0x02;
    smsg[1..].copy_from_slice(&h3);
    if !verify_internal(&st.vk_i, &smsg, b"", sigb) {
        return Err("m3 verify fail");
    }
    st.h = h3;
    let ss_i = decaps_internal(&st.dk_r, ctb);
    let (ss_r, ct_r) = encaps_internal(&st.ek_i, &st.nonce_r);
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
    let mut smsg4 = [0u8; 33];
    smsg4[0] = 0x03;
    smsg4[1..].copy_from_slice(&h4);
    let sig4 = sign_internal(&st.sk_r, &smsg4, b"");
    m4[CT_LEN + 4..].copy_from_slice(&sig4);
    let mut ss = [0u8; 64];
    ss[..32].copy_from_slice(&ss_i);
    ss[32..].copy_from_slice(&st.ss_r);
    Ok((m4, hkdf_derive(&h4, &ss, spi_i, spi_r)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn m1_m4_handshake() {
        let (mut ia, m1) = initiator_start(&[1u8; 32], &[2u8; 32], &[3u8; 32], &[4u8; 32]);
        let fp_i = fingerprint(&ia.vk_i);
        let (mut rb, m2) =
            responder_start(&[5u8; 32], &[6u8; 32], &[7u8; 32], &[8u8; 32], &m1, &fp_i).unwrap();
        let fp_r = fingerprint(&rb.vk_r);
        let (m3, spi_i) = initiator_recv_m2(&mut ia, &m2, &fp_r).unwrap();
        let (m4, sa_r) = responder_recv_m3(&mut rb, &m3, spi_i).unwrap();
        let sa_i = initiator_recv_m4(&mut ia, &m4, spi_i).unwrap();
        assert_eq!(sa_i.spi_i, sa_r.spi_i);
        assert_eq!(sa_i.spi_r, sa_r.spi_r);
        assert_eq!(sa_i.sk_ei, sa_r.sk_ei);
        assert_eq!(sa_i.sk_er, sa_r.sk_er);
        assert_eq!(sa_i.sa_salt, sa_r.sa_salt);
    }

    #[test]
    fn tamper_m2_fails() {
        let (mut ia, m1) = initiator_start(&[1u8; 32], &[2u8; 32], &[3u8; 32], &[4u8; 32]);
        let fp_i = fingerprint(&ia.vk_i);
        let (mut rb, mut m2) =
            responder_start(&[5u8; 32], &[6u8; 32], &[7u8; 32], &[8u8; 32], &m1, &fp_i).unwrap();
        m2[100] ^= 0xff;
        let fp_r = fingerprint(&rb.vk_r);
        assert!(initiator_recv_m2(&mut ia, &m2, &fp_r).is_err());
    }


    #[test]
    fn wrong_fp_rejected() {
        let (ia, m1) = initiator_start(&[1u8; 32], &[2u8; 32], &[3u8; 32], &[4u8; 32]);
        assert!(responder_start(
            &[5u8; 32],
            &[6u8; 32],
            &[7u8; 32],
            &[8u8; 32],
            &m1,
            &[0xffu8; 32]
        )
        .is_err());
        let _ = ia;
    }
}
