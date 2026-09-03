use crate::shake;

const Q: u64 = 8380417;
const K: usize = 6;
const L: usize = 5;
const ETA: u64 = 4;
pub const TAU: usize = 49;
const GAMMA1: u64 = 524288;
const GAMMA2: u64 = 261888;
const TWO_GAMMA2: u64 = 523776;
const BETA: u64 = 196;
const OMEGA: usize = 55;
const LAMBDA: usize = 48;
const D: usize = 13;
const GAMMA1_MINUS_BETA: u64 = GAMMA1 - BETA;
const GAMMA2_MINUS_BETA: u64 = GAMMA2 - BETA;

pub const VK_LEN: usize = 1952;
pub const SK_LEN: usize = 4032;
pub const SIG_LEN: usize = 3309;

fn h(x: &[u8]) -> [u8; 64] {
    let mut out = [0u8; 64];
    shake::shake256_squeeze(&[x], &mut out);
    out
}

pub fn ntt(a: &mut [u64; 256]) {
    crate::mldsa_mont::ntt(a);
}

pub fn invntt(a: &mut [u64; 256]) {
    crate::mldsa_mont::invntt(a);
}

pub fn rej_ntt_poly(rho: &[u8], r: u8, s: u8) -> [u64; 256] {
    let mut seed = [0u8; 34];
    seed[..32].copy_from_slice(rho);
    seed[32] = s;
    seed[33] = r;
    let mut f = [0u64; 256];
    let mut n = 0usize;
    let mut buf = [0u8; 4096];
    shake::shake128_squeeze(&[&seed], &mut buf);
    let mut pos = 0usize;
    while n < 256 && pos + 2 < 4096 {
        let b2 = buf[pos + 2] as u32 - if buf[pos + 2] > 127 { 128 } else { 0 };
        let z = ((b2 as u64) << 16) | ((buf[pos + 1] as u64) << 8) | (buf[pos] as u64);
        pos += 3;
        if z < Q {
            f[n] = z;
            n += 1;
        }
    }
    f
}

pub fn rej_bounded_poly(rho: &[u8], r: u16) -> [u64; 256] {
    let mut seed = [0u8; 66];
    seed[..64].copy_from_slice(rho);
    seed[64] = (r & 0xff) as u8;
    seed[65] = (r >> 8) as u8;
    let mut f = [0u64; 256];
    let mut n = 0usize;
    let mut buf = [0u8; 1024];
    shake::shake256_squeeze(&[&seed], &mut buf);
    let mut pos = 0usize;
    while n < 256 && pos < 1024 {
        let lo = buf[pos] & 0x0F;
        let hi = buf[pos] >> 4;
        pos += 1;
        for cc in [lo, hi] {
            if cc < 9 {
                let cv = cc as u64;
                let coeff = if cv <= 4 { 4 - cv } else { Q - (cv - 4) };
                f[n] = coeff;
                n += 1;
                if n == 256 {
                    break;
                }
            }
        }
    }
    f
}

pub fn expand_mask_poly(rho: &[u8], mu: u16) -> [u64; 256] {
    let mut seed = [0u8; 66];
    seed[..64].copy_from_slice(rho);
    seed[64] = (mu & 0xff) as u8;
    seed[65] = (mu >> 8) as u8;
    let mut bytes = [0u8; 640];
    shake::shake256_squeeze(&[&seed], &mut bytes);
    let mut y = [0u64; 256];
    for (k, oc) in y.iter_mut().enumerate() {
        let mut v = 0u64;
        for j in 0..20 {
            let idx = k * 20 + j;
            v |= (((bytes[idx / 8] >> (idx % 8)) & 1) as u64) << j;
        }
        *oc = (GAMMA1 + Q - v) % Q;
    }
    y
}

pub fn sample_in_ball(rho: &[u8], tau: usize) -> [u64; 256] {
    let mut c = [0u64; 256];
    let mut buf = [0u8; 2048];
    shake::shake256_squeeze(&[rho], &mut buf);
    let s = [
        buf[0], buf[1], buf[2], buf[3], buf[4], buf[5], buf[6], buf[7],
    ];
    let mut pos = 8usize;
    for i in (256 - tau)..256 {
        let mut jb;
        loop {
            jb = buf[pos];
            pos += 1;
            if (jb as usize) <= i {
                break;
            }
        }
        let j = jb as usize;
        c[i] = c[j];
        let bit = (s[(i + tau - 256) >> 3] >> ((i + tau - 256) & 7)) & 1;
        c[j] = if bit == 1 { Q - 1 } else { 1 };
    }
    c
}

fn pack(d: usize, coeffs: &[u64], out: &mut [u8]) {
    for (i, &c) in coeffs.iter().enumerate() {
        let mut a = c;
        for j in 0..d {
            let idx = i * d + j;
            out[idx / 8] |= ((a & 1) as u8) << (idx % 8);
            a >>= 1;
        }
    }
}

fn unpack(d: usize, bytes: &[u8], out: &mut [u64]) {
    for (i, o) in out.iter_mut().enumerate() {
        let mut v = 0u64;
        for j in 0..d {
            let idx = i * d + j;
            v |= (((bytes[idx / 8] >> (idx % 8)) & 1) as u64) << j;
        }
        *o = v;
    }
}

fn mod_plus_minus(x: u64, m: u64) -> u64 {
    let r = x % m;
    if r > m >> 1 {
        r + Q - m
    } else {
        r
    }
}

fn power2round(x: u64) -> (u64, u64) {
    let r0 = mod_plus_minus(x, 1 << D);
    let r1 = ((x + Q - r0) % Q) >> D;
    (r1, r0)
}

fn decompose(x: u64) -> (u64, u64) {
    let r0 = mod_plus_minus(x, TWO_GAMMA2);
    let diff = (x + Q - r0) % Q;
    if diff == Q - 1 {
        (0, (r0 + Q - 1) % Q)
    } else {
        (diff / TWO_GAMMA2, r0)
    }
}

fn high_bits(x: u64) -> u64 {
    decompose(x).0
}

fn low_bits(x: u64) -> u64 {
    decompose(x).1
}

fn make_hint(z: u64, r: u64) -> bool {
    high_bits((r + z) % Q) != high_bits(r)
}

fn use_hint(h: bool, r: u64) -> u64 {
    let m = (Q - 1) / TWO_GAMMA2;
    let (r1, r0) = decompose(r);
    if h {
        if r0 > 0 && r0 <= GAMMA2 {
            (r1 + 1) % m
        } else {
            (r1 + m - 1) % m
        }
    } else {
        r1
    }
}

fn infinity_norm(p: &[u64]) -> u64 {
    p.iter()
        .map(|&x| if x > Q / 2 { Q - x } else { x })
        .max()
        .unwrap()
}

fn ntt_vec<const N: usize>(v: &[[u64; 256]; N]) -> [[u64; 256]; N] {
    let mut out = *v;
    for p in out.iter_mut() {
        ntt(p);
    }
    out
}

fn invntt_vec<const N: usize>(v: &[[u64; 256]; N]) -> [[u64; 256]; N] {
    let mut out = *v;
    for p in out.iter_mut() {
        invntt(p);
    }
    out
}

fn poly_mul_ntt(a: &[u64; 256], b: &[u64; 256]) -> [u64; 256] {
    let mut c = [0u64; 256];
    for ((oc, &ac), &bc) in c.iter_mut().zip(a.iter()).zip(b.iter()) {
        *oc = ac * bc % Q;
    }
    c
}

pub fn mat_mul_vec(a: &[[u64; 256]; K * L], v: &[[u64; 256]; L]) -> [[u64; 256]; K] {
    let mut out = [[0u64; 256]; K];
    for (i, row) in a.chunks_exact(L).enumerate() {
        for k in 0..256 {
            let acc = row
                .iter()
                .zip(v.iter())
                .fold(0u64, |acc, (ar, vr)| (acc + ar[k] * vr[k]) % Q);
            out[i][k] = acc;
        }
    }
    out
}

fn encode_s<const N: usize>(s: &[[u64; 256]; N], out: &mut [u8]) {
    let mut flat = [0u64; 1536];
    let mut fi = 0;
    for p in s {
        for &c in p.iter() {
            flat[fi] = (ETA + Q - c) % Q;
            fi += 1;
        }
    }
    pack(4, &flat[..N * 256], out);
}

fn decode_s<const N: usize>(bytes: &[u8]) -> [[u64; 256]; N] {
    let mut flat = [0u64; 1536];
    unpack(4, bytes, &mut flat[..N * 256]);
    let mut out = [[0u64; 256]; N];
    for (op, fp) in out.iter_mut().zip(flat.chunks_exact(256)) {
        for (oc, &fc) in op.iter_mut().zip(fp.iter()) {
            *oc = (ETA + Q - fc) % Q;
        }
    }
    out
}

fn encode_t0<const N: usize>(t0: &[[u64; 256]; N], out: &mut [u8]) {
    let mut flat = [0u64; 1536];
    let mut fi = 0;
    for p in t0 {
        for &c in p.iter() {
            flat[fi] = ((1 << (D - 1)) + Q - c) % Q;
            fi += 1;
        }
    }
    pack(D, &flat[..N * 256], out);
}

fn decode_t0<const N: usize>(bytes: &[u8]) -> [[u64; 256]; N] {
    let mut flat = [0u64; 1536];
    unpack(D, bytes, &mut flat[..N * 256]);
    let mut out = [[0u64; 256]; N];
    for (op, fp) in out.iter_mut().zip(flat.chunks_exact(256)) {
        for (oc, &fc) in op.iter_mut().zip(fp.iter()) {
            *oc = ((1 << (D - 1)) + Q - fc) % Q;
        }
    }
    out
}

fn encode_t1<const N: usize>(t1: &[[u64; 256]; N], out: &mut [u8]) {
    let mut flat = [0u64; 1536];
    let mut fi = 0;
    for p in t1 {
        for &c in p.iter() {
            flat[fi] = c;
            fi += 1;
        }
    }
    pack(10, &flat[..N * 256], out);
}

fn decode_t1<const N: usize>(bytes: &[u8]) -> [[u64; 256]; N] {
    let mut flat = [0u64; 1536];
    unpack(10, bytes, &mut flat[..N * 256]);
    let mut out = [[0u64; 256]; N];
    for (op, fp) in out.iter_mut().zip(flat.chunks_exact(256)) {
        for (oc, &fc) in op.iter_mut().zip(fp.iter()) {
            *oc = fc;
        }
    }
    out
}

fn encode_w1<const N: usize>(w1: &[[u64; 256]; N], out: &mut [u8]) {
    let mut flat = [0u64; 1536];
    let mut fi = 0;
    for p in w1 {
        for &c in p.iter() {
            flat[fi] = c;
            fi += 1;
        }
    }
    pack(4, &flat[..N * 256], out);
}

fn decode_z<const N: usize>(bytes: &[u8]) -> [[u64; 256]; N] {
    let mut flat = [0u64; 1536];
    unpack(20, bytes, &mut flat[..N * 256]);
    let mut out = [[0u64; 256]; N];
    for (op, fp) in out.iter_mut().zip(flat.chunks_exact(256)) {
        for (oc, &w) in op.iter_mut().zip(fp.iter()) {
            *oc = if w <= GAMMA1 {
                (GAMMA1 - w) % Q
            } else {
                Q - (w - GAMMA1) % Q
            };
        }
    }
    out
}

fn encode_z<const N: usize>(z: &[[u64; 256]; N], out: &mut [u8]) {
    let mut flat = [0u64; 1536];
    let mut fi = 0;
    for p in z {
        for &c in p.iter() {
            flat[fi] = (GAMMA1 + Q - c) % Q;
            fi += 1;
        }
    }
    pack(20, &flat[..N * 256], out);
}

fn pack_h(h: &[[bool; 256]; K]) -> [u8; OMEGA + K] {
    let mut y = [0u8; OMEGA + K];
    let mut idx = 0usize;
    for (i, hp) in h.iter().enumerate() {
        for (j, &hv) in hp.iter().enumerate() {
            if hv {
                y[idx] = j as u8;
                idx += 1;
            }
        }
        y[OMEGA + i] = idx as u8;
    }
    y
}

fn unpack_h(bytes: &[u8]) -> Option<[[bool; 256]; K]> {
    let mut h = [[false; 256]; K];
    let mut idx = 0usize;
    let mut prev_end = 0usize;
    for i in 0..K {
        let end = bytes[OMEGA + i] as usize;
        if end > OMEGA || end < prev_end {
            return None;
        }
        prev_end = end;
        let mut prev = usize::MAX;
        while idx < end {
            let j = bytes[idx] as usize;
            if j >= 256 || (prev != usize::MAX && j <= prev) {
                return None;
            }
            idx += 1;
            prev = j;
            h[i][j] = true;
        }
    }
    if bytes[idx..OMEGA].iter().any(|&b| b != 0) {
        return None;
    }
    Some(h)
}

pub fn keygen_internal(seed: &[u8; 32]) -> ([u8; VK_LEN], [u8; SK_LEN]) {
    let mut gd = [0u8; 34];
    gd[..32].copy_from_slice(seed);
    gd[32] = K as u8;
    gd[33] = L as u8;
    let mut gout = [0u8; 128];
    shake::shake256_squeeze(&[&gd], &mut gout);
    let mut rho = [0u8; 32];
    let mut rho2 = [0u8; 64];
    let mut kk = [0u8; 32];
    rho.copy_from_slice(&gout[..32]);
    rho2.copy_from_slice(&gout[32..96]);
    kk.copy_from_slice(&gout[96..128]);

    let mut a_hat = [[0u64; 256]; K * L];
    for (i, row) in a_hat.chunks_exact_mut(L).enumerate() {
        for (j, cell) in row.iter_mut().enumerate() {
            *cell = rej_ntt_poly(&rho, i as u8, j as u8);
        }
    }

    let mut s1 = [[0u64; 256]; L];
    let mut s2 = [[0u64; 256]; K];
    for (i, p) in s1.iter_mut().enumerate() {
        *p = rej_bounded_poly(&rho2, i as u16);
    }
    for (i, p) in s2.iter_mut().enumerate() {
        *p = rej_bounded_poly(&rho2, (L + i) as u16);
    }

    let s1_hat = ntt_vec(&s1);
    let t = mat_mul_vec(&a_hat, &s1_hat);
    let t = invntt_vec(&t);
    let mut t_std = t;
    for (tp, sp) in t_std.iter_mut().zip(s2.iter()) {
        for (tc, &sc) in tp.iter_mut().zip(sp.iter()) {
            *tc = (*tc + sc) % Q;
        }
    }

    let mut t1 = [[0u64; 256]; K];
    let mut t0 = [[0u64; 256]; K];
    for i in 0..K {
        for k in 0..256 {
            let (r1, r0) = power2round(t_std[i][k]);
            t1[i][k] = r1;
            t0[i][k] = r0;
        }
    }

    let mut vk = [0u8; VK_LEN];
    vk[..32].copy_from_slice(&rho);
    encode_t1(&t1, &mut vk[32..]);

    let tr = h(&vk);
    let mut tr64 = [0u8; 64];
    tr64.copy_from_slice(&tr);

    let mut sk = [0u8; SK_LEN];
    sk[..32].copy_from_slice(&rho);
    sk[32..64].copy_from_slice(&kk);
    sk[64..128].copy_from_slice(&tr64);
    encode_s(&s1, &mut sk[128..128 + L * 128]);
    encode_s(&s2, &mut sk[128 + L * 128..128 + L * 128 + K * 128]);
    encode_t0(&t0, &mut sk[128 + L * 128 + K * 128..]);

    (vk, sk)
}

pub fn sign_internal(sk: &[u8; SK_LEN], msg: &[u8], ctx: &[u8]) -> [u8; SIG_LEN] {
    let tr = &sk[64..128];
    let mut mu_b = [0u8; 64];
    shake::shake256_squeeze(&[tr, &[0x00], &[ctx.len() as u8], ctx, msg], &mut mu_b);
    sign_core(sk, &mu_b, &[0u8; 32])
}

pub fn sign_prehash_internal(sk: &[u8; SK_LEN], m2: &[u8], rnd: &[u8; 32]) -> [u8; SIG_LEN] {
    let tr = &sk[64..128];
    let mut mu_b = [0u8; 64];
    shake::shake256_squeeze(&[tr, m2], &mut mu_b);
    sign_core(sk, &mu_b, rnd)
}

pub fn sign_internal_msg(sk: &[u8; SK_LEN], msg: &[u8]) -> [u8; SIG_LEN] {
    sign_prehash_internal(sk, msg, &[0u8; 32])
}

pub fn sign_mu_internal(sk: &[u8; SK_LEN], mu_b: &[u8; 64]) -> [u8; SIG_LEN] {
    sign_core(sk, mu_b, &[0u8; 32])
}

pub fn sign_mu_rnd_internal(sk: &[u8; SK_LEN], mu_b: &[u8; 64], rnd: &[u8; 32]) -> [u8; SIG_LEN] {
    sign_core(sk, mu_b, rnd)
}

pub fn sign_rnd_internal(
    sk: &[u8; SK_LEN],
    msg: &[u8],
    ctx: &[u8],
    rnd: &[u8; 32],
) -> [u8; SIG_LEN] {
    let tr = &sk[64..128];
    let mut mu_b = [0u8; 64];
    shake::shake256_squeeze(&[tr, &[0x00], &[ctx.len() as u8], ctx, msg], &mut mu_b);
    sign_core(sk, &mu_b, rnd)
}

pub fn sign_prehash_rnd_internal(sk: &[u8; SK_LEN], m2: &[u8], rnd: &[u8; 32]) -> [u8; SIG_LEN] {
    let tr = &sk[64..128];
    let mut mu_b = [0u8; 64];
    shake::shake256_squeeze(&[tr, m2], &mut mu_b);
    sign_core(sk, &mu_b, rnd)
}

fn sign_core(sk: &[u8; SK_LEN], mu_b: &[u8; 64], rnd: &[u8; 32]) -> [u8; SIG_LEN] {
    let rho = &sk[..32];
    let kk = &sk[32..64];
    let s1 = decode_s::<L>(&sk[128..128 + L * 128]);
    let s2 = decode_s::<K>(&sk[128 + L * 128..128 + L * 128 + K * 128]);
    let t0 = decode_t0::<K>(&sk[128 + L * 128 + K * 128..]);
    let s1_hat = ntt_vec(&s1);
    let s2_hat = ntt_vec(&s2);
    let t0_hat = ntt_vec(&t0);

    let mut a_hat = [[0u64; 256]; K * L];
    for (i, row) in a_hat.chunks_exact_mut(L).enumerate() {
        for (j, cell) in row.iter_mut().enumerate() {
            *cell = rej_ntt_poly(rho, i as u8, j as u8);
        }
    }

    let mut rhopp = [0u8; 64];
    shake::shake256_squeeze(&[kk, rnd, mu_b], &mut rhopp);

    let mut kappa = 0u16;
    let (c_tilde, z, h);
    loop {
        let mut y = [[0u64; 256]; L];
        for (i, p) in y.iter_mut().enumerate() {
            *p = expand_mask_poly(&rhopp, kappa + i as u16);
        }
        let y_hat = ntt_vec(&y);
        let w = mat_mul_vec(&a_hat, &y_hat);
        let w = invntt_vec(&w);

        let mut w1 = [[0u64; 256]; K];
        for (w1p, wp) in w1.iter_mut().zip(w.iter()) {
            for (wc, &wv) in w1p.iter_mut().zip(wp.iter()) {
                *wc = high_bits(wv);
            }
        }
        let mut w1_tilde = [0u8; K * 128];
        encode_w1(&w1, &mut w1_tilde);

        let mut ctil = [0u8; LAMBDA];
        shake::shake256_squeeze(&[mu_b, &w1_tilde], &mut ctil);

        let c = sample_in_ball(&ctil, TAU);
        let mut c_hat = [0u64; 256];
        c_hat.copy_from_slice(&c);
        ntt(&mut c_hat);

        let mut cs1 = [[0u64; 256]; L];
        let mut cs2 = [[0u64; 256]; K];
        for (o, &s) in cs1.iter_mut().zip(s1_hat.iter()) {
            *o = poly_mul_ntt(&c_hat, &s);
        }
        for (o, &s) in cs2.iter_mut().zip(s2_hat.iter()) {
            *o = poly_mul_ntt(&c_hat, &s);
        }
        let cs1 = invntt_vec(&cs1);
        let cs2 = invntt_vec(&cs2);

        let mut zz = y;
        let mut ok = true;
        let mut w_minus_cs2 = [[0u64; 256]; K];
        for (zp, c1p) in zz.iter_mut().zip(cs1.iter()) {
            for (zc, &c1c) in zp.iter_mut().zip(c1p.iter()) {
                *zc = (*zc + c1c) % Q;
            }
            if infinity_norm(zp) >= GAMMA1_MINUS_BETA {
                ok = false;
            }
        }
        for ((op, wp), c2p) in w_minus_cs2.iter_mut().zip(w.iter()).zip(cs2.iter()) {
            for ((oc, &wv), &c2c) in op.iter_mut().zip(wp.iter()).zip(c2p.iter()) {
                *oc = (wv + Q - c2c) % Q;
            }
        }
        let mut r0 = [[0u64; 256]; K];
        for (rp, wmp) in r0.iter_mut().zip(w_minus_cs2.iter()) {
            for (rc, &wm) in rp.iter_mut().zip(wmp.iter()) {
                *rc = low_bits(wm);
            }
            if infinity_norm(rp) >= GAMMA2_MINUS_BETA {
                ok = false;
            }
        }
        if !ok {
            kappa = kappa.wrapping_add(L as u16);
            continue;
        }

        let mut ct0 = [[0u64; 256]; K];
        for (o, &t) in ct0.iter_mut().zip(t0_hat.iter()) {
            *o = poly_mul_ntt(&c_hat, &t);
        }
        let ct0 = invntt_vec(&ct0);

        let mut hh = [[false; 256]; K];
        let mut wgt = 0usize;
        ok = true;
        for ((hp, cp), wmp) in hh.iter_mut().zip(ct0.iter()).zip(w_minus_cs2.iter()) {
            for ((hc, &cv), &wm) in hp.iter_mut().zip(cp.iter()).zip(wmp.iter()) {
                let nct0 = (Q - cv) % Q;
                let wcc = (wm + cv) % Q;
                *hc = make_hint(nct0, wcc);
                if *hc {
                    wgt += 1;
                }
            }
            if infinity_norm(cp) >= GAMMA2 {
                ok = false;
            }
        }
        if wgt > OMEGA {
            ok = false;
        }
        if !ok {
            kappa = kappa.wrapping_add(L as u16);
            continue;
        }

        c_tilde = ctil;
        z = zz;
        h = hh;
        break;
    }

    let mut sig = [0u8; SIG_LEN];
    sig[..LAMBDA].copy_from_slice(&c_tilde);
    encode_z(&z, &mut sig[LAMBDA..LAMBDA + L * 640]);
    sig[LAMBDA + L * 640..].copy_from_slice(&pack_h(&h));
    sig
}

pub fn verify_internal(vk: &[u8; VK_LEN], msg: &[u8], ctx: &[u8], sig: &[u8; SIG_LEN]) -> bool {
    if ctx.len() > 255 {
        return false;
    }
    let mut tr_b = [0u8; 64];
    shake::shake256_squeeze(&[vk], &mut tr_b);

    let mut mu_b = [0u8; 64];
    shake::shake256_squeeze(&[&tr_b, &[0x00], &[ctx.len() as u8], ctx, msg], &mut mu_b);
    verify_core(vk, &mu_b, sig)
}

pub fn verify_prehash_internal(vk: &[u8; VK_LEN], m2: &[u8], sig: &[u8; SIG_LEN]) -> bool {
    let mut tr_b = [0u8; 64];
    shake::shake256_squeeze(&[vk], &mut tr_b);

    let mut mu_b = [0u8; 64];
    shake::shake256_squeeze(&[&tr_b, m2], &mut mu_b);
    verify_core(vk, &mu_b, sig)
}

pub fn verify_mu_internal(vk: &[u8; VK_LEN], mu_b: &[u8; 64], sig: &[u8; SIG_LEN]) -> bool {
    verify_core(vk, mu_b, sig)
}

fn verify_core(vk: &[u8; VK_LEN], mu_b: &[u8; 64], sig: &[u8; SIG_LEN]) -> bool {
    let rho = &vk[..32];
    let t1 = decode_t1::<K>(&vk[32..]);

    let mut a_hat = [[0u64; 256]; K * L];
    for i in 0..K {
        for j in 0..L {
            a_hat[i * L + j] = rej_ntt_poly(rho, i as u8, j as u8);
        }
    }

    let mut t1_2d = [[0u64; 256]; K];
    for (op, ip) in t1_2d.iter_mut().zip(t1.iter()) {
        for (oc, &ic) in op.iter_mut().zip(ip.iter()) {
            *oc = ic * (1u64 << D) % Q;
        }
    }
    let t1_2d_hat = ntt_vec(&t1_2d);

    let c_tilde = &sig[..LAMBDA];
    let z = decode_z::<L>(&sig[LAMBDA..LAMBDA + L * 640]);
    let h = match unpack_h(&sig[LAMBDA + L * 640..]) {
        Some(h) => h,
        None => return false,
    };
    for zp in z.iter() {
        if infinity_norm(zp) >= GAMMA1_MINUS_BETA {
            return false;
        }
    }

    let c = sample_in_ball(c_tilde, TAU);
    let mut c_hat = [0u64; 256];
    c_hat.copy_from_slice(&c);
    ntt(&mut c_hat);
    let z_hat = ntt_vec(&z);

    let mut az = [[0u64; 256]; K];
    for (i, row) in a_hat.chunks_exact(L).enumerate() {
        for k in 0..256 {
            let acc = row
                .iter()
                .zip(z_hat.iter())
                .fold(0u64, |acc, (ar, zr)| (acc + ar[k] * zr[k]) % Q);
            az[i][k] = acc;
        }
    }
    let mut w_hat = [[0u64; 256]; K];
    for ((op, azp), tp) in w_hat.iter_mut().zip(az.iter()).zip(t1_2d_hat.iter()) {
        for (k, ((oc, &av), &tv)) in op.iter_mut().zip(azp.iter()).zip(tp.iter()).enumerate() {
            let ct1 = c_hat[k] * tv % Q;
            *oc = (av + Q - ct1) % Q;
        }
    }
    let w_approx = invntt_vec(&w_hat);

    let mut w1 = [[0u64; 256]; K];
    for ((op, ap), hp) in w1.iter_mut().zip(w_approx.iter()).zip(h.iter()) {
        for ((oc, &av), &hv) in op.iter_mut().zip(ap.iter()).zip(hp.iter()) {
            *oc = use_hint(hv, av);
        }
    }
    let mut w1_tilde = [0u8; K * 128];
    encode_w1(&w1, &mut w1_tilde);

    let mut ctil = [0u8; LAMBDA];
    shake::shake256_squeeze(&[mu_b, &w1_tilde], &mut ctil);
    ctil == *c_tilde
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip() {
        let (vk, sk) = keygen_internal(&[1u8; 32]);
        let sig = sign_internal(&sk, b"message", &[]);
        assert!(verify_internal(&vk, b"message", &[], &sig));
        assert!(!verify_internal(&vk, b"message2", &[], &sig));
    }
}
