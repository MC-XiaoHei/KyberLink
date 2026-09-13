use crate::ntt;
use crate::shake;

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
    pub a: [u16; 2304],
    pub s: [u16; 768],
    pub e: [u16; 768],
    pub sh: [u16; 768],
    pub eh: [u16; 768],
    pub th: [u16; 768],
}

#[derive(Clone, Debug)]
pub struct EncapsMid {
    pub hek: [u8; 32],
    pub k: [u8; 32],
    pub r: [u8; 32],
    pub th: [u16; 768],
    pub rho: [u8; 32],
    pub a: [u16; 2304],
    pub y: [u16; 768],
    pub e1: [u16; 768],
    pub e2: [u16; 256],
    pub yh: [u16; 768],
    pub u: [u16; 768],
    pub mu: [u16; 256],
    pub v: [u16; 256],
}

#[derive(Clone, Debug)]
pub struct DecapsMid {
    pub m: [u8; 32],
    pub u: [u16; 768],
    pub v: [u16; 256],
    pub sh: [u16; 768],
    pub uh: [u16; 768],
    pub w: [u16; 256],
    pub kp: [u8; 32],
    pub rp: [u8; 32],
    pub kbar: [u8; 32],
    pub cp: [u8; CT_LEN],
}

fn concat3(a: &[[u16; 256]; 3]) -> [u16; 768] {
    let mut out = [0u16; 768];
    for i in 0..3 {
        out[i * 256..(i + 1) * 256].copy_from_slice(&a[i]);
    }
    out
}

fn concat9(a: &[[u16; 256]; 9]) -> [u16; 2304] {
    let mut out = [0u16; 2304];
    for i in 0..9 {
        out[i * 256..(i + 1) * 256].copy_from_slice(&a[i]);
    }
    out
}

fn h(x: &[u8]) -> [u8; 32] {
    shake::sha3_256(x)
}

fn g(x: &[u8]) -> [u8; 64] {
    shake::sha3_512(x)
}

fn j(x: &[u8]) -> [u8; 32] {
    let mut out = [0u8; 32];
    shake::shake256_squeeze(&[x], &mut out);
    out
}

fn sample_ntt_poly(rho: &[u8; 32], j: u8, i: u8) -> [u16; 256] {
    let mut seed = [0u8; 34];
    seed[..32].copy_from_slice(rho);
    seed[32] = j;
    seed[33] = i;
    let mut stream = [0u8; 840];
    shake::shake128_squeeze(&[&seed], &mut stream);
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
    for (oc, &cc) in f.iter_mut().zip(c.iter()) {
        *oc = cc.rem_euclid(Q as i16) as u16;
    }
    f
}

fn prf_poly(seed: &[u8; 32], b: u8, eta: usize) -> [u16; 256] {
    let mut out = [0u8; 192];
    shake::shake256_squeeze(&[seed, &[b]], &mut out[..64 * eta]);
    let mut coeffs = [0i16; 256];
    if eta == 3 {
        for (idx, w) in out[..64 * eta].chunks(3).enumerate() {
            let d = w[0] as u32 | ((w[1] as u32) << 8) | ((w[2] as u32) << 16);
            for k in 0..4 {
                let bits = (d >> (6 * k)) & 0x3F;
                let pos = (bits & 0b111).count_ones() as i16;
                let neg = ((bits >> 3) & 0b111).count_ones() as i16;
                coeffs[idx * 4 + k] = pos - neg;
            }
        }
    } else {
        for (idx, b) in out[..64 * eta].chunks(4).enumerate() {
            let d =
                b[0] as u32 | ((b[1] as u32) << 8) | ((b[2] as u32) << 16) | ((b[3] as u32) << 24);
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

fn byte_encode(d: usize, coeffs: &[u16; 256], out: &mut [u8]) {
    debug_assert!(out.len() >= 32 * d);
    for (i, &c) in coeffs.iter().enumerate() {
        let mut a = c;
        for j in 0..d {
            let idx = i * d + j;
            out[idx / 8] |= ((a & 1) as u8) << (idx % 8);
            a >>= 1;
        }
    }
}

fn byte_decode(d: usize, bytes: &[u8]) -> [u16; 256] {
    let mut f = [0u16; 256];
    for (i, o) in f.iter_mut().enumerate() {
        let mut v = 0u16;
        for j in 0..d {
            let idx = i * d + j;
            v |= (((bytes[idx / 8] >> (idx % 8)) & 1) as u16) << j;
        }
        if d == 12 {
            v %= Q;
        }
        *o = v;
    }
    f
}

fn compress(d: usize, x: u16) -> u16 {
    let a = ((x as u64) << d) + 1665;
    (((a * ((1u64 << 34) / 3329)) >> 34) & ((1u64 << d) - 1)) as u16
}

fn decompress(d: usize, y: u16) -> u16 {
    (((y as u64) * 3329 + (1u64 << (d - 1))) >> d) as u16
}

fn kpke_keygen(d: &[u8; 32]) -> ([u8; EK_LEN], [u8; DK_PKE_LEN], KeygenMid) {
    let mut gd = [0u8; 33];
    gd[..32].copy_from_slice(d);
    gd[32] = K as u8;
    let out = g(&gd);
    let mut rho = [0u8; 32];
    let mut sigma = [0u8; 32];
    rho.copy_from_slice(&out[..32]);
    sigma.copy_from_slice(&out[32..]);

    let mut a = [[0u16; 256]; 9];
    for (i, row) in a.as_chunks_mut::<3>().0.iter_mut().enumerate() {
        for (j, cell) in row.iter_mut().enumerate() {
            *cell = sample_ntt_poly(&rho, j as u8, i as u8);
        }
    }

    let mut s = [[0u16; 256]; 3];
    let mut e = [[0u16; 256]; 3];
    for (i, p) in s.iter_mut().enumerate() {
        *p = prf_poly(&sigma, i as u8, ETA1);
    }
    for (i, p) in e.iter_mut().enumerate() {
        *p = prf_poly(&sigma, (i + 3) as u8, ETA1);
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
    for (tp, ep) in th.iter_mut().zip(eh.iter()) {
        for (tc, &ec) in tp.iter_mut().zip(ep.iter()) {
            *tc = (*tc + ec) % Q;
        }
    }

    let mut ek = [0u8; EK_LEN];
    for i in 0..3 {
        byte_encode(12, &th[i], &mut ek[384 * i..384 * (i + 1)]);
    }
    ek[1152..1184].copy_from_slice(&rho);

    let mut dk = [0u8; DK_PKE_LEN];
    for i in 0..3 {
        byte_encode(12, &sh[i], &mut dk[384 * i..384 * (i + 1)]);
    }
    (
        ek,
        dk,
        KeygenMid {
            rho,
            sigma,
            a: concat9(&a),
            s: concat3(&s),
            e: concat3(&e),
            sh: concat3(&sh),
            eh: concat3(&eh),
            th: concat3(&th),
        },
    )
}

pub fn kpke_keygen_mid(d: &[u8; 32]) -> ([u8; EK_LEN], [u8; DK_PKE_LEN], KeygenMid) {
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

fn kpke_encrypt(ek: &[u8], m: &[u8; 32], r: &[u8; 32]) -> ([u8; CT_LEN], EncapsMid) {
    let mut th = [[0u16; 256]; 3];
    for (i, p) in th.iter_mut().enumerate() {
        *p = byte_decode(12, &ek[384 * i..384 * i + 384]);
    }
    let mut rho = [0u8; 32];
    rho.copy_from_slice(&ek[1152..1184]);

    let mut a = [[0u16; 256]; 9];
    for (i, row) in a.as_chunks_mut::<3>().0.iter_mut().enumerate() {
        for (j, cell) in row.iter_mut().enumerate() {
            *cell = sample_ntt_poly(&rho, j as u8, i as u8);
        }
    }

    let mut y = [[0u16; 256]; 3];
    let mut e1 = [[0u16; 256]; 3];
    for (i, p) in y.iter_mut().enumerate() {
        *p = prf_poly(r, i as u8, ETA1);
    }
    for (i, p) in e1.iter_mut().enumerate() {
        *p = prf_poly(r, (i + 3) as u8, ETA2);
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
    for (up, e1p) in u.iter_mut().zip(e1.iter()) {
        for (uc, &ec) in up.iter_mut().zip(e1p.iter()) {
            *uc = (*uc + ec) % Q;
        }
    }

    let mb = byte_decode(1, m);
    let mut mu = [0u16; 256];
    for (oc, &mc) in mu.iter_mut().zip(mb.iter()) {
        *oc = decompress(1, mc);
    }

    let mut v = dot3(&th, &yh);
    ntt::invntt(&mut v);
    for k in 0..256 {
        v[k] = (v[k] + e2[k] + mu[k]) % Q;
    }

    let mut c = [0u8; CT_LEN];
    for i in 0..3 {
        let mut cu = [0u16; 256];
        for k in 0..256 {
            cu[k] = compress(DU, u[i][k]);
        }
        byte_encode(DU, &cu, &mut c[32 * DU * i..32 * DU * (i + 1)]);
    }
    let mut cv = [0u16; 256];
    for k in 0..256 {
        cv[k] = compress(DV, v[k]);
    }
    byte_encode(DV, &cv, &mut c[32 * DU * 3..32 * DU * 3 + 32 * DV]);
    (
        c,
        EncapsMid {
            hek: [0; 32],
            k: [0; 32],
            r: *r,
            th: concat3(&th),
            rho,
            a: concat9(&a),
            y: concat3(&y),
            e1: concat3(&e1),
            e2,
            yh: concat3(&yh),
            u: concat3(&u),
            mu,
            v,
        },
    )
}

fn kpke_decrypt(dk: &[u8], c: &[u8]) -> ([u8; 32], DecapsMid) {
    let mut u = [[0u16; 256]; 3];
    for (i, p) in u.iter_mut().enumerate() {
        let mut cu = byte_decode(DU, &c[32 * DU * i..32 * DU * (i + 1)]);
        for c_ in cu.iter_mut() {
            *c_ = decompress(DU, *c_);
        }
        *p = cu;
    }
    let mut cv = byte_decode(DV, &c[32 * DU * 3..32 * DU * 3 + 32 * DV]);
    for c_ in cv.iter_mut() {
        *c_ = decompress(DV, *c_);
    }

    let mut sh = [[0u16; 256]; 3];
    for (i, p) in sh.iter_mut().enumerate() {
        *p = byte_decode(12, &dk[384 * i..384 * i + 384]);
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

    let mut cw = [0u16; 256];
    for k in 0..256 {
        cw[k] = compress(1, w[k]);
    }
    let mut m = [0u8; 32];
    byte_encode(1, &cw, &mut m);
    (
        m,
        DecapsMid {
            m,
            u: concat3(&u),
            v: cv,
            sh: concat3(&sh),
            uh: concat3(&uh),
            w,
            kp: [0; 32],
            rp: [0; 32],
            kbar: [0; 32],
            cp: [0; CT_LEN],
        },
    )
}

pub fn kpke_decrypt_mid(dk: &[u8], c: &[u8]) -> ([u8; 32], DecapsMid) {
    kpke_decrypt(dk, c)
}

pub fn keygen_internal(d: &[u8; 32], z: &[u8; 32]) -> ([u8; EK_LEN], [u8; DK_LEN]) {
    let (ek_pke, dk_pke, _mid) = kpke_keygen(d);
    let hek = h(&ek_pke);
    let mut dk = [0u8; DK_LEN];
    dk[..DK_PKE_LEN].copy_from_slice(&dk_pke);
    dk[DK_PKE_LEN..DK_PKE_LEN + EK_LEN].copy_from_slice(&ek_pke);
    dk[DK_PKE_LEN + EK_LEN..DK_PKE_LEN + EK_LEN + 32].copy_from_slice(&hek);
    dk[DK_PKE_LEN + EK_LEN + 32..].copy_from_slice(z);
    (ek_pke, dk)
}

pub fn encaps_internal(ek: &[u8; EK_LEN], m: &[u8; 32]) -> ([u8; 32], [u8; CT_LEN]) {
    let hek = h(ek);
    let mut ginput = [0u8; 64];
    ginput[..32].copy_from_slice(m);
    ginput[32..].copy_from_slice(&hek);
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
    let mut ginput = [0u8; 64];
    ginput[..32].copy_from_slice(&m);
    ginput[32..].copy_from_slice(h_ek);
    let gout = g(&ginput);
    let mut kp = [0u8; 32];
    let mut rp = [0u8; 32];
    kp.copy_from_slice(&gout[..32]);
    rp.copy_from_slice(&gout[32..]);
    let mut jz = [0u8; 32 + CT_LEN];
    jz[..32].copy_from_slice(z);
    jz[32..].copy_from_slice(c);
    let kbar = j(&jz);
    let (cp, _mid) = kpke_encrypt(ek_pke, &m, &rp);
    if cp == c {
        kp
    } else {
        kbar
    }
}

pub fn keygen_mid(d: &[u8; 32], z: &[u8; 32]) -> (([u8; EK_LEN], [u8; DK_LEN]), KeygenMid) {
    let (ek_pke, dk_pke, mid) = kpke_keygen(d);
    let hek = h(&ek_pke);
    let mut dk = [0u8; DK_LEN];
    dk[..DK_PKE_LEN].copy_from_slice(&dk_pke);
    dk[DK_PKE_LEN..DK_PKE_LEN + EK_LEN].copy_from_slice(&ek_pke);
    dk[DK_PKE_LEN + EK_LEN..DK_PKE_LEN + EK_LEN + 32].copy_from_slice(&hek);
    dk[DK_PKE_LEN + EK_LEN + 32..].copy_from_slice(z);
    ((ek_pke, dk), mid)
}

pub fn encaps_mid(ek: &[u8; EK_LEN], m: &[u8; 32]) -> (([u8; 32], [u8; CT_LEN]), EncapsMid) {
    let hek = h(ek);
    let mut ginput = [0u8; 64];
    ginput[..32].copy_from_slice(m);
    ginput[32..].copy_from_slice(&hek);
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
    let mut ginput = [0u8; 64];
    ginput[..32].copy_from_slice(&m);
    ginput[32..].copy_from_slice(h_ek);
    let gout = g(&ginput);
    let mut kp = [0u8; 32];
    let mut rp = [0u8; 32];
    kp.copy_from_slice(&gout[..32]);
    rp.copy_from_slice(&gout[32..]);
    let mut jz = [0u8; 32 + CT_LEN];
    jz[..32].copy_from_slice(z);
    jz[32..].copy_from_slice(c);
    let kbar = j(&jz);
    let (cp, _enc_mid) = kpke_encrypt(ek_pke, &m, &rp);
    mid.kp = kp;
    mid.rp = rp;
    mid.kbar = kbar;
    mid.cp = cp;
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
