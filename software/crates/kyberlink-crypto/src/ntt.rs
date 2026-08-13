pub const Q: u16 = 3329;

const ZETAS: [i16; 128] = [
    1, 1729, 2580, 3289, 2642, 630, 1897, 848,
    1062, 1919, 193, 797, 2786, 3260, 569, 1746,
    296, 2447, 1339, 1476, 3046, 56, 2240, 1333,
    1426, 2094, 535, 2882, 2393, 2879, 1974, 821,
    289, 331, 3253, 1756, 1197, 2304, 2277, 2055,
    650, 1977, 2513, 632, 2865, 33, 1320, 1915,
    2319, 1435, 807, 452, 1438, 2868, 1534, 2402,
    2647, 2617, 1481, 648, 2474, 3110, 1227, 910,
    17, 2761, 583, 2649, 1637, 723, 2288, 1100,
    1409, 2662, 3281, 233, 756, 2156, 3015, 3050,
    1703, 1651, 2789, 1789, 1847, 952, 1461, 2687,
    939, 2308, 2437, 2388, 733, 2337, 268, 641,
    1584, 2298, 2037, 3220, 375, 2549, 2090, 1645,
    1063, 319, 2773, 757, 2099, 561, 2466, 2594,
    2804, 1092, 403, 1026, 1143, 2150, 2775, 886,
    1722, 1212, 1874, 1029, 2110, 2935, 885, 2154,
];

pub const GAMMAS: [i16; 128] = [
    17, -17, 2761, -2761, 583, -583, 2649, -2649,
    1637, -1637, 723, -723, 2288, -2288, 1100, -1100,
    1409, -1409, 2662, -2662, 3281, -3281, 233, -233,
    756, -756, 2156, -2156, 3015, -3015, 3050, -3050,
    1703, -1703, 1651, -1651, 2789, -2789, 1789, -1789,
    1847, -1847, 952, -952, 1461, -1461, 2687, -2687,
    939, -939, 2308, -2308, 2437, -2437, 2388, -2388,
    733, -733, 2337, -2337, 268, -268, 641, -641,
    1584, -1584, 2298, -2298, 2037, -2037, 3220, -3220,
    375, -375, 2549, -2549, 2090, -2090, 1645, -1645,
    1063, -1063, 319, -319, 2773, -2773, 757, -757,
    2099, -2099, 561, -561, 2466, -2466, 2594, -2594,
    2804, -2804, 1092, -1092, 403, -403, 1026, -1026,
    1143, -1143, 2150, -2150, 2775, -2775, 886, -886,
    1722, -1722, 1212, -1212, 1874, -1874, 1029, -1029,
    2110, -2110, 2935, -2935, 885, -885, 2154, -2154,
];

pub fn ntt(f: &mut [u16; 256]) {
    let q = Q as i32;
    let mut i = 1;
    let mut len = 128;
    while len >= 2 {
        let mut start = 0;
        while start < 256 {
            let zeta = ZETAS[i] as i32;
            i += 1;
            for j in start..start + len {
                let t = (zeta * f[j + len] as i32).rem_euclid(q) as u16;
                let fj = f[j];
                f[j] = (fj + t) % Q;
                f[j + len] = (fj + Q - t) % Q;
            }
            start += 2 * len;
        }
        len /= 2;
    }
}

pub fn invntt(f: &mut [u16; 256]) {
    let q = Q as i32;
    let mut i = 127;
    let mut len = 2;
    while len <= 128 {
        let mut start = 0;
        while start < 256 {
            let zeta = ZETAS[i] as i32;
            i -= 1;
            for j in start..start + len {
                let fj = f[j] as i32;
                let fjl = f[j + len] as i32;
                f[j] = ((fj + fjl) % q) as u16;
                f[j + len] = (zeta * (fjl - fj)).rem_euclid(q) as u16;
            }
            start += 2 * len;
        }
        len *= 2;
    }
    for v in f.iter_mut() {
        *v = (*v as i32 * 3303 % q) as u16;
    }
}

pub fn basemul(a: &[u16; 2], b: &[u16; 2], gamma: i16) -> [u16; 2] {
    let q = Q as i64;
    let a0 = a[0] as i64;
    let a1 = a[1] as i64;
    let b0 = b[0] as i64;
    let b1 = b[1] as i64;
    let c0 = (a0 * b0 + a1 * b1 * gamma as i64).rem_euclid(q) as u16;
    let c1 = (a0 * b1 + a1 * b0).rem_euclid(q) as u16;
    [c0, c1]
}

pub fn matmul(a: &[[u16; 256]; 9], b: &[[u16; 256]; 3], transpose: bool) -> [[u16; 256]; 3] {
    let mut c = [[0u16; 256]; 3];
    for i in 0..3 {
        for k in 0..128 {
            let mut acc0 = 0u16;
            let mut acc1 = 0u16;
            for j in 0..3 {
                let aj = if transpose { &a[j * 3 + i] } else { &a[i * 3 + j] };
                let pair = basemul(
                    &[aj[2 * k], aj[2 * k + 1]],
                    &[b[j][2 * k], b[j][2 * k + 1]],
                    GAMMAS[k],
                );
                acc0 = (acc0 + pair[0]) % Q;
                acc1 = (acc1 + pair[1]) % Q;
            }
            c[i][2 * k] = acc0;
            c[i][2 * k + 1] = acc1;
        }
    }
    c
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rand_poly(mut s: u64) -> [u16; 256] {
        let mut f = [0u16; 256];
        for v in f.iter_mut() {
            s ^= s << 13;
            s ^= s >> 7;
            s ^= s << 17;
            *v = (s % Q as u64) as u16;
        }
        f
    }

    fn polymul_naive(a: &[u16; 256], b: &[u16; 256]) -> [u16; 256] {
        let q = Q as i64;
        let mut c = [0u16; 256];
        for i in 0..256 {
            for j in 0..256 {
                let k = (i + j) % 256;
                let sign = if i + j >= 256 { -1 } else { 1 };
                c[k] = (c[k] as i64 + sign * a[i] as i64 * b[j] as i64).rem_euclid(q) as u16;
            }
        }
        c
    }

    #[test]
    fn ntt_invntt_roundtrip() {
        for s in 0..100u64 {
            let f = rand_poly(s);
            let mut g = f;
            ntt(&mut g);
            invntt(&mut g);
            assert_eq!(g, f);
        }
    }

    #[test]
    fn multiply_matches_ntt_domain() {
        for s in 0..100u64 {
            let a = rand_poly(s);
            let b = rand_poly(s + 1);
            let mut at = a;
            let mut bt = b;
            ntt(&mut at);
            ntt(&mut bt);
            let mut ct = [0u16; 256];
            for i in 0..128 {
                let r = basemul(
                    &[at[2 * i], at[2 * i + 1]],
                    &[bt[2 * i], bt[2 * i + 1]],
                    GAMMAS[i],
                );
                ct[2 * i] = r[0];
                ct[2 * i + 1] = r[1];
            }
            invntt(&mut ct);
            assert_eq!(ct, polymul_naive(&a, &b));
        }
    }

    #[test]
    fn zero_maps_to_zero() {
        let mut f = [0u16; 256];
        ntt(&mut f);
        assert_eq!(f, [0u16; 256]);
    }

    #[test]
    fn matmul_matches_pointwise() {
        for s in 0..20u64 {
            let mut a = [[0u16; 256]; 9];
            let mut b = [[0u16; 256]; 3];
            for (idx, row) in a.iter_mut().enumerate() {
                *row = rand_poly(s * 10 + idx as u64);
            }
            for (idx, v) in b.iter_mut().enumerate() {
                *v = rand_poly(s * 10 + 20 + idx as u64);
            }
            for transpose in [false, true] {
                let c = matmul(&a, &b, transpose);
                for i in 0..3 {
                    let mut ci = [0u16; 256];
                    for j in 0..3 {
                        let aj = if transpose { &a[j * 3 + i] } else { &a[i * 3 + j] };
                        let mut t = [0u16; 256];
                        for k in 0..128 {
                            let r = basemul(
                                &[aj[2 * k], aj[2 * k + 1]],
                                &[b[j][2 * k], b[j][2 * k + 1]],
                                GAMMAS[k],
                            );
                            t[2 * k] = r[0];
                            t[2 * k + 1] = r[1];
                        }
                        for k in 0..256 {
                            ci[k] = (ci[k] as i64 + t[k] as i64).rem_euclid(Q as i64) as u16;
                        }
                    }
                    assert_eq!(c[i], ci, "s={s} transpose={transpose} i={i}");
                }
            }
        }
    }
}
