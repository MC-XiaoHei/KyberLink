use sha3::digest::{ExtendableOutput, Update, XofReader};
use sha3::{Shake128, Shake256};

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
const INVERSE_256: u64 = 8347681;

pub const VK_LEN: usize = 1952;
pub const SK_LEN: usize = 4032;
pub const SIG_LEN: usize = 3309;

fn h(x: &[u8]) -> Vec<u8> {
    let mut out = vec![0u8; 64];
    let mut s = Shake256::default();
    s.update(x);
    s.finalize_xof().read(&mut out);
    out
}

fn bitrev8(x: u64) -> u64 {
    x.reverse_bits() >> 56
}

fn pow_mod(mut b: u64, mut e: u64) -> u64 {
    let mut r = 1u64;
    while e > 0 {
        if e & 1 == 1 {
            r = r * b % Q;
        }
        b = b * b % Q;
        e >>= 1;
    }
    r
}

fn zetas() -> Vec<u64> {
    (0..256u64).map(|i| pow_mod(1753, bitrev8(i))).collect()
}

pub fn ntt(a: &mut [u64; 256]) {
    let z = zetas();
    let mut m = 0usize;
    let mut len = 128usize;
    while len >= 1 {
        let mut start = 0usize;
        while start < 256 {
            m += 1;
            let zi = z[m];
            for j in start..start + len {
                let t = zi * a[j + len] % Q;
                a[j + len] = (a[j] + Q - t) % Q;
                a[j] = (a[j] + t) % Q;
            }
            start += 2 * len;
        }
        len >>= 1;
    }
}

pub fn invntt(a: &mut [u64; 256]) {
    let z = zetas();
    let mut m = 256usize;
    let mut len = 1usize;
    while len <= 128 {
        let mut start = 0usize;
        while start < 256 {
            m -= 1;
            let zi = (Q - z[m]) % Q;
            for j in start..start + len {
                let t = a[j];
                a[j] = (t + a[j + len]) % Q;
                a[j + len] = zi * ((t + Q - a[j + len]) % Q) % Q;
            }
            start += 2 * len;
        }
        len <<= 1;
    }
    for v in a.iter_mut() {
        *v = *v * INVERSE_256 % Q;
    }
}

pub fn rej_ntt_poly(rho: &[u8], r: u8, s: u8) -> [u64; 256] {
    let mut seed = [0u8; 34];
    seed[..32].copy_from_slice(rho);
    seed[32] = s;
    seed[33] = r;
    let mut f = [0u64; 256];
    let mut n = 0usize;
    let mut ctx = Shake128::default();
    ctx.update(&seed);
    let mut xof = ctx.finalize_xof();
    let mut buf = [0u8; 3];
    while n < 256 {
        xof.read(&mut buf);
        let b2 = buf[2] as u32 - if buf[2] > 127 { 128 } else { 0 };
        let z = ((b2 as u64) << 16) | ((buf[1] as u64) << 8) | (buf[0] as u64);
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
    let mut ctx = Shake256::default();
    ctx.update(&seed);
    let mut xof = ctx.finalize_xof();
    let mut buf = [0u8; 1];
    while n < 256 {
        xof.read(&mut buf);
        let lo = buf[0] & 0x0F;
        let hi = buf[0] >> 4;
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
    let mut bytes = vec![0u8; 640];
    let mut ctx = Shake256::default();
    ctx.update(&seed);
    ctx.finalize_xof().read(&mut bytes);
    let mut y = [0u64; 256];
    for k in 0..256 {
        let mut v = 0u64;
        for j in 0..20 {
            let idx = k * 20 + j;
            v |= (((bytes[idx / 8] >> (idx % 8)) & 1) as u64) << j;
        }
        y[k] = (GAMMA1 + Q - v) % Q;
    }
    y
}

pub fn sample_in_ball(rho: &[u8], tau: usize) -> [u64; 256] {
    let mut c = [0u64; 256];
    let mut ctx = Shake256::default();
    ctx.update(rho);
    let mut xof = ctx.finalize_xof();
    let mut s = [0u8; 8];
    xof.read(&mut s);
    let mut jb = [0u8; 1];
    for i in (256 - tau)..256 {
        loop {
            xof.read(&mut jb);
            if jb[0] as usize <= i {
                break;
            }
        }
        let j = jb[0] as usize;
        c[i] = c[j];
        let bit = (s[(i + tau - 256) >> 3] >> ((i + tau - 256) & 7)) & 1;
        c[j] = if bit == 1 { Q - 1 } else { 1 };
    }
    c
}

fn pack(d: usize, coeffs: &[u64]) -> Vec<u8> {
    let mut bytes = vec![0u8; (coeffs.len() * d + 7) / 8];
    for (i, &c) in coeffs.iter().enumerate() {
        let mut a = c;
        for j in 0..d {
            let idx = i * d + j;
            bytes[idx / 8] |= ((a & 1) as u8) << (idx % 8);
            a >>= 1;
        }
    }
    bytes
}

fn unpack(d: usize, bytes: &[u8], len: usize) -> Vec<u64> {
    let mut f = vec![0u64; len];
    for i in 0..len {
        let mut v = 0u64;
        for j in 0..d {
            let idx = i * d + j;
            v |= (((bytes[idx / 8] >> (idx % 8)) & 1) as u64) << j;
        }
        f[i] = v;
    }
    f
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
    p.iter().map(|&x| if x > Q / 2 { Q - x } else { x }).max().unwrap()
}

fn ntt_vec(v: &[[u64; 256]]) -> Vec<[u64; 256]> {
    let mut out = v.to_vec();
    for p in out.iter_mut() {
        ntt(p);
    }
    out
}

fn invntt_vec(v: &[[u64; 256]]) -> Vec<[u64; 256]> {
    let mut out = v.to_vec();
    for p in out.iter_mut() {
        invntt(p);
    }
    out
}

fn poly_mul_ntt(a: &[u64; 256], b: &[u64; 256]) -> [u64; 256] {
    let mut c = [0u64; 256];
    for k in 0..256 {
        c[k] = a[k] * b[k] % Q;
    }
    c
}

fn mat_mul_vec(a: &[[u64; 256]], v: &[[u64; 256]], rows: usize, cols: usize) -> Vec<[u64; 256]> {
    let mut out = vec![[0u64; 256]; rows];
    for i in 0..rows {
        for k in 0..256 {
            let mut acc = 0u64;
            for j in 0..cols {
                acc = (acc + a[i * cols + j][k] * v[j][k]) % Q;
            }
            out[i][k] = acc;
        }
    }
    out
}

fn encode_s(s: &[[u64; 256]]) -> Vec<u8> {
    let mut flat = Vec::with_capacity(s.len() * 256);
    for p in s {
        for k in 0..256 {
            flat.push((ETA + Q - p[k]) % Q);
        }
    }
    pack(4, &flat)
}

fn decode_s(bytes: &[u8], n: usize) -> Vec<[u64; 256]> {
    let flat = unpack(4, bytes, n * 256);
    let mut out = Vec::with_capacity(n);
    for i in 0..n {
        let mut p = [0u64; 256];
        for k in 0..256 {
            p[k] = (ETA + Q - flat[i * 256 + k]) % Q;
        }
        out.push(p);
    }
    out
}

fn encode_t0(t0: &[[u64; 256]]) -> Vec<u8> {
    let mut flat = Vec::with_capacity(t0.len() * 256);
    for p in t0 {
        for k in 0..256 {
            flat.push(((1 << (D - 1)) + Q - p[k]) % Q);
        }
    }
    pack(D, &flat)
}

fn decode_t0(bytes: &[u8], n: usize) -> Vec<[u64; 256]> {
    let flat = unpack(D, bytes, n * 256);
    let mut out = Vec::with_capacity(n);
    for i in 0..n {
        let mut p = [0u64; 256];
        for k in 0..256 {
            p[k] = ((1 << (D - 1)) + Q - flat[i * 256 + k]) % Q;
        }
        out.push(p);
    }
    out
}

fn encode_t1(t1: &[[u64; 256]]) -> Vec<u8> {
    let mut flat = Vec::with_capacity(t1.len() * 256);
    for p in t1 {
        for k in 0..256 {
            flat.push(p[k]);
        }
    }
    pack(10, &flat)
}

fn decode_t1(bytes: &[u8], n: usize) -> Vec<[u64; 256]> {
    let flat = unpack(10, bytes, n * 256);
    let mut out = Vec::with_capacity(n);
    for i in 0..n {
        let mut p = [0u64; 256];
        for k in 0..256 {
            p[k] = flat[i * 256 + k];
        }
        out.push(p);
    }
    out
}

fn encode_w1(w1: &[[u64; 256]]) -> Vec<u8> {
    let mut flat = Vec::with_capacity(w1.len() * 256);
    for p in w1 {
        for k in 0..256 {
            flat.push(p[k]);
        }
    }
    pack(4, &flat)
}

fn decode_z(bytes: &[u8], n: usize) -> Vec<[u64; 256]> {
    let flat = unpack(20, bytes, n * 256);
    let mut out = Vec::with_capacity(n);
    for i in 0..n {
        let mut p = [0u64; 256];
        for k in 0..256 {
            let w = flat[i * 256 + k];
            p[k] = if w <= GAMMA1 { (GAMMA1 - w) % Q } else { Q - (w - GAMMA1) % Q };
        }
        out.push(p);
    }
    out
}

fn encode_z(z: &[[u64; 256]]) -> Vec<u8> {
    let mut flat = Vec::with_capacity(z.len() * 256);
    for p in z {
        for k in 0..256 {
            flat.push((GAMMA1 + Q - p[k]) % Q);
        }
    }
    pack(20, &flat)
}

fn pack_h(h: &[[bool; 256]]) -> Vec<u8> {
    let mut y = vec![0u8; OMEGA + K];
    let mut idx = 0usize;
    for i in 0..K {
        for j in 0..256 {
            if h[i][j] {
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
    for k in idx..OMEGA {
        if bytes[k] != 0 {
            return None;
        }
    }
    Some(h)
}

pub fn keygen_internal(seed: &[u8; 32]) -> ([u8; VK_LEN], [u8; SK_LEN]) {
    let mut gd = Vec::with_capacity(34);
    gd.extend_from_slice(seed);
    gd.push(K as u8);
    gd.push(L as u8);
    let mut gout = [0u8; 128];
    let mut s = Shake256::default();
    s.update(&gd);
    s.finalize_xof().read(&mut gout);
    let mut rho = [0u8; 32];
    let mut rho2 = [0u8; 64];
    let mut kk = [0u8; 32];
    rho.copy_from_slice(&gout[..32]);
    rho2.copy_from_slice(&gout[32..96]);
    kk.copy_from_slice(&gout[96..128]);

    let mut a_hat = vec![[0u64; 256]; K * L];
    for i in 0..K {
        for j in 0..L {
            a_hat[i * L + j] = rej_ntt_poly(&rho, i as u8, j as u8);
        }
    }

    let mut s1 = Vec::with_capacity(L);
    let mut s2 = Vec::with_capacity(K);
    for i in 0..L {
        s1.push(rej_bounded_poly(&rho2, i as u16));
    }
    for i in 0..K {
        s2.push(rej_bounded_poly(&rho2, (L + i) as u16));
    }

    let s1_hat = ntt_vec(&s1);
    let t = mat_mul_vec(&a_hat, &s1_hat, K, L);
    let t = invntt_vec(&t);
    let mut t_std = t;
    for i in 0..K {
        for k in 0..256 {
            t_std[i][k] = (t_std[i][k] + s2[i][k]) % Q;
        }
    }

    let mut t1 = Vec::with_capacity(K);
    let mut t0 = Vec::with_capacity(K);
    for i in 0..K {
        let mut p1 = [0u64; 256];
        let mut p0 = [0u64; 256];
        for k in 0..256 {
            let (r1, r0) = power2round(t_std[i][k]);
            p1[k] = r1;
            p0[k] = r0;
        }
        t1.push(p1);
        t0.push(p0);
    }

    let mut vk = Vec::with_capacity(VK_LEN);
    vk.extend_from_slice(&rho);
    vk.extend_from_slice(&encode_t1(&t1));

    let tr = h(&vk);
    let mut tr64 = [0u8; 64];
    tr64.copy_from_slice(&tr[..64]);

    let mut sk = Vec::with_capacity(SK_LEN);
    sk.extend_from_slice(&rho);
    sk.extend_from_slice(&kk);
    sk.extend_from_slice(&tr64);
    sk.extend_from_slice(&encode_s(&s1));
    sk.extend_from_slice(&encode_s(&s2));
    sk.extend_from_slice(&encode_t0(&t0));

    (vk.try_into().unwrap(), sk.try_into().unwrap())
}

pub fn sign_internal(sk: &[u8; SK_LEN], msg: &[u8], ctx: &[u8]) -> [u8; SIG_LEN] {
    let tr = &sk[64..128];
    let mut mu = Shake256::default();
    mu.update(tr);
    mu.update(&[0x00]);
    mu.update(&[ctx.len() as u8]);
    mu.update(ctx);
    mu.update(msg);
    let mut mu_b = [0u8; 64];
    let mut mx = mu.finalize_xof();
    mx.read(&mut mu_b);
    sign_core(sk, &mu_b, &[0u8; 32])
}

pub fn sign_prehash_internal(sk: &[u8; SK_LEN], m2: &[u8], rnd: &[u8; 32]) -> [u8; SIG_LEN] {
    let tr = &sk[64..128];
    let mut mu = Shake256::default();
    mu.update(tr);
    mu.update(m2);
    let mut mu_b = [0u8; 64];
    let mut mx = mu.finalize_xof();
    mx.read(&mut mu_b);
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

pub fn sign_rnd_internal(sk: &[u8; SK_LEN], msg: &[u8], ctx: &[u8], rnd: &[u8; 32]) -> [u8; SIG_LEN] {
    let tr = &sk[64..128];
    let mut mu = Shake256::default();
    mu.update(tr);
    mu.update(&[0x00]);
    mu.update(&[ctx.len() as u8]);
    mu.update(ctx);
    mu.update(msg);
    let mut mu_b = [0u8; 64];
    let mut mx = mu.finalize_xof();
    mx.read(&mut mu_b);
    sign_core(sk, &mu_b, rnd)
}

pub fn sign_prehash_rnd_internal(sk: &[u8; SK_LEN], m2: &[u8], rnd: &[u8; 32]) -> [u8; SIG_LEN] {
    let tr = &sk[64..128];
    let mut mu = Shake256::default();
    mu.update(tr);
    mu.update(m2);
    let mut mu_b = [0u8; 64];
    let mut mx = mu.finalize_xof();
    mx.read(&mut mu_b);
    sign_core(sk, &mu_b, rnd)
}

fn sign_core(sk: &[u8; SK_LEN], mu_b: &[u8; 64], rnd: &[u8; 32]) -> [u8; SIG_LEN] {
    let rho = &sk[..32];
    let kk = &sk[32..64];
    let s1 = decode_s(&sk[128..128 + L * 128], L);
    let s2 = decode_s(&sk[128 + L * 128..128 + L * 128 + K * 128], K);
    let t0 = decode_t0(&sk[128 + L * 128 + K * 128..], K);
    let s1_hat = ntt_vec(&s1);
    let s2_hat = ntt_vec(&s2);
    let t0_hat = ntt_vec(&t0);

    let mut a_hat = vec![[0u64; 256]; K * L];
    for i in 0..K {
        for j in 0..L {
            a_hat[i * L + j] = rej_ntt_poly(rho, i as u8, j as u8);
        }
    }

    let mut rhop = Shake256::default();
    rhop.update(kk);
    rhop.update(rnd);
    rhop.update(mu_b);
    let mut rhopp = [0u8; 64];
    let mut rx = rhop.finalize_xof();
    rx.read(&mut rhopp);

    let mut kappa = 0u16;
    let (c_tilde, z, h);
    loop {
        let mut y = Vec::with_capacity(L);
        for i in 0..L {
            y.push(expand_mask_poly(&rhopp, kappa + i as u16));
        }
        let y_hat = ntt_vec(&y);
        let w = mat_mul_vec(&a_hat, &y_hat, K, L);
        let w = invntt_vec(&w);

        let mut w1 = Vec::with_capacity(K);
        for i in 0..K {
            let mut p = [0u64; 256];
            for k in 0..256 {
                p[k] = high_bits(w[i][k]);
            }
            w1.push(p);
        }
        let w1_tilde = encode_w1(&w1);

        let mut mh = Shake256::default();
        mh.update(mu_b);
        mh.update(&w1_tilde);
        let mut ctil = [0u8; LAMBDA];
        let mut mxx = mh.finalize_xof();
        mxx.read(&mut ctil);

        let c = sample_in_ball(&ctil, TAU);
        let mut c_hat = [0u64; 256];
        c_hat.copy_from_slice(&c);
        ntt(&mut c_hat);

        let mut cs1 = Vec::with_capacity(L);
        let mut cs2 = Vec::with_capacity(K);
        for i in 0..L {
            cs1.push(poly_mul_ntt(&c_hat, &s1_hat[i]));
        }
        for i in 0..K {
            cs2.push(poly_mul_ntt(&c_hat, &s2_hat[i]));
        }
        let cs1 = invntt_vec(&cs1);
        let cs2 = invntt_vec(&cs2);

        let mut zz = y;
        let mut ok = true;
        let mut w_minus_cs2 = vec![[0u64; 256]; K];
        for i in 0..L {
            for k in 0..256 {
                zz[i][k] = (zz[i][k] + cs1[i][k]) % Q;
            }
            if infinity_norm(&zz[i]) >= GAMMA1_MINUS_BETA {
                ok = false;
            }
        }
        let mut r0 = vec![[0u64; 256]; K];
        for i in 0..K {
            for k in 0..256 {
                w_minus_cs2[i][k] = (w[i][k] + Q - cs2[i][k]) % Q;
                r0[i][k] = low_bits(w_minus_cs2[i][k]);
            }
            if infinity_norm(&r0[i]) >= GAMMA2_MINUS_BETA {
                ok = false;
            }
        }
        if !ok {
            kappa = kappa.wrapping_add(L as u16);
            continue;
        }

        let mut ct0 = Vec::with_capacity(K);
        for i in 0..K {
            ct0.push(poly_mul_ntt(&c_hat, &t0_hat[i]));
        }
        let ct0 = invntt_vec(&ct0);

        let mut hh = [[false; 256]; K];
        let mut wgt = 0usize;
        ok = true;
        for i in 0..K {
            for k in 0..256 {
                let nct0 = (Q - ct0[i][k]) % Q;
                let wcc = (w_minus_cs2[i][k] + ct0[i][k]) % Q;
                hh[i][k] = make_hint(nct0, wcc);
                if hh[i][k] {
                    wgt += 1;
                }
            }
            if infinity_norm(&ct0[i]) >= GAMMA2 {
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

    let mut sig = Vec::with_capacity(SIG_LEN);
    sig.extend_from_slice(&c_tilde);
    sig.extend_from_slice(&encode_z(&z));
    sig.extend_from_slice(&pack_h(&h));
    sig.try_into().unwrap()
}

pub fn verify_internal(vk: &[u8; VK_LEN], msg: &[u8], ctx: &[u8], sig: &[u8; SIG_LEN]) -> bool {
    if ctx.len() > 255 {
        return false;
    }
    let mut tr = Shake256::default();
    tr.update(vk);
    let mut tr_b = [0u8; 64];
    let mut tx = tr.finalize_xof();
    tx.read(&mut tr_b);

    let mut mu = Shake256::default();
    mu.update(&tr_b);
    mu.update(&[0x00]);
    mu.update(&[ctx.len() as u8]);
    mu.update(ctx);
    mu.update(msg);
    let mut mu_b = [0u8; 64];
    let mut mx = mu.finalize_xof();
    mx.read(&mut mu_b);
    verify_core(vk, &mu_b, sig)
}

pub fn verify_prehash_internal(vk: &[u8; VK_LEN], m2: &[u8], sig: &[u8; SIG_LEN]) -> bool {
    let mut tr = Shake256::default();
    tr.update(vk);
    let mut tr_b = [0u8; 64];
    let mut tx = tr.finalize_xof();
    tx.read(&mut tr_b);

    let mut mu = Shake256::default();
    mu.update(&tr_b);
    mu.update(m2);
    let mut mu_b = [0u8; 64];
    let mut mx = mu.finalize_xof();
    mx.read(&mut mu_b);
    verify_core(vk, &mu_b, sig)
}

pub fn verify_mu_internal(vk: &[u8; VK_LEN], mu_b: &[u8; 64], sig: &[u8; SIG_LEN]) -> bool {
    verify_core(vk, mu_b, sig)
}

fn verify_core(vk: &[u8; VK_LEN], mu_b: &[u8; 64], sig: &[u8; SIG_LEN]) -> bool {
    let rho = &vk[..32];
    let t1 = decode_t1(&vk[32..], K);

    let mut a_hat = vec![[0u64; 256]; K * L];
    for i in 0..K {
        for j in 0..L {
            a_hat[i * L + j] = rej_ntt_poly(rho, i as u8, j as u8);
        }
    }

    let mut t1_2d = Vec::with_capacity(K);
    for i in 0..K {
        let mut p = [0u64; 256];
        for k in 0..256 {
            p[k] = t1[i][k] * (1u64 << D) % Q;
        }
        t1_2d.push(p);
    }
    let t1_2d_hat = ntt_vec(&t1_2d);

    let c_tilde = &sig[..LAMBDA];
    let z = decode_z(&sig[LAMBDA..LAMBDA + L * 640], L);
    let h = match unpack_h(&sig[LAMBDA + L * 640..]) {
        Some(h) => h,
        None => return false,
    };
    for i in 0..L {
        if infinity_norm(&z[i]) >= GAMMA1_MINUS_BETA {
            return false;
        }
    }

    let c = sample_in_ball(c_tilde, TAU);
    let mut c_hat = [0u64; 256];
    c_hat.copy_from_slice(&c);
    ntt(&mut c_hat);
    let z_hat = ntt_vec(&z);

    let mut az = [[0u64; 256]; 9];
    for i in 0..K {
        let mut p = [0u64; 256];
        for k in 0..256 {
            let mut acc = 0u64;
            for j in 0..L {
                acc = (acc + a_hat[i * L + j][k] * z_hat[j][k]) % Q;
            }
            p[k] = acc;
        }
        az[i] = p;
    }
    let mut w_hat = vec![[0u64; 256]; K];
    for i in 0..K {
        for k in 0..256 {
            let ct1 = c_hat[k] * t1_2d_hat[i][k] % Q;
            w_hat[i][k] = (az[i][k] + Q - ct1) % Q;
        }
    }
    let w_approx = invntt_vec(&w_hat);

    let mut w1 = Vec::with_capacity(K);
    for i in 0..K {
        let mut p = [0u64; 256];
        for k in 0..256 {
            p[k] = use_hint(h[i][k], w_approx[i][k]);
        }
        w1.push(p);
    }
    let w1_tilde = encode_w1(&w1);

    let mut mh = Shake256::default();
    mh.update(mu_b);
    mh.update(&w1_tilde);
    let mut ctil = [0u8; LAMBDA];
    let mut mxx = mh.finalize_xof();
    mxx.read(&mut ctil);
    ctil == *c_tilde
}

pub struct KeygenMid {
    pub rho: [u8; 32],
    pub rho2: [u8; 64],
    pub kk: [u8; 32],
    pub a_hat: Vec<[u64; 256]>,
    pub s1: Vec<[u64; 256]>,
    pub s2: Vec<[u64; 256]>,
    pub s1_hat: Vec<[u64; 256]>,
    pub t_std: Vec<[u64; 256]>,
    pub t1: Vec<[u64; 256]>,
    pub t0: Vec<[u64; 256]>,
    pub tr: [u8; 64],
}

pub struct SignMid {
    pub rho: [u8; 32],
    pub kk: [u8; 32],
    pub s1: Vec<[u64; 256]>,
    pub s2: Vec<[u64; 256]>,
    pub t0: Vec<[u64; 256]>,
    pub s1_hat: Vec<[u64; 256]>,
    pub s2_hat: Vec<[u64; 256]>,
    pub t0_hat: Vec<[u64; 256]>,
    pub a_hat: Vec<[u64; 256]>,
    pub rhopp: [u8; 64],
    pub kappa: u16,
    pub y: Vec<[u64; 256]>,
    pub y_hat: Vec<[u64; 256]>,
    pub w: Vec<[u64; 256]>,
    pub w1: Vec<[u64; 256]>,
    pub w1_tilde: Vec<u8>,
    pub c_tilde: [u8; LAMBDA],
    pub c: [u64; 256],
    pub c_hat: [u64; 256],
    pub cs1: Vec<[u64; 256]>,
    pub cs2: Vec<[u64; 256]>,
    pub zz: Vec<[u64; 256]>,
    pub r0: Vec<[u64; 256]>,
    pub w_minus_cs2: Vec<[u64; 256]>,
    pub ct0: Vec<[u64; 256]>,
    pub hh: Vec<[bool; 256]>,
}

pub struct VerifyMid {
    pub rho: [u8; 32],
    pub t1: Vec<[u64; 256]>,
    pub tr: [u8; 64],
    pub a_hat: Vec<[u64; 256]>,
    pub t1_2d_hat: Vec<[u64; 256]>,
    pub c_tilde: [u8; LAMBDA],
    pub c: [u64; 256],
    pub c_hat: [u64; 256],
    pub z_hat: Vec<[u64; 256]>,
    pub w_hat: Vec<[u64; 256]>,
    pub w_approx: Vec<[u64; 256]>,
    pub w1: Vec<[u64; 256]>,
    pub ctil: [u8; LAMBDA],
}

pub fn keygen_mid(seed: &[u8; 32]) -> (([u8; VK_LEN], [u8; SK_LEN]), KeygenMid) {
    let mut gd = Vec::with_capacity(34);
    gd.extend_from_slice(seed);
    gd.push(K as u8);
    gd.push(L as u8);
    let mut gout = [0u8; 128];
    let mut s = Shake256::default();
    s.update(&gd);
    s.finalize_xof().read(&mut gout);
    let mut rho = [0u8; 32];
    let mut rho2 = [0u8; 64];
    let mut kk = [0u8; 32];
    rho.copy_from_slice(&gout[..32]);
    rho2.copy_from_slice(&gout[32..96]);
    kk.copy_from_slice(&gout[96..128]);

    let mut a_hat = vec![[0u64; 256]; K * L];
    for i in 0..K {
        for j in 0..L {
            a_hat[i * L + j] = rej_ntt_poly(&rho, i as u8, j as u8);
        }
    }

    let mut s1 = Vec::with_capacity(L);
    let mut s2 = Vec::with_capacity(K);
    for i in 0..L {
        s1.push(rej_bounded_poly(&rho2, i as u16));
    }
    for i in 0..K {
        s2.push(rej_bounded_poly(&rho2, (L + i) as u16));
    }

    let s1_hat = ntt_vec(&s1);
    let t = mat_mul_vec(&a_hat, &s1_hat, K, L);
    let t = invntt_vec(&t);
    let mut t_std = t;
    for i in 0..K {
        for k in 0..256 {
            t_std[i][k] = (t_std[i][k] + s2[i][k]) % Q;
        }
    }

    let mut t1 = Vec::with_capacity(K);
    let mut t0 = Vec::with_capacity(K);
    for i in 0..K {
        let mut p1 = [0u64; 256];
        let mut p0 = [0u64; 256];
        for k in 0..256 {
            let (r1, r0) = power2round(t_std[i][k]);
            p1[k] = r1;
            p0[k] = r0;
        }
        t1.push(p1);
        t0.push(p0);
    }

    let mut vk = Vec::with_capacity(VK_LEN);
    vk.extend_from_slice(&rho);
    vk.extend_from_slice(&encode_t1(&t1));
    let mut tr = [0u8; 64];
    tr.copy_from_slice(&h(&vk)[..64]);

    let mut sk = Vec::with_capacity(SK_LEN);
    sk.extend_from_slice(&rho);
    sk.extend_from_slice(&kk);
    sk.extend_from_slice(&tr);
    sk.extend_from_slice(&encode_s(&s1));
    sk.extend_from_slice(&encode_s(&s2));
    sk.extend_from_slice(&encode_t0(&t0));

    let mid = KeygenMid {
        rho,
        rho2,
        kk,
        a_hat,
        s1,
        s2,
        s1_hat,
        t_std,
        t1,
        t0,
        tr,
    };
    ((vk.try_into().unwrap(), sk.try_into().unwrap()), mid)
}

pub fn sign_mu_mid(sk: &[u8; SK_LEN], mu_b: &[u8; 64]) -> ([u8; SIG_LEN], SignMid) {
    let rho: [u8; 32] = sk[..32].try_into().unwrap();
    let kk: [u8; 32] = sk[32..64].try_into().unwrap();
    let s1 = decode_s(&sk[128..128 + L * 128], L);
    let s2 = decode_s(&sk[128 + L * 128..128 + L * 128 + K * 128], K);
    let t0 = decode_t0(&sk[128 + L * 128 + K * 128..], K);
    let s1_hat = ntt_vec(&s1);
    let s2_hat = ntt_vec(&s2);
    let t0_hat = ntt_vec(&t0);

    let mut a_hat = vec![[0u64; 256]; K * L];
    for i in 0..K {
        for j in 0..L {
            a_hat[i * L + j] = rej_ntt_poly(&rho, i as u8, j as u8);
        }
    }

    let rnd = [0u8; 32];
    let mut rhop = Shake256::default();
    rhop.update(&kk);
    rhop.update(&rnd);
    rhop.update(mu_b);
    let mut rhopp = [0u8; 64];
    let mut rx = rhop.finalize_xof();
    rx.read(&mut rhopp);

    let mut kappa = 0u16;
    loop {
        let mut y = Vec::with_capacity(L);
        for i in 0..L {
            y.push(expand_mask_poly(&rhopp, kappa + i as u16));
        }
        let y_hat = ntt_vec(&y);
        let w = invntt_vec(&mat_mul_vec(&a_hat, &y_hat, K, L));

        let mut w1 = Vec::with_capacity(K);
        for i in 0..K {
            let mut p = [0u64; 256];
            for k in 0..256 {
                p[k] = high_bits(w[i][k]);
            }
            w1.push(p);
        }
        let w1_tilde = encode_w1(&w1);

        let mut mh = Shake256::default();
        mh.update(mu_b);
        mh.update(&w1_tilde);
        let mut ctil = [0u8; LAMBDA];
        let mut mxx = mh.finalize_xof();
        mxx.read(&mut ctil);

        let mut c = [0u64; 256];
        c.copy_from_slice(&sample_in_ball(&ctil, TAU));
        let mut c_hat = [0u64; 256];
        c_hat.copy_from_slice(&c);
        ntt(&mut c_hat);

        let mut cs1 = Vec::with_capacity(L);
        let mut cs2 = Vec::with_capacity(K);
        for i in 0..L {
            cs1.push(poly_mul_ntt(&c_hat, &s1_hat[i]));
        }
        for i in 0..K {
            cs2.push(poly_mul_ntt(&c_hat, &s2_hat[i]));
        }
        let cs1 = invntt_vec(&cs1);
        let cs2 = invntt_vec(&cs2);

        let mut zz = y.clone();
        let y_saved = y;
        let mut ok = true;
        let mut w_minus_cs2 = vec![[0u64; 256]; K];
        for i in 0..L {
            for k in 0..256 {
                zz[i][k] = (zz[i][k] + cs1[i][k]) % Q;
            }
            if infinity_norm(&zz[i]) >= GAMMA1_MINUS_BETA {
                ok = false;
            }
        }
        let mut r0 = vec![[0u64; 256]; K];
        for i in 0..K {
            for k in 0..256 {
                w_minus_cs2[i][k] = (w[i][k] + Q - cs2[i][k]) % Q;
                r0[i][k] = low_bits(w_minus_cs2[i][k]);
            }
            if infinity_norm(&r0[i]) >= GAMMA2_MINUS_BETA {
                ok = false;
            }
        }
        if !ok {
            kappa = kappa.wrapping_add(L as u16);
            continue;
        }

        let mut ct0 = Vec::with_capacity(K);
        for i in 0..K {
            ct0.push(poly_mul_ntt(&c_hat, &t0_hat[i]));
        }
        let ct0 = invntt_vec(&ct0);

        let mut hh = vec![[false; 256]; K];
        let mut wgt = 0usize;
        ok = true;
        for i in 0..K {
            for k in 0..256 {
                let nct0 = (Q - ct0[i][k]) % Q;
                let wcc = (w_minus_cs2[i][k] + ct0[i][k]) % Q;
                hh[i][k] = make_hint(nct0, wcc);
                if hh[i][k] {
                    wgt += 1;
                }
            }
            if infinity_norm(&ct0[i]) >= GAMMA2 {
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

        let mut sig = Vec::with_capacity(SIG_LEN);
        sig.extend_from_slice(&ctil);
        sig.extend_from_slice(&encode_z(&zz));
        sig.extend_from_slice(&pack_h(&hh));
        let out: [u8; SIG_LEN] = sig.try_into().unwrap();
        let mid = SignMid {
            rho,
            kk,
            s1,
            s2,
            t0,
            s1_hat,
            s2_hat,
            t0_hat,
            a_hat,
            rhopp,
            kappa,
            y: y_saved,
            y_hat,
            w,
            w1,
            w1_tilde,
            c_tilde: ctil,
            c,
            c_hat,
            cs1,
            cs2,
            zz,
            r0,
            w_minus_cs2,
            ct0,
            hh,
        };
        return (out, mid);
    }
}

pub fn verify_mid(vk: &[u8; VK_LEN], mu_b: &[u8; 64], sig: &[u8; SIG_LEN]) -> (bool, VerifyMid) {
    let rho: [u8; 32] = vk[..32].try_into().unwrap();
    let t1 = decode_t1(&vk[32..], K);

    let mut a_hat = vec![[0u64; 256]; K * L];
    for i in 0..K {
        for j in 0..L {
            a_hat[i * L + j] = rej_ntt_poly(&rho, i as u8, j as u8);
        }
    }

    let mut t1_2d = Vec::with_capacity(K);
    for i in 0..K {
        let mut p = [0u64; 256];
        for k in 0..256 {
            p[k] = t1[i][k] * (1u64 << D) % Q;
        }
        t1_2d.push(p);
    }
    let t1_2d_hat = ntt_vec(&t1_2d);

    let mut c_tilde = [0u8; LAMBDA];
    c_tilde.copy_from_slice(&sig[..LAMBDA]);
    let z = decode_z(&sig[LAMBDA..LAMBDA + L * 640], L);
    let h = match unpack_h(&sig[LAMBDA + L * 640..]) {
        Some(h) => h,
        None => return (false, finish_verify_mid(rho, t1, a_hat, t1_2d_hat, c_tilde, mu_b)),
    };
    for i in 0..L {
        if infinity_norm(&z[i]) >= GAMMA1_MINUS_BETA {
            return (false, finish_verify_mid(rho, t1, a_hat, t1_2d_hat, c_tilde, mu_b));
        }
    }

    let mut c = [0u64; 256];
    c.copy_from_slice(&sample_in_ball(&c_tilde, TAU));
    let mut c_hat = [0u64; 256];
    c_hat.copy_from_slice(&c);
    ntt(&mut c_hat);
    let z_hat = ntt_vec(&z);

    let mut w_hat = vec![[0u64; 256]; K];
    for i in 0..K {
        for k in 0..256 {
            let mut acc = 0u64;
            for j in 0..L {
                acc = (acc + a_hat[i * L + j][k] * z_hat[j][k]) % Q;
            }
            let ct1 = c_hat[k] * t1_2d_hat[i][k] % Q;
            w_hat[i][k] = (acc + Q - ct1) % Q;
        }
    }
    let w_approx = invntt_vec(&w_hat);

    let mut w1 = Vec::with_capacity(K);
    for i in 0..K {
        let mut p = [0u64; 256];
        for k in 0..256 {
            p[k] = use_hint(h[i][k], w_approx[i][k]);
        }
        w1.push(p);
    }
    let w1_tilde = encode_w1(&w1);

    let mut mh = Shake256::default();
    mh.update(mu_b);
    mh.update(&w1_tilde);
    let mut ctil = [0u8; LAMBDA];
    let mut mxx = mh.finalize_xof();
    mxx.read(&mut ctil);

    let mid = VerifyMid {
        rho,
        t1,
        tr: [0u8; 64],
        a_hat,
        t1_2d_hat,
        c_tilde,
        c,
        c_hat,
        z_hat,
        w_hat,
        w_approx,
        w1,
        ctil,
    };
    (ctil == c_tilde, mid)
}

fn finish_verify_mid(
    rho: [u8; 32],
    t1: Vec<[u64; 256]>,
    a_hat: Vec<[u64; 256]>,
    t1_2d_hat: Vec<[u64; 256]>,
    c_tilde: [u8; LAMBDA],
    mu_b: &[u8; 64],
) -> VerifyMid {
    let c = sample_in_ball(&c_tilde, TAU);
    let mut c_hat = [0u64; 256];
    c_hat.copy_from_slice(&c);
    ntt(&mut c_hat);
    let w1 = vec![[0u64; 256]; K];
    let mut mh = Shake256::default();
    mh.update(mu_b);
    mh.update(&encode_w1(&w1));
    let mut ctil = [0u8; LAMBDA];
    let mut mxx = mh.finalize_xof();
    mxx.read(&mut ctil);
    VerifyMid {
        rho,
        t1,
        tr: [0u8; 64],
        a_hat,
        t1_2d_hat,
        c_tilde,
        c,
        c_hat,
        z_hat: vec![[0u64; 256]; L],
        w_hat: vec![[0u64; 256]; K],
        w_approx: vec![[0u64; 256]; K],
        w1,
        ctil,
    }
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
