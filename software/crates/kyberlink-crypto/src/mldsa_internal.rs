use crate::shake;

const Q: u32 = 8380417;
const K: usize = 6;
const L: usize = 5;
const ETA: u32 = 4;
pub const TAU: usize = 49;
const GAMMA1: u32 = 524288;
const GAMMA2: u32 = 261888;
const TWO_GAMMA2: u32 = 523776;
const BETA: u32 = 196;
const OMEGA: usize = 55;
const LAMBDA: usize = 48;
const D: usize = 13;
const GAMMA1_MINUS_BETA: u32 = GAMMA1 - BETA;
const GAMMA2_MINUS_BETA: u32 = GAMMA2 - BETA;

pub const VK_LEN: usize = 1952;
pub const SK_LEN: usize = 4032;
pub const SIG_LEN: usize = 3309;

fn h(x: &[u8]) -> [u8; 64] {
    let mut out = [0u8; 64];
    shake::shake256_squeeze(&[x], &mut out);
    out
}

pub fn ntt(a: &mut [u32; 256]) {
    crate::mldsa_mont::ntt(a);
}

pub fn invntt(a: &mut [u32; 256]) {
    crate::mldsa_mont::invntt(a);
}

pub fn rej_ntt_poly(rho: &[u8], r: u8, s: u8) -> [u32; 256] {
    let mut seed = [0u8; 34];
    seed[..32].copy_from_slice(rho);
    seed[32] = s;
    seed[33] = r;
    let mut f = [0u32; 256];
    let mut n = 0usize;
    let mut buf = [0u8; 1008];
    shake::shake128_squeeze(&[&seed], &mut buf);
    let mut pos = 0usize;
    while n < 256 && pos + 2 < 1008 {
        let b2 = buf[pos + 2] as u32 - if buf[pos + 2] > 127 { 128 } else { 0 };
        let z = (b2 << 16) | ((buf[pos + 1] as u32) << 8) | (buf[pos] as u32);
        pos += 3;
        if z < Q {
            f[n] = z;
            n += 1;
        }
    }
    f
}

pub fn rej_bounded_poly(rho: &[u8], r: u16) -> [u32; 256] {
    let mut seed = [0u8; 66];
    seed[..64].copy_from_slice(rho);
    seed[64] = (r & 0xff) as u8;
    seed[65] = (r >> 8) as u8;
    let mut f = [0u32; 256];
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
                let cv = cc as u32;
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

pub fn expand_mask_poly(rho: &[u8], mu: u16) -> [u32; 256] {
    let mut seed = [0u8; 66];
    seed[..64].copy_from_slice(rho);
    seed[64] = (mu & 0xff) as u8;
    seed[65] = (mu >> 8) as u8;
    let mut bytes = [0u8; 640];
    shake::shake256_squeeze(&[&seed], &mut bytes);
    let mut y = [0u32; 256];
    for (k, oc) in y.iter_mut().enumerate() {
        let mut v = 0u32;
        for j in 0..20 {
            let idx = k * 20 + j;
            v |= (((bytes[idx / 8] >> (idx % 8)) & 1) as u32) << j;
        }
        *oc = (GAMMA1 + Q - v) % Q;
    }
    y
}

pub fn sample_in_ball(rho: &[u8], tau: usize) -> [u32; 256] {
    let mut c = [0u32; 256];
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

fn pack<const D: usize>(coeffs: &[u32], out: &mut [u8]) {
    let mut acc: u64 = 0;
    let mut nbits = 0u32;
    let mut oi = 0usize;
    for &c in coeffs {
        acc |= (c as u64) << nbits;
        nbits += D as u32;
        while nbits >= 8 {
            out[oi] = acc as u8;
            oi += 1;
            acc >>= 8;
            nbits -= 8;
        }
    }
    if nbits > 0 {
        out[oi] = acc as u8;
    }
}

fn unpack<const D: usize>(bytes: &[u8], out: &mut [u32]) {
    let mut bitpos = 0usize;
    for o in out.iter_mut() {
        let byte = bitpos / 8;
        let sh = bitpos % 8;
        let mut v: u32 = (bytes[byte] as u32) >> sh;
        let need = (D as isize) - (8 - sh as isize);
        if need > 0 {
            v |= (bytes[byte + 1] as u32) << (8 - sh);
        }
        if need > 8 {
            v |= (bytes[byte + 2] as u32) << (16 - sh);
        }
        *o = v & ((1u32 << D) - 1);
        bitpos += D;
    }
}

fn mod_plus_minus(x: u32, m: u32) -> u32 {
    let r = x % m;
    if r > m >> 1 {
        r + Q - m
    } else {
        r
    }
}

fn power2round(x: u32) -> (u32, u32) {
    let r0 = mod_plus_minus(x, 1 << D);
    let r1 = ((x + Q - r0) % Q) >> D;
    (r1, r0)
}

fn decompose(x: u32) -> (u32, u32) {
    let r0 = mod_plus_minus(x, TWO_GAMMA2);
    let diff = (x + Q - r0) % Q;
    if diff == Q - 1 {
        (0, (r0 + Q - 1) % Q)
    } else {
        (diff / TWO_GAMMA2, r0)
    }
}

fn high_bits(x: u32) -> u32 {
    decompose(x).0
}

fn low_bits(x: u32) -> u32 {
    decompose(x).1
}

fn make_hint(z: u32, r: u32) -> bool {
    high_bits((r + z) % Q) != high_bits(r)
}

fn use_hint(h: bool, r: u32) -> u32 {
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

fn infinity_norm(p: &[u32]) -> u32 {
    p.iter()
        .map(|&x| if x > Q / 2 { Q - x } else { x })
        .max()
        .unwrap()
}

fn ntt_vec<const N: usize>(v: &[[u32; 256]; N]) -> [[u32; 256]; N] {
    let mut out = *v;
    for p in out.iter_mut() {
        ntt(p);
    }
    out
}

fn invntt_vec<const N: usize>(v: &[[u32; 256]; N]) -> [[u32; 256]; N] {
    let mut out = *v;
    for p in out.iter_mut() {
        invntt(p);
    }
    out
}

fn poly_mul_ntt(a: &[u32; 256], b: &[u32; 256]) -> [u32; 256] {
    let mut c = [0u32; 256];
    for ((oc, &ac), &bc) in c.iter_mut().zip(a.iter()).zip(b.iter()) {
        *oc = (ac as u64 * bc as u64 % Q as u64) as u32;
    }
    c
}

pub fn mat_mul_vec(a: &[[u32; 256]; K * L], v: &[[u32; 256]; L]) -> [[u32; 256]; K] {
    let mut out = [[0u32; 256]; K];
    for (i, row) in a.as_chunks::<L>().0.iter().enumerate() {
        for k in 0..256 {
            let acc = row.iter().zip(v.iter()).fold(0u64, |acc, (ar, vr)| {
                (acc + ar[k] as u64 * vr[k] as u64) % Q as u64
            }) as u32;
            out[i][k] = acc;
        }
    }
    out
}

fn encode_s<const N: usize>(s: &[[u32; 256]; N], out: &mut [u8]) {
    let mut flat = [0u32; 1536];
    let mut fi = 0;
    for p in s {
        for &c in p.iter() {
            flat[fi] = (ETA + Q - c) % Q;
            fi += 1;
        }
    }
    pack::<4>(&flat[..N * 256], out);
}

fn decode_s<const N: usize>(bytes: &[u8]) -> [[u32; 256]; N] {
    let mut flat = [0u32; 1536];
    unpack::<4>(bytes, &mut flat[..N * 256]);
    let mut out = [[0u32; 256]; N];
    for (op, fp) in out.iter_mut().zip(flat.as_chunks::<256>().0.iter()) {
        for (oc, &fc) in op.iter_mut().zip(fp.iter()) {
            *oc = (ETA + Q - fc) % Q;
        }
    }
    out
}

fn encode_t0<const N: usize>(t0: &[[u32; 256]; N], out: &mut [u8]) {
    let mut flat = [0u32; 1536];
    let mut fi = 0;
    for p in t0 {
        for &c in p.iter() {
            flat[fi] = ((1 << (D - 1)) + Q - c) % Q;
            fi += 1;
        }
    }
    pack::<D>(&flat[..N * 256], out);
}

fn decode_t0<const N: usize>(bytes: &[u8]) -> [[u32; 256]; N] {
    let mut flat = [0u32; 1536];
    unpack::<D>(bytes, &mut flat[..N * 256]);
    let mut out = [[0u32; 256]; N];
    for (op, fp) in out.iter_mut().zip(flat.as_chunks::<256>().0.iter()) {
        for (oc, &fc) in op.iter_mut().zip(fp.iter()) {
            *oc = ((1 << (D - 1)) + Q - fc) % Q;
        }
    }
    out
}

fn encode_t1<const N: usize>(t1: &[[u32; 256]; N], out: &mut [u8]) {
    let mut flat = [0u32; 1536];
    let mut fi = 0;
    for p in t1 {
        for &c in p.iter() {
            flat[fi] = c;
            fi += 1;
        }
    }
    pack::<10>(&flat[..N * 256], out);
}

fn decode_t1<const N: usize>(bytes: &[u8]) -> [[u32; 256]; N] {
    let mut flat = [0u32; 1536];
    unpack::<10>(bytes, &mut flat[..N * 256]);
    let mut out = [[0u32; 256]; N];
    for (op, fp) in out.iter_mut().zip(flat.as_chunks::<256>().0.iter()) {
        for (oc, &fc) in op.iter_mut().zip(fp.iter()) {
            *oc = fc;
        }
    }
    out
}

fn encode_w1<const N: usize>(w1: &[[u32; 256]; N], out: &mut [u8]) {
    let mut flat = [0u32; 1536];
    let mut fi = 0;
    for p in w1 {
        for &c in p.iter() {
            flat[fi] = c;
            fi += 1;
        }
    }
    pack::<4>(&flat[..N * 256], out);
}

fn decode_z<const N: usize>(bytes: &[u8]) -> [[u32; 256]; N] {
    let mut flat = [0u32; 1536];
    unpack::<20>(bytes, &mut flat[..N * 256]);
    let mut out = [[0u32; 256]; N];
    for (op, fp) in out.iter_mut().zip(flat.as_chunks::<256>().0.iter()) {
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

fn encode_z<const N: usize>(z: &[[u32; 256]; N], out: &mut [u8]) {
    let mut flat = [0u32; 1536];
    let mut fi = 0;
    for p in z {
        for &c in p.iter() {
            flat[fi] = (GAMMA1 + Q - c) % Q;
            fi += 1;
        }
    }
    pack::<20>(&flat[..N * 256], out);
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

    let mut a_hat = [[0u32; 256]; K * L];
    for (i, row) in a_hat.as_chunks_mut::<L>().0.iter_mut().enumerate() {
        for (j, cell) in row.iter_mut().enumerate() {
            *cell = rej_ntt_poly(&rho, i as u8, j as u8);
        }
    }

    let mut s1 = [[0u32; 256]; L];
    let mut s2 = [[0u32; 256]; K];
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

    let mut t1 = [[0u32; 256]; K];
    let mut t0 = [[0u32; 256]; K];
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

    let mut a_hat = [[0u32; 256]; K * L];
    for (i, row) in a_hat.as_chunks_mut::<L>().0.iter_mut().enumerate() {
        for (j, cell) in row.iter_mut().enumerate() {
            *cell = rej_ntt_poly(rho, i as u8, j as u8);
        }
    }

    let mut rhopp = [0u8; 64];
    shake::shake256_squeeze(&[kk, rnd, mu_b], &mut rhopp);

    let mut kappa = 0u16;
    let (c_tilde, z, h);
    loop {
        let mut y = [[0u32; 256]; L];
        for (i, p) in y.iter_mut().enumerate() {
            *p = expand_mask_poly(&rhopp, kappa + i as u16);
        }
        let y_hat = ntt_vec(&y);
        let w = mat_mul_vec(&a_hat, &y_hat);
        let w = invntt_vec(&w);

        let mut w1 = [[0u32; 256]; K];
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
        let mut c_hat = [0u32; 256];
        c_hat.copy_from_slice(&c);
        ntt(&mut c_hat);

        let mut cs1 = [[0u32; 256]; L];
        let mut cs2 = [[0u32; 256]; K];
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
        let mut w_minus_cs2 = [[0u32; 256]; K];
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
        let mut r0 = [[0u32; 256]; K];
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

        let mut ct0 = [[0u32; 256]; K];
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

pub struct VerifyPrecomp {
    pub a_hat_packed: [u8; K * L * 256 * 3],
    pub t1_2d_hat_packed: [u8; K * 256 * 3],
    pub tr_b: [u8; 64],
    pub vk_hash: [u8; 32],
}

impl Default for VerifyPrecomp {
    fn default() -> Self {
        VerifyPrecomp {
            a_hat_packed: [0u8; K * L * 256 * 3],
            t1_2d_hat_packed: [0u8; K * 256 * 3],
            tr_b: [0u8; 64],
            vk_hash: [0u8; 32],
        }
    }
}

#[inline(always)]
fn pack3(p: &mut [u8], idx: usize, v: u32) {
    p[idx] = v as u8;
    p[idx + 1] = (v >> 8) as u8;
    p[idx + 2] = (v >> 16) as u8;
}

#[inline(always)]
fn unpack3(p: &[u8], idx: usize) -> u32 {
    p[idx] as u32 | ((p[idx + 1] as u32) << 8) | ((p[idx + 2] as u32) << 16)
}

pub const SPC_LEN: usize = K * L * 256 * 3 + L * 256 * 3 + K * 256 * 3 + K * 256 * 3;

const A_HAT_LEN: usize = K * L * 256 * 3;
const S1_HAT_OFF: usize = A_HAT_LEN;
const S2_HAT_OFF: usize = S1_HAT_OFF + L * 256 * 3;
const T0_HAT_OFF: usize = S2_HAT_OFF + K * 256 * 3;

#[repr(transparent)]
pub struct SignPrecomp([u8; SPC_LEN]);

impl SignPrecomp {
    pub fn from_bytes(raw: &[u8; SPC_LEN]) -> &Self {
        // SAFETY: repr(transparent) over the same array type guarantees the
        // layout is identical, so the pointer cast is valid.
        unsafe { &*(raw as *const [u8; SPC_LEN] as *const SignPrecomp) }
    }

    pub fn as_bytes(&self) -> &[u8; SPC_LEN] {
        &self.0
    }

    fn a_hat(&self) -> &[u8] {
        &self.0[..A_HAT_LEN]
    }

    fn a_hat_mut(&mut self) -> &mut [u8] {
        &mut self.0[..A_HAT_LEN]
    }

    fn s1_hat(&self) -> &[u8] {
        &self.0[S1_HAT_OFF..S2_HAT_OFF]
    }

    fn s1_hat_mut(&mut self) -> &mut [u8] {
        &mut self.0[S1_HAT_OFF..S2_HAT_OFF]
    }

    fn s2_hat(&self) -> &[u8] {
        &self.0[S2_HAT_OFF..T0_HAT_OFF]
    }

    fn s2_hat_mut(&mut self) -> &mut [u8] {
        &mut self.0[S2_HAT_OFF..T0_HAT_OFF]
    }

    fn t0_hat(&self) -> &[u8] {
        &self.0[T0_HAT_OFF..]
    }

    fn t0_hat_mut(&mut self) -> &mut [u8] {
        &mut self.0[T0_HAT_OFF..]
    }
}

impl Default for SignPrecomp {
    fn default() -> Self {
        SignPrecomp([0u8; SPC_LEN])
    }
}

pub fn sign_precomp_new_into(pc: &mut SignPrecomp, sk: &[u8; SK_LEN]) {
    let rho = &sk[..32];
    let s1 = decode_s::<L>(&sk[128..128 + L * 128]);
    let s2 = decode_s::<K>(&sk[128 + L * 128..128 + L * 128 + K * 128]);
    let t0 = decode_t0::<K>(&sk[128 + L * 128 + K * 128..]);

    for i in 0..K {
        for j in 0..L {
            let p = rej_ntt_poly(rho, i as u8, j as u8);
            for (k, &v) in p.iter().enumerate() {
                pack3(pc.a_hat_mut(), ((i * L + j) * 256 + k) * 3, v);
            }
        }
    }
    for (i, s) in ntt_vec(&s1).iter().enumerate() {
        for (k, &v) in s.iter().enumerate() {
            pack3(pc.s1_hat_mut(), (i * 256 + k) * 3, v);
        }
    }
    for (i, s) in ntt_vec(&s2).iter().enumerate() {
        for (k, &v) in s.iter().enumerate() {
            pack3(pc.s2_hat_mut(), (i * 256 + k) * 3, v);
        }
    }
    for (i, s) in ntt_vec(&t0).iter().enumerate() {
        for (k, &v) in s.iter().enumerate() {
            pack3(pc.t0_hat_mut(), (i * 256 + k) * 3, v);
        }
    }
}

pub fn sign_precomp_into(
    pc: &SignPrecomp,
    sk: &[u8; SK_LEN],
    mu_b: &[u8; 64],
    rnd: &[u8; 32],
) -> [u8; SIG_LEN] {
    let mut kk = [0u8; 32];
    kk.copy_from_slice(&sk[32..64]);
    sign_precomp_kk_into(pc, &kk, mu_b, rnd)
}

pub fn sign_precomp_kk_into(
    pc: &SignPrecomp,
    kk: &[u8; 32],
    mu_b: &[u8; 64],
    rnd: &[u8; 32],
) -> [u8; SIG_LEN] {
    let mut rhopp = [0u8; 64];
    shake::shake256_squeeze(&[kk, rnd, mu_b], &mut rhopp);

    let mut kappa = 0u16;
    let (c_tilde, z, h);
    loop {
        let mut y = [[0u32; 256]; L];
        for (i, p) in y.iter_mut().enumerate() {
            *p = expand_mask_poly(&rhopp, kappa + i as u16);
        }
        let mut y_hat_packed = [0u8; L * 256 * 3];
        for (i, yp) in y.iter().enumerate() {
            let mut tmp = *yp;
            ntt(&mut tmp);
            for (k, &v) in tmp.iter().enumerate() {
                pack3(&mut y_hat_packed, (i * 256 + k) * 3, v);
            }
        }

        let mut w = [[0u32; 256]; K];
        for (i, wi) in w.iter_mut().enumerate() {
            for (k, wc) in wi.iter_mut().enumerate() {
                let mut acc = 0u64;
                for j in 0..L {
                    let ar = unpack3(pc.a_hat(), ((i * L + j) * 256 + k) * 3);
                    let yr = unpack3(y_hat_packed.as_slice(), (j * 256 + k) * 3);
                    acc += ar as u64 * yr as u64;
                }
                *wc = (acc % Q as u64) as u32;
            }
        }
        for wp in w.iter_mut() {
            invntt(wp);
        }

        let mut w1_tilde = [0u8; K * 128];
        for (wp, out) in w.iter().zip(w1_tilde.as_chunks_mut::<128>().0.iter_mut()) {
            let mut hi = [0u32; 256];
            for (hc, &wv) in hi.iter_mut().zip(wp.iter()) {
                *hc = high_bits(wv);
            }
            pack::<4>(&hi, out);
        }

        let mut ctil = [0u8; LAMBDA];
        shake::shake256_squeeze(&[mu_b, w1_tilde.as_slice()], &mut ctil);

        let c = sample_in_ball(&ctil, TAU);
        let mut c_hat = [0u32; 256];
        c_hat.copy_from_slice(&c);
        ntt(&mut c_hat);

        let mut ok = true;
        let mut cp = [0u32; 256];
        for (i, yi) in y.iter_mut().enumerate() {
            for k in 0..256 {
                let cr = c_hat[k] as u64;
                let sr = unpack3(pc.s1_hat(), (i * 256 + k) * 3) as u64;
                cp[k] = ((cr * sr) % Q as u64) as u32;
            }
            invntt(&mut cp);
            for (yc, &cc) in yi.iter_mut().zip(cp.iter()) {
                *yc = (*yc + cc) % Q;
            }
            if infinity_norm(yi) >= GAMMA1_MINUS_BETA {
                ok = false;
            }
        }
        if !ok {
            kappa = kappa.wrapping_add(L as u16);
            continue;
        }

        for (i, wi) in w.iter_mut().enumerate() {
            for k in 0..256 {
                let cr = c_hat[k] as u64;
                let sr = unpack3(pc.s2_hat(), (i * 256 + k) * 3) as u64;
                cp[k] = ((cr * sr) % Q as u64) as u32;
            }
            invntt(&mut cp);
            for (wc, &cc) in wi.iter_mut().zip(cp.iter()) {
                *wc = (*wc + Q - cc) % Q;
            }
            let mut rmax = 0u32;
            for &wm in wi.iter() {
                let r0 = low_bits(wm);
                let mag = if r0 > Q / 2 { Q - r0 } else { r0 };
                if mag > rmax {
                    rmax = mag;
                }
            }
            if rmax >= GAMMA2_MINUS_BETA {
                ok = false;
            }
        }
        let mut hh = [[false; 256]; K];
        let mut wgt = 0usize;
        for i in 0..K {
            for k in 0..256 {
                let cr = c_hat[k] as u64;
                let tr = unpack3(pc.t0_hat(), (i * 256 + k) * 3) as u64;
                cp[k] = ((cr * tr) % Q as u64) as u32;
            }
            invntt(&mut cp);
            if infinity_norm(&cp) >= GAMMA2 {
                ok = false;
            }
            for (k, (hc, &cv)) in hh[i].iter_mut().zip(cp.iter()).enumerate() {
                let nct0 = (Q - cv) % Q;
                let wcc = (w[i][k] + cv) % Q;
                *hc = make_hint(nct0, wcc);
                if *hc {
                    wgt += 1;
                }
            }
        }
        if !ok || wgt > OMEGA {
            kappa = kappa.wrapping_add(L as u16);
            continue;
        }

        c_tilde = ctil;
        z = y;
        h = hh;
        break;
    }

    let mut sig = [0u8; SIG_LEN];
    sig[..LAMBDA].copy_from_slice(&c_tilde);
    encode_z(&z, &mut sig[LAMBDA..LAMBDA + L * 640]);
    sig[LAMBDA + L * 640..].copy_from_slice(&pack_h(&h));
    sig
}

pub fn verify_precomp_new_into(pc: &mut VerifyPrecomp, vk: &[u8; VK_LEN]) {
    let rho = &vk[..32];
    let t1 = decode_t1::<K>(&vk[32..]);

    for i in 0..K {
        for j in 0..L {
            let a = rej_ntt_poly(rho, i as u8, j as u8);
            let base = (i * L + j) * 256 * 3;
            for (k, &v) in a.iter().enumerate() {
                pack3(&mut pc.a_hat_packed, base + k * 3, v);
            }
        }
    }
    for (i, ip) in t1.iter().enumerate() {
        let mut tp = [0u32; 256];
        for (oc, &ic) in tp.iter_mut().zip(ip.iter()) {
            *oc = (ic as u64 * (1u32 << D) as u64 % Q as u64) as u32;
        }
        ntt(&mut tp);
        let base = i * 256 * 3;
        for (k, &v) in tp.iter().enumerate() {
            pack3(&mut pc.t1_2d_hat_packed, base + k * 3, v);
        }
    }

    let mut tr_b = [0u8; 64];
    shake::shake256_squeeze(&[vk], &mut tr_b);
    let vk_hash = crate::shake::sha3_256(vk);

    pc.tr_b = tr_b;
    pc.vk_hash = vk_hash;
}

pub fn verify_precomp_new(vk: &[u8; VK_LEN]) -> VerifyPrecomp {
    let mut pc = VerifyPrecomp {
        a_hat_packed: [0u8; K * L * 256 * 3],
        t1_2d_hat_packed: [0u8; K * 256 * 3],
        tr_b: [0u8; 64],
        vk_hash: [0u8; 32],
    };
    verify_precomp_new_into(&mut pc, vk);
    pc
}

fn verify_core_precomp(pc: &VerifyPrecomp, mu_b: &[u8; 64], sig: &[u8; SIG_LEN]) -> bool {
    let a_hat_packed = &pc.a_hat_packed;
    let t1_2d_hat_packed = &pc.t1_2d_hat_packed;

    let c_tilde = &sig[..LAMBDA];
    let mut z = decode_z::<L>(&sig[LAMBDA..LAMBDA + L * 640]);
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
    let mut c_hat = [0u32; 256];
    c_hat.copy_from_slice(&c);
    ntt(&mut c_hat);
    for zp in z.iter_mut() {
        ntt(zp);
    }

    let mut buf = [[0u32; 256]; K];
    for (i, bp) in buf.iter_mut().enumerate() {
        for (k, bc) in bp.iter_mut().enumerate() {
            // 30 terms < 2^63
            let mut acc = 0u64;
            for (j, zj) in z.iter().enumerate() {
                const ABASE: usize = 256 * 3;
                let off = (i * L + j) * ABASE + k * 3;
                let ar = unpack3(a_hat_packed.as_slice(), off);
                let zr = zj[k];
                acc += ar as u64 * zr as u64;
            }
            *bc = (acc % Q as u64) as u32;
        }
    }
    for (i, op) in buf.iter_mut().enumerate() {
        for k in 0..256 {
            const TBASE: usize = 256 * 3;
            let tv = unpack3(t1_2d_hat_packed.as_slice(), i * TBASE + k * 3);
            let av = op[k];
            let ct1 = (c_hat[k] as u64 * tv as u64 % Q as u64) as u32;
            let d = av + Q - ct1;
            op[k] = if d >= Q { d - Q } else { d };
        }
    }
    for wp in buf.iter_mut() {
        invntt(wp);
    }

    for (op, hp) in buf.iter_mut().zip(h.iter()) {
        for (oc, &hv) in op.iter_mut().zip(hp.iter()) {
            *oc = use_hint(hv, *oc);
        }
    }
    let mut w1_tilde = [0u8; K * 128];
    encode_w1(&buf, &mut w1_tilde);

    let mut ctil = [0u8; LAMBDA];
    shake::shake256_squeeze(&[mu_b, &w1_tilde], &mut ctil);
    ctil == *c_tilde
}

pub fn verify_precomp(pc: &VerifyPrecomp, msg: &[u8], ctx: &[u8], sig: &[u8; SIG_LEN]) -> bool {
    if ctx.len() > 255 {
        return false;
    }
    let mut mu_b = [0u8; 64];
    shake::shake256_squeeze(
        &[&pc.tr_b, &[0x00], &[ctx.len() as u8], ctx, msg],
        &mut mu_b,
    );
    verify_core_precomp(pc, &mu_b, sig)
}

fn verify_core(vk: &[u8; VK_LEN], mu_b: &[u8; 64], sig: &[u8; SIG_LEN]) -> bool {
    let rho = &vk[..32];
    let t1 = decode_t1::<K>(&vk[32..]);

    let mut a_hat = [[0u32; 256]; K * L];
    for i in 0..K {
        for j in 0..L {
            a_hat[i * L + j] = rej_ntt_poly(rho, i as u8, j as u8);
        }
    }

    let mut t1_2d = [[0u32; 256]; K];
    for (op, ip) in t1_2d.iter_mut().zip(t1.iter()) {
        for (oc, &ic) in op.iter_mut().zip(ip.iter()) {
            *oc = (ic as u64 * (1u32 << D) as u64 % Q as u64) as u32;
        }
    }
    let t1_2d_hat = ntt_vec(&t1_2d);

    let c_tilde = &sig[..LAMBDA];
    let mut z = decode_z::<L>(&sig[LAMBDA..LAMBDA + L * 640]);
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
    let mut c_hat = [0u32; 256];
    c_hat.copy_from_slice(&c);
    ntt(&mut c_hat);
    for zp in z.iter_mut() {
        ntt(zp);
    }

    let mut buf = [[0u32; 256]; K];
    for (i, row) in a_hat.as_chunks::<L>().0.iter().enumerate() {
        for k in 0..256 {
            // 30 terms < 2^63
            let acc = row
                .iter()
                .zip(z.iter())
                .fold(0u64, |acc, (ar, zr)| acc + ar[k] as u64 * zr[k] as u64);
            buf[i][k] = (acc % Q as u64) as u32;
        }
    }
    for (i, op) in buf.iter_mut().enumerate() {
        for k in 0..256 {
            let tv = t1_2d_hat[i][k];
            let av = op[k];
            let ct1 = (c_hat[k] as u64 * tv as u64 % Q as u64) as u32;
            let d = av + Q - ct1;
            op[k] = if d >= Q { d - Q } else { d };
        }
    }
    for wp in buf.iter_mut() {
        invntt(wp);
    }

    for (op, hp) in buf.iter_mut().zip(h.iter()) {
        for (oc, &hv) in op.iter_mut().zip(hp.iter()) {
            *oc = use_hint(hv, *oc);
        }
    }
    let mut w1_tilde = [0u8; K * 128];
    encode_w1(&buf, &mut w1_tilde);

    let mut ctil = [0u8; LAMBDA];
    shake::shake256_squeeze(&[mu_b, &w1_tilde], &mut ctil);
    ctil == *c_tilde
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sign_precomp_stages_match_reference() {
        use crate::shake;
        let seed = [9u8; 32];
        let (_vk, sk) = keygen_internal(&seed);
        let mut pc = SignPrecomp::default();
        sign_precomp_new_into(&mut pc, &sk);

        let msg = b"hello";
        let tr = &sk[64..128];
        let len_b = [msg.len() as u8];
        let mut mu_b = [0u8; 64];
        shake::shake256_squeeze(&[tr, &[0x00], &len_b, msg], &mut mu_b);

        let rho = &sk[..32];
        let kk = &sk[32..64];
        let mut rhopp_a = [0u8; 64];
        shake::shake256_squeeze(&[kk, &[0u8; 32], &mu_b], &mut rhopp_a);

        let mut y = [[0u32; 256]; L];
        for (i, p) in y.iter_mut().enumerate() {
            *p = expand_mask_poly(&rhopp_a, 5 + i as u16);
        }
        let mut y_hat_packed = [0u8; L * 256 * 3];
        for (i, yp) in y.iter().enumerate() {
            let mut tmp = *yp;
            ntt(&mut tmp);
            for (k, &v) in tmp.iter().enumerate() {
                pack3(&mut y_hat_packed, (i * 256 + k) * 3, v);
            }
        }
        let mut a_hat = [[0u32; 256]; K * L];
        for (i, row) in a_hat.as_chunks_mut::<L>().0.iter_mut().enumerate() {
            for (j, cell) in row.iter_mut().enumerate() {
                *cell = rej_ntt_poly(rho, i as u8, j as u8);
            }
        }
        let y_hat = ntt_vec(&y);
        let w_ref = mat_mul_vec(&a_hat, &y_hat);

        let mut w = [[0u32; 256]; K];
        for (i, wi) in w.iter_mut().enumerate() {
            for (k, wc) in wi.iter_mut().enumerate() {
                let mut acc = 0u64;
                for j in 0..L {
                    let ar = unpack3(pc.a_hat(), ((i * L + j) * 256 + k) * 3);
                    let yr = unpack3(y_hat_packed.as_slice(), (j * 256 + k) * 3);
                    acc += ar as u64 * yr as u64;
                }
                *wc = (acc % Q as u64) as u32;
            }
        }
        assert_eq!(w, w_ref, "matmul mismatch");

        for wp in w.iter_mut() {
            invntt(wp);
        }
        let w_ref2 = invntt_vec(&w_ref);
        assert_eq!(w, w_ref2, "invntt mismatch");

        let mut w1_tilde = [0u8; K * 128];
        for (wp, out) in w.iter().zip(w1_tilde.as_chunks_mut::<128>().0.iter_mut()) {
            let mut hi = [0u32; 256];
            for (hc, &wv) in hi.iter_mut().zip(wp.iter()) {
                *hc = high_bits(wv);
            }
            pack::<4>(&hi, out);
        }
        let mut w1 = [[0u32; 256]; K];
        for (w1p, wp) in w1.iter_mut().zip(w_ref2.iter()) {
            for (wc, &wv) in w1p.iter_mut().zip(wp.iter()) {
                *wc = high_bits(wv);
            }
        }
        let mut w1_tilde_ref = [0u8; K * 128];
        encode_w1(&w1, &mut w1_tilde_ref);
        assert_eq!(w1_tilde, w1_tilde_ref, "w1 encode mismatch");

        let mut ctil = [0u8; LAMBDA];
        shake::shake256_squeeze(&[&mu_b, &w1_tilde], &mut ctil);
        let mut ctil_ref = [0u8; LAMBDA];
        shake::shake256_squeeze(&[&mu_b, &w1_tilde_ref], &mut ctil_ref);
        assert_eq!(ctil, ctil_ref, "ctil mismatch");

        let c = sample_in_ball(&ctil, TAU);
        let mut c_hat = [0u32; 256];
        c_hat.copy_from_slice(&c);
        ntt(&mut c_hat);

        let s1 = decode_s::<L>(&sk[128..128 + L * 128]);
        let s2 = decode_s::<K>(&sk[128 + L * 128..128 + L * 128 + K * 128]);
        let s1_hat = ntt_vec(&s1);
        let s2_hat = ntt_vec(&s2);

        let mut cs1_hat = [[0u32; 256]; L];
        for (o, &s) in cs1_hat.iter_mut().zip(s1_hat.iter()) {
            *o = poly_mul_ntt(&c_hat, &s);
        }
        let cs1_ref = invntt_vec(&cs1_hat);
        let mut z_ref = y;
        for (zp, c1p) in z_ref.iter_mut().zip(cs1_ref.iter()) {
            for (zc, &c1c) in zp.iter_mut().zip(c1p.iter()) {
                *zc = (*zc + c1c) % Q;
            }
        }

        let mut cp = [0u32; 256];
        for (i, yi) in y.iter_mut().enumerate() {
            for k in 0..256 {
                let cr = c_hat[k] as u64;
                let sr = unpack3(pc.s1_hat(), (i * 256 + k) * 3) as u64;
                cp[k] = ((cr * sr) % Q as u64) as u32;
            }
            invntt(&mut cp);
            for (yc, &cc) in yi.iter_mut().zip(cp.iter()) {
                *yc = (*yc + cc) % Q;
            }
        }
        assert_eq!(y, z_ref, "cs1/z mismatch");

        let mut cs2_hat = [[0u32; 256]; K];
        for (o, &s) in cs2_hat.iter_mut().zip(s2_hat.iter()) {
            *o = poly_mul_ntt(&c_hat, &s);
        }
        let cs2_ref = invntt_vec(&cs2_hat);
        let mut w0_ref = w_ref2;
        for ((op, wp), c2p) in w0_ref.iter_mut().zip(w_ref2.iter()).zip(cs2_ref.iter()) {
            for ((oc, &wv), &c2c) in op.iter_mut().zip(wp.iter()).zip(c2p.iter()) {
                *oc = (wv + Q - c2c) % Q;
            }
        }
        for (i, wi) in w.iter_mut().enumerate() {
            for k in 0..256 {
                let cr = c_hat[k] as u64;
                let sr = unpack3(pc.s2_hat(), (i * 256 + k) * 3) as u64;
                cp[k] = ((cr * sr) % Q as u64) as u32;
            }
            invntt(&mut cp);
            for (wc, &cc) in wi.iter_mut().zip(cp.iter()) {
                *wc = (*wc + Q - cc) % Q;
            }
        }
        assert_eq!(w, w0_ref, "cs2/w0 mismatch");

        let t0 = decode_t0::<K>(&sk[128 + L * 128 + K * 128..]);
        let t0_hat = ntt_vec(&t0);
        let mut ct0_hat = [[0u32; 256]; K];
        for (o, &t) in ct0_hat.iter_mut().zip(t0_hat.iter()) {
            *o = poly_mul_ntt(&c_hat, &t);
        }
        let ct0_ref = invntt_vec(&ct0_hat);
        let mut hh_ref = [[false; 256]; K];
        let mut wgt_ref = 0usize;
        for ((hp, cp), wmp) in hh_ref.iter_mut().zip(ct0_ref.iter()).zip(w0_ref.iter()) {
            for ((hc, &cv), &wm) in hp.iter_mut().zip(cp.iter()).zip(wmp.iter()) {
                let nct0 = (Q - cv) % Q;
                let wcc = (wm + cv) % Q;
                *hc = make_hint(nct0, wcc);
                if *hc {
                    wgt_ref += 1;
                }
            }
        }

        let mut hh = [[false; 256]; K];
        let mut wgt = 0usize;
        for i in 0..K {
            for k in 0..256 {
                let cr = c_hat[k] as u64;
                let tr = unpack3(pc.t0_hat(), (i * 256 + k) * 3) as u64;
                cp[k] = ((cr * tr) % Q as u64) as u32;
            }
            invntt(&mut cp);
            for (k, (hc, &cv)) in hh[i].iter_mut().zip(cp.iter()).enumerate() {
                let nct0 = (Q - cv) % Q;
                let wcc = (w[i][k] + cv) % Q;
                *hc = make_hint(nct0, wcc);
                if *hc {
                    wgt += 1;
                }
            }
        }
        assert_eq!(hh, hh_ref, "hint mismatch");
        assert_eq!(wgt, wgt_ref, "hint weight mismatch");

        let mut rmax_ref = 0u32;
        for (wp, wmp) in w_ref2.iter().zip(w0_ref.iter()) {
            let _ = wp;
            for &wm in wmp.iter() {
                let r0 = low_bits(wm);
                let mag = if r0 > Q / 2 { Q - r0 } else { r0 };
                if mag > rmax_ref {
                    rmax_ref = mag;
                }
            }
        }
        let mut rmax = 0u32;
        for wp in w.iter() {
            for &wm in wp.iter() {
                let r0 = low_bits(wm);
                let mag = if r0 > Q / 2 { Q - r0 } else { r0 };
                if mag > rmax {
                    rmax = mag;
                }
            }
        }
        assert_eq!(rmax, rmax_ref, "r0 norm mismatch");
        assert_eq!(
            rmax >= GAMMA2_MINUS_BETA,
            rmax_ref >= GAMMA2_MINUS_BETA,
            "r0 verdict mismatch"
        );

        let mut ct0n_ref = 0u32;
        for cp in ct0_ref.iter() {
            let m = infinity_norm(cp);
            if m > ct0n_ref {
                ct0n_ref = m;
            }
        }
        let mut ct0n = 0u32;
        for i in 0..K {
            for k in 0..256 {
                let cr = c_hat[k] as u64;
                let tr = unpack3(pc.t0_hat(), (i * 256 + k) * 3) as u64;
                cp[k] = ((cr * tr) % Q as u64) as u32;
            }
            invntt(&mut cp);
            let m = infinity_norm(&cp);
            if m > ct0n {
                ct0n = m;
            }
        }
        assert_eq!(ct0n, ct0n_ref, "ct0 norm mismatch");
        let _ = y_hat_packed;
    }

    #[test]
    fn sign_precomp_matches() {
        let seed = [9u8; 32];
        let (vk, sk) = keygen_internal(&seed);
        let mut pc = SignPrecomp::default();
        sign_precomp_new_into(&mut pc, &sk);

        for msg in [b"hello".as_slice(), b"", &[42u8; 1000][..]] {
            let a = sign_internal(&sk, msg, b"");
            let mut mu_b = [0u8; 64];
            let tr = &sk[64..128];
            shake::shake256_squeeze(&[tr, &[0x00], &[0u8], msg], &mut mu_b);
            let b = sign_precomp_into(&pc, &sk, &mu_b, &[0u8; 32]);
            assert_eq!(a, b, "msg len {}", msg.len());
        }

        let mut mu_b = [0u8; 64];
        let tr = &sk[64..128];
        shake::shake256_squeeze(&[tr, &[0x00], &[0u8], b"hello".as_slice()], &mut mu_b);
        let sig = sign_precomp_into(&pc, &sk, &mu_b, &[0u8; 32]);
        assert!(verify_internal(&vk, b"hello", b"", &sig));
        assert!(!verify_internal(&vk, b"hellp", b"", &sig));
    }

    #[test]
    fn roundtrip() {
        let (vk, sk) = keygen_internal(&[1u8; 32]);
        let sig = sign_internal(&sk, b"message", &[]);
        assert!(verify_internal(&vk, b"message", &[], &sig));
        assert!(!verify_internal(&vk, b"message2", &[], &sig));
    }
}
