use sha3::digest::{ExtendableOutput, Update, XofReader};
use sha3::{Digest, Shake128, Shake256, Sha3_256, Sha3_512};

use crate::ntt;

const K: usize = 3;
const ETA1: usize = 2;
const ETA2: usize = 2;
const DU: usize = 10;
const DV: usize = 4;
const Q: u16 = ntt::Q;

pub const EK_LEN: usize = 384 * K + 32;
pub const DK_PKE_LEN: usize = 384 * K;
pub const DK_LEN: usize = DK_PKE_LEN + EK_LEN + 32 + 32;
pub const CT_LEN: usize = 32 * DU * K + 32 * DV;

#[derive(Clone, Debug)]
pub struct KeygenMid {
    pub rho: [u8; 32],
    pub sigma: [u8; 32],
    pub a: Vec<u16>,
    pub s: Vec<u16>,
    pub e: Vec<u16>,
    pub sh: Vec<u16>,
    pub eh: Vec<u16>,
    pub th: Vec<u16>,
}

#[derive(Clone, Debug)]
pub struct EncapsMid {
    pub hek: [u8; 32],
    pub k: [u8; 32],
    pub r: [u8; 32],
    pub th: Vec<u16>,
    pub rho: [u8; 32],
    pub a: Vec<u16>,
    pub y: Vec<u16>,
    pub e1: Vec<u16>,
    pub e2: Vec<u16>,
    pub yh: Vec<u16>,
    pub u: Vec<u16>,
    pub mu: Vec<u16>,
    pub v: Vec<u16>,
}

#[derive(Clone, Debug)]
pub struct DecapsMid {
    pub m: [u8; 32],
    pub u: Vec<u16>,
    pub v: Vec<u16>,
    pub sh: Vec<u16>,
    pub uh: Vec<u16>,
    pub w: Vec<u16>,
    pub kp: [u8; 32],
    pub rp: [u8; 32],
    pub kbar: [u8; 32],
    pub cp: Vec<u8>,
}

fn h(x: &[u8]) -> [u8; 32] {
    Sha3_256::digest(x).into()
}

fn g(x: &[u8]) -> [u8; 64] {
    Sha3_512::digest(x).into()
}

fn j(x: &[u8]) -> [u8; 32] {
    let mut out = [0u8; 32];
    let mut s = Shake256::default();
    s.update(x);
    s.finalize_xof().read(&mut out);
    out
}

fn sample_ntt_poly(rho: &[u8; 32], j: u8, i: u8) -> [u16; 256] {
    let mut seed = [0u8; 34];
    seed[..32].copy_from_slice(rho);
    seed[32] = j;
    seed[33] = i;
    let mut stream = [0u8; 840];
    let mut s = Shake128::default();
    s.update(&seed);
    s.finalize_xof().read(&mut stream);
    let mut coeffs = [0u16; 256];
    let mut pos = 0;
    let mut n = 0;
    while n < 256 {
        let b0 = stream[pos] as u16;
        let b1 = stream[pos + 1] as u16;
        let b2 = stream[pos + 2] as u16;
        pos += 3;
        let d1 = b0 + 256 * (b1 % 16);
        if d1 < Q {
            coeffs[n] = d1;
            n += 1;
        }
        if n < 256 {
            let d2 = b1 / 16 + 16 * b2;
            if d2 < Q {
                coeffs[n] = d2;
                n += 1;
            }
        }
    }
    coeffs
}

fn cbd_to_poly(c: &[i16; 256]) -> [u16; 256] {
    let mut f = [0u16; 256];
    for k in 0..256 {
        f[k] = c[k].rem_euclid(Q as i16) as u16;
    }
    f
}

fn prf_poly(seed: &[u8; 32], b: u8, eta: usize) -> [u16; 256] {
    let mut out = vec![0u8; 64 * eta];
    let mut s = Shake256::default();
    s.update(seed);
    s.update(&[b]);
    s.finalize_xof().read(&mut out);
    let mut coeffs = [0i16; 256];
    if eta == 3 {
        for (idx, w) in out.chunks(3).enumerate() {
            let d = w[0] as u32 | ((w[1] as u32) << 8) | ((w[2] as u32) << 16);
            for k in 0..4 {
                let bits = (d >> (6 * k)) & 0x3F;
                let pos = (bits & 0b111).count_ones() as i16;
                let neg = ((bits >> 3) & 0b111).count_ones() as i16;
                coeffs[idx * 4 + k] = pos - neg;
            }
        }
    } else {
        for (idx, b) in out.chunks(4).enumerate() {
            let d = b[0] as u32 | ((b[1] as u32) << 8) | ((b[2] as u32) << 16) | ((b[3] as u32) << 24);
            for k in 0..8 {
                let bits = (d >> (4 * k)) & 0xF;
                let pos = (bits & 0b11).count_ones() as i16;
                let neg = ((bits >> 2) & 0b11).count_ones() as i16;
                coeffs[idx * 8 + k] = pos - neg;
            }
        }
    }
    cbd_to_poly(&coeffs)
}

fn byte_encode(d: usize, coeffs: &[u16; 256]) -> Vec<u8> {
    let mut bytes = vec![0u8; 32 * d];
    for i in 0..256 {
        let mut a = coeffs[i];
        for j in 0..d {
            let idx = i * d + j;
            bytes[idx / 8] |= ((a & 1) as u8) << (idx % 8);
            a >>= 1;
        }
    }
    bytes
}

fn byte_decode(d: usize, bytes: &[u8]) -> [u16; 256] {
    let mut f = [0u16; 256];
    for i in 0..256 {
        let mut v = 0u16;
        for j in 0..d {
            let idx = i * d + j;
            v |= (((bytes[idx / 8] >> (idx % 8)) & 1) as u16) << j;
        }
        if d == 12 {
            v %= Q;
        }
        f[i] = v;
    }
    f
}

fn compress(d: usize, x: u16) -> u16 {
    let a = ((x as u64) << d) + 1665;
    ((a * ((1u64 << 34) / 3329) >> 34) & ((1u64 << d) - 1)) as u16
}

fn decompress(d: usize, y: u16) -> u16 {
    (((y as u64) * 3329 + (1u64 << (d - 1))) >> d) as u16
}

fn kpke_keygen(d: &[u8; 32]) -> (Vec<u8>, Vec<u8>, KeygenMid) {
    let mut gd = [0u8; 33];
    gd[..32].copy_from_slice(d);
    gd[32] = K as u8;
    let out = g(&gd);
    let mut rho = [0u8; 32];
    let mut sigma = [0u8; 32];
    rho.copy_from_slice(&out[..32]);
    sigma.copy_from_slice(&out[32..]);

    let mut a = [[0u16; 256]; 9];
    for i in 0..3 {
        for j in 0..3 {
            a[i * 3 + j] = sample_ntt_poly(&rho, j as u8, i as u8);
        }
    }

    let mut s = [[0u16; 256]; 3];
    let mut e = [[0u16; 256]; 3];
    for i in 0..3 {
        s[i] = prf_poly(&sigma, i as u8, ETA1);
    }
    for i in 0..3 {
        e[i] = prf_poly(&sigma, (i + 3) as u8, ETA1);
    }

    let mut sh = s;
    let mut eh = e;
    for poly in sh.iter_mut() {
        ntt::ntt(poly);
    }
    for poly in eh.iter_mut() {
        ntt::ntt(poly);
    }

    let mut th = ntt::matmul(&a, &sh, false);
    for i in 0..3 {
        for k in 0..256 {
            th[i][k] = (th[i][k] + eh[i][k]) % Q;
        }
    }

    let mut ek = Vec::with_capacity(EK_LEN);
    for i in 0..3 {
        ek.extend_from_slice(&byte_encode(12, &th[i]));
    }
    ek.extend_from_slice(&rho);

    let mut dk = Vec::with_capacity(DK_PKE_LEN);
    for i in 0..3 {
        dk.extend_from_slice(&byte_encode(12, &sh[i]));
    }
    (
        ek,
        dk,
        KeygenMid {
            rho,
            sigma,
            a: a.concat().to_vec(),
            s: s.concat().to_vec(),
            e: e.concat().to_vec(),
            sh: sh.concat().to_vec(),
            eh: eh.concat().to_vec(),
            th: th.concat().to_vec(),
        },
    )
}

pub fn kpke_keygen_mid(d: &[u8; 32]) -> (Vec<u8>, Vec<u8>, KeygenMid) {
    kpke_keygen(d)
}

fn dot3(a: &[[u16; 256]; 3], b: &[[u16; 256]; 3]) -> [u16; 256] {
    let mut c = [0u16; 256];
    for k in 0..128 {
        let mut acc0 = 0u16;
        let mut acc1 = 0u16;
        for j in 0..3 {
            let r = ntt::basemul(
                &[a[j][2 * k], a[j][2 * k + 1]],
                &[b[j][2 * k], b[j][2 * k + 1]],
                ntt::GAMMAS[k],
            );
            acc0 = (acc0 + r[0]) % Q;
            acc1 = (acc1 + r[1]) % Q;
        }
        c[2 * k] = acc0;
        c[2 * k + 1] = acc1;
    }
    c
}

fn kpke_encrypt(ek: &[u8], m: &[u8; 32], r: &[u8; 32]) -> (Vec<u8>, EncapsMid) {
    let mut th = [[0u16; 256]; 3];
    for i in 0..3 {
        th[i] = byte_decode(12, &ek[384 * i..384 * i + 384]);
    }
    let mut rho = [0u8; 32];
    rho.copy_from_slice(&ek[1152..1184]);

    let mut a = [[0u16; 256]; 9];
    for i in 0..3 {
        for j in 0..3 {
            a[i * 3 + j] = sample_ntt_poly(&rho, j as u8, i as u8);
        }
    }

    let mut y = [[0u16; 256]; 3];
    let mut e1 = [[0u16; 256]; 3];
    for i in 0..3 {
        y[i] = prf_poly(r, i as u8, ETA1);
    }
    for i in 0..3 {
        e1[i] = prf_poly(r, (i + 3) as u8, ETA2);
    }
    let e2 = prf_poly(r, 6, ETA2);

    let mut yh = y;
    for poly in yh.iter_mut() {
        ntt::ntt(poly);
    }

    let mut u = ntt::matmul(&a, &yh, true);
    for poly in u.iter_mut() {
        ntt::invntt(poly);
    }
    for i in 0..3 {
        for k in 0..256 {
            u[i][k] = (u[i][k] + e1[i][k]) % Q;
        }
    }

    let mb = byte_decode(1, m);
    let mut mu = [0u16; 256];
    for k in 0..256 {
        mu[k] = decompress(1, mb[k]);
    }

    let mut v = dot3(&th, &yh);
    ntt::invntt(&mut v);
    for k in 0..256 {
        v[k] = (v[k] + e2[k] + mu[k]) % Q;
    }

    let mut c = Vec::with_capacity(CT_LEN);
    for i in 0..3 {
        let cu: Vec<u16> = u[i].iter().map(|&x| compress(DU, x)).collect();
        c.extend_from_slice(&byte_encode(DU, &cu.try_into().unwrap()));
    }
    let cv: Vec<u16> = v.iter().map(|&x| compress(DV, x)).collect();
    c.extend_from_slice(&byte_encode(DV, &cv.try_into().unwrap()));
    (
        c,
        EncapsMid {
            hek: [0; 32],
            k: [0; 32],
            r: *r,
            th: th.concat().to_vec(),
            rho,
            a: a.concat().to_vec(),
            y: y.concat().to_vec(),
            e1: e1.concat().to_vec(),
            e2: e2.to_vec(),
            yh: yh.concat().to_vec(),
            u: u.concat().to_vec(),
            mu: mu.to_vec(),
            v: v.to_vec(),
        },
    )
}

fn kpke_decrypt(dk: &[u8], c: &[u8]) -> ([u8; 32], DecapsMid) {
    let mut u = [[0u16; 256]; 3];
    for i in 0..3 {
        let mut cu = byte_decode(DU, &c[32 * DU * i..32 * DU * (i + 1)]);
        for k in 0..256 {
            cu[k] = decompress(DU, cu[k]);
        }
        u[i] = cu;
    }
    let mut cv = byte_decode(DV, &c[32 * DU * 3..32 * DU * 3 + 32 * DV]);
    for k in 0..256 {
        cv[k] = decompress(DV, cv[k]);
    }

    let mut sh = [[0u16; 256]; 3];
    for i in 0..3 {
        sh[i] = byte_decode(12, &dk[384 * i..384 * i + 384]);
    }

    let mut uh = u;
    for poly in uh.iter_mut() {
        ntt::ntt(poly);
    }
    let mut w = dot3(&sh, &uh);
    ntt::invntt(&mut w);
    for k in 0..256 {
        w[k] = (cv[k] + Q - w[k]) % Q;
    }

    let cw: Vec<u16> = w.iter().map(|&x| compress(1, x)).collect();
    let m = byte_encode(1, &cw.try_into().unwrap()).try_into().unwrap();
    (
        m,
        DecapsMid {
            m,
            u: u.concat().to_vec(),
            v: cv.to_vec(),
            sh: sh.concat().to_vec(),
            uh: uh.concat().to_vec(),
            w: w.to_vec(),
            kp: [0; 32],
            rp: [0; 32],
            kbar: [0; 32],
            cp: Vec::new(),
        },
    )
}

pub fn kpke_decrypt_mid(dk: &[u8], c: &[u8]) -> ([u8; 32], DecapsMid) {
    kpke_decrypt(dk, c)
}

pub fn keygen_internal(d: &[u8; 32], z: &[u8; 32]) -> ([u8; EK_LEN], [u8; DK_LEN]) {
    let (ek_pke, dk_pke, _mid) = kpke_keygen(d);
    let hek = h(&ek_pke);
    let mut dk = Vec::with_capacity(DK_LEN);
    dk.extend_from_slice(&dk_pke);
    dk.extend_from_slice(&ek_pke);
    dk.extend_from_slice(&hek);
    dk.extend_from_slice(z);
    (ek_pke.try_into().unwrap(), dk.try_into().unwrap())
}

pub fn encaps_internal(ek: &[u8; EK_LEN], m: &[u8; 32]) -> ([u8; 32], Vec<u8>) {
    let hek = h(ek);
    let mut ginput = Vec::with_capacity(64);
    ginput.extend_from_slice(m);
    ginput.extend_from_slice(&hek);
    let gout = g(&ginput);
    let mut k = [0u8; 32];
    let mut r = [0u8; 32];
    k.copy_from_slice(&gout[..32]);
    r.copy_from_slice(&gout[32..]);
    let (c, _mid) = kpke_encrypt(ek, m, &r);
    (k, c)
}

pub fn decaps_internal(dk: &[u8; DK_LEN], c: &[u8]) -> [u8; 32] {
    let dk_pke = &dk[..DK_PKE_LEN];
    let ek_pke = &dk[DK_PKE_LEN..DK_PKE_LEN + EK_LEN];
    let h_ek = &dk[DK_PKE_LEN + EK_LEN..DK_PKE_LEN + EK_LEN + 32];
    let z = &dk[DK_PKE_LEN + EK_LEN + 32..];
    let m = kpke_decrypt(dk_pke, c).0;
    let mut ginput = Vec::with_capacity(64);
    ginput.extend_from_slice(&m);
    ginput.extend_from_slice(h_ek);
    let gout = g(&ginput);
    let mut kp = [0u8; 32];
    let mut rp = [0u8; 32];
    kp.copy_from_slice(&gout[..32]);
    rp.copy_from_slice(&gout[32..]);
    let mut jz = Vec::with_capacity(32 + 1088);
    jz.extend_from_slice(z);
    jz.extend_from_slice(c);
    let kbar = j(&jz);
    let (cp, _mid) = kpke_encrypt(ek_pke, &m, &rp);
    if cp == c { kp } else { kbar }
}

pub fn keygen_mid(d: &[u8; 32], z: &[u8; 32]) -> (([u8; EK_LEN], [u8; DK_LEN]), KeygenMid) {
    let (ek_pke, dk_pke, mid) = kpke_keygen(d);
    let hek = h(&ek_pke);
    let mut dk = Vec::with_capacity(DK_LEN);
    dk.extend_from_slice(&dk_pke);
    dk.extend_from_slice(&ek_pke);
    dk.extend_from_slice(&hek);
    dk.extend_from_slice(z);
    ((ek_pke.try_into().unwrap(), dk.try_into().unwrap()), mid)
}

pub fn encaps_mid(
    ek: &[u8; EK_LEN],
    m: &[u8; 32],
) -> (([u8; 32], Vec<u8>), EncapsMid) {
    let hek = h(ek);
    let mut ginput = Vec::with_capacity(64);
    ginput.extend_from_slice(m);
    ginput.extend_from_slice(&hek);
    let gout = g(&ginput);
    let mut k = [0u8; 32];
    let mut r = [0u8; 32];
    k.copy_from_slice(&gout[..32]);
    r.copy_from_slice(&gout[32..]);
    let (c, mut mid) = kpke_encrypt(ek, m, &r);
    mid.hek = hek;
    mid.k = k;
    ((k, c), mid)
}

pub fn decaps_mid(dk: &[u8; DK_LEN], c: &[u8]) -> ([u8; 32], DecapsMid) {
    let dk_pke = &dk[..DK_PKE_LEN];
    let ek_pke = &dk[DK_PKE_LEN..DK_PKE_LEN + EK_LEN];
    let h_ek = &dk[DK_PKE_LEN + EK_LEN..DK_PKE_LEN + EK_LEN + 32];
    let z = &dk[DK_PKE_LEN + EK_LEN + 32..];
    let (m, mut mid) = kpke_decrypt(dk_pke, c);
    let mut ginput = Vec::with_capacity(64);
    ginput.extend_from_slice(&m);
    ginput.extend_from_slice(h_ek);
    let gout = g(&ginput);
    let mut kp = [0u8; 32];
    let mut rp = [0u8; 32];
    kp.copy_from_slice(&gout[..32]);
    rp.copy_from_slice(&gout[32..]);
    let mut jz = Vec::with_capacity(32 + 1088);
    jz.extend_from_slice(z);
    jz.extend_from_slice(c);
    let kbar = j(&jz);
    let (cp, _enc_mid) = kpke_encrypt(ek_pke, &m, &rp);
    mid.kp = kp;
    mid.rp = rp;
    mid.kbar = kbar;
    mid.cp = cp.clone();
    let out = if cp == c { kp } else { kbar };
    (out, mid)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip() {
        let (ek, dk) = keygen_internal(&[1u8; 32], &[2u8; 32]);
        let (k, c) = encaps_internal(&ek, &[3u8; 32]);
        assert_eq!(c.len(), CT_LEN);
        let k2 = decaps_internal(&dk, &c);
        assert_eq!(k, k2);
    }

    #[test]
    fn wrong_ct_rejected() {
        let (ek, dk) = keygen_internal(&[1u8; 32], &[2u8; 32]);
        let (k, mut c) = encaps_internal(&ek, &[3u8; 32]);
        c[0] ^= 1;
        let k2 = decaps_internal(&dk, &c);
        assert_ne!(k, k2);
    }

    #[test]
    fn different_seed_differs() {
        let (ek1, _) = keygen_internal(&[1u8; 32], &[2u8; 32]);
        let (ek2, _) = keygen_internal(&[9u8; 32], &[2u8; 32]);
        assert_ne!(ek1, ek2);
    }
}
