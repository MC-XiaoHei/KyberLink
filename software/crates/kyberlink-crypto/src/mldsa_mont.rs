const Q_U32: u32 = 8380417;
const Q_INV: u32 = 4236238847; // -Q^{-1} mod 2^32
const R2: u32 = 2365951; // R^2 mod Q
const INV_256_MONT: u32 = 16382; // 256^{-1} * R mod Q

const ZETAS: [u32; 256] = include!("zetas_const.rs");

const Q_INV_C: u32 = Q_INV;

const fn cmont_mul(a: u32, b: u32) -> u32 {
    let t = (a as u64) * (b as u64);
    let m = (t as u32).wrapping_mul(Q_INV_C);
    let t2 = t + (m as u64) * (Q_U32 as u64);
    let r = (t2 >> 32) as u32;
    if r >= Q_U32 { r - Q_U32 } else { r }
}

const ZETAS_MONT: [u32; 256] = {
    let mut out = [0u32; 256];
    let mut i = 0;
    while i < 256 {
        out[i] = cmont_mul(ZETAS[i], R2);
        i += 1;
    }
    out
};

#[inline(always)]
fn mont_mul(a: u32, b: u32) -> u32 {
    let t = (a as u64) * (b as u64);
    let m = (t as u32).wrapping_mul(Q_INV);
    let t2 = t + (m as u64) * (Q_U32 as u64);
    let r = (t2 >> 32) as u32;
    if r >= Q_U32 { r - Q_U32 } else { r }
}

#[inline(always)]
fn to_mont(x: u32) -> u32 {
    mont_mul(x, R2)
}

#[inline(always)]
fn from_mont(x: u32) -> u32 {
    mont_mul(x, 1)
}

#[inline(always)]
fn ntt_layer<const LEN: usize, const ITER: usize>(a: &mut [u32; 256], zm: &[u32; 256], m: &mut usize) {
    #[allow(clippy::needless_range_loop)]
    for i in 0..ITER {
        let start = i * 2 * LEN;
        *m += 1;
        let zi = zm[*m];
        for j in start..start + LEN {
            let t = mont_mul(zi, a[j + LEN]);
            let d = a[j] + Q_U32 - t;
            a[j + LEN] = if d >= Q_U32 { d - Q_U32 } else { d };
            let s2 = a[j] + t;
            a[j] = if s2 >= Q_U32 { s2 - Q_U32 } else { s2 };
        }
    }
}

pub fn ntt(a: &mut [u32; 256]) {
    for v in a.iter_mut() {
        *v = to_mont(*v);
    }
    let mut m = 0usize;
    let zm = &ZETAS_MONT;
    ntt_layer::<128, 1>(a, zm, &mut m);
    ntt_layer::<64, 2>(a, zm, &mut m);
    ntt_layer::<32, 4>(a, zm, &mut m);
    ntt_layer::<16, 8>(a, zm, &mut m);
    ntt_layer::<8, 16>(a, zm, &mut m);
    ntt_layer::<4, 32>(a, zm, &mut m);
    ntt_layer::<2, 64>(a, zm, &mut m);
    ntt_layer::<1, 128>(a, zm, &mut m);
    for v in a.iter_mut() {
        *v = from_mont(*v);
    }
}

#[inline(always)]
fn invntt_layer<const LEN: usize, const ITER: usize>(a: &mut [u32; 256], zm: &[u32; 256], m: &mut usize) {
    #[allow(clippy::needless_range_loop)]
    for i in 0..ITER {
        let start = i * 2 * LEN;
        *m -= 1;
        let zi = Q_U32 - zm[*m];
        for j in start..start + LEN {
            let t = a[j];
            let s3 = t + a[j + LEN];
            a[j] = if s3 >= Q_U32 { s3 - Q_U32 } else { s3 };
            let d = t + Q_U32 - a[j + LEN];
            let d = if d >= Q_U32 { d - Q_U32 } else { d };
            a[j + LEN] = mont_mul(zi, d);
        }
    }
}

pub fn invntt(a: &mut [u32; 256]) {
    for v in a.iter_mut() {
        *v = to_mont(*v);
    }
    let mut m = 256usize;
    let zm = &ZETAS_MONT;
    invntt_layer::<1, 128>(a, zm, &mut m);
    invntt_layer::<2, 64>(a, zm, &mut m);
    invntt_layer::<4, 32>(a, zm, &mut m);
    invntt_layer::<8, 16>(a, zm, &mut m);
    invntt_layer::<16, 8>(a, zm, &mut m);
    invntt_layer::<32, 4>(a, zm, &mut m);
    invntt_layer::<64, 2>(a, zm, &mut m);
    invntt_layer::<128, 1>(a, zm, &mut m);
    for v in a.iter_mut() {
        *v = mont_mul(*v, INV_256_MONT);
        *v = from_mont(*v);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mont_roundtrip() {
        for x in [0u32, 1, 2, 1000, 8380416, 4190208] {
            assert_eq!(from_mont(to_mont(x)), x, "x={}", x);
        }
        let a = 12345u32;
        let b = 67890u32;
        let am = to_mont(a);
        let bm = to_mont(b);
        let p = mont_mul(am, bm);
        assert_eq!(from_mont(p), (a * b) % Q_U32);
    }

    #[test]
    fn ntt_roundtrip() {
        let mut f: [u32; 256] = core::array::from_fn(|i| ((i * 7 + 3) % Q_U32 as usize) as u32);
        let orig = f;
        ntt(&mut f);
        invntt(&mut f);
        assert_eq!(f, orig);
    }
}
