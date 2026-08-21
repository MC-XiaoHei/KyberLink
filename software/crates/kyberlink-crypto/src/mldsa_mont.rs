fn pow_mod(mut b: u64, mut e: u64) -> u64 {
    let mut r = 1u64;
    while e > 0 {
        if e & 1 == 1 {
            r = r * b % Q_U32 as u64;
        }
        b = b * b % Q_U32 as u64;
        e >>= 1;
    }
    r
}

fn bitrev8(x: u64) -> u64 {
    x.reverse_bits() >> 56
}

fn zetas() -> [u64; 256] {
    let mut z = [0u64; 256];
    for i in 0..256 {
        z[i] = pow_mod(1753, bitrev8(i as u64));
    }
    z
}

const Q_U32: u32 = 8380417;
const Q_INV: u32 = 4236238847; // -Q^{-1} mod 2^32
const R2: u32 = 2365951; // R^2 mod Q
const INV_256_MONT: u32 = 16382; // 256^{-1} * R mod Q

#[inline(always)]
fn mont_mul(a: u32, b: u32) -> u32 {
    let t = (a as u64) * (b as u64);
    let m = (t as u32).wrapping_mul(Q_INV);
    let t2 = t + (m as u64) * (Q_U32 as u64);
    let r = (t2 >> 32) as u32;
    if r >= Q_U32 {
        r - Q_U32
    } else {
        r
    }
}

#[inline(always)]
fn to_mont(x: u64) -> u64 {
    mont_mul(x as u32, R2) as u64
}

#[inline(always)]
fn from_mont(x: u64) -> u64 {
    mont_mul(x as u32, 1) as u64
}

pub fn ntt(a: &mut [u64; 256]) {
    let z = zetas();
    let mut zm = [0u64; 256];
    for i in 0..256 {
        zm[i] = to_mont(z[i]);
    }
    for v in a.iter_mut() {
        *v = to_mont(*v);
    }
    let mut m = 0usize;
    let mut len = 128usize;
    while len >= 1 {
        let mut start = 0usize;
        while start < 256 {
            m += 1;
            let zi = zm[m] as u32;
            for j in start..start + len {
                let t = mont_mul(zi, a[j + len] as u32) as u64;
                let d = a[j] + Q_U32 as u64 - t;
                a[j + len] = if d >= Q_U32 as u64 { d - Q_U32 as u64 } else { d };
                let s2 = a[j] + t;
                a[j] = if s2 >= Q_U32 as u64 { s2 - Q_U32 as u64 } else { s2 };
            }
            start += 2 * len;
        }
        len >>= 1;
    }
    for v in a.iter_mut() {
        *v = from_mont(*v);
    }
}

pub fn invntt(a: &mut [u64; 256]) {
    let z = zetas();
    let mut zm = [0u64; 256];
    for i in 0..256 {
        zm[i] = to_mont(z[i]);
    }
    for v in a.iter_mut() {
        *v = to_mont(*v);
    }
    let mut m = 256usize;
    let mut len = 1usize;
    while len <= 128 {
        let mut start = 0usize;
        while start < 256 {
            m -= 1;
            let zi = (Q_U32 as u64 - zm[m]) as u32;
            for j in start..start + len {
                let t = a[j];
                let s3 = t + a[j + len];
                a[j] = if s3 >= Q_U32 as u64 { s3 - Q_U32 as u64 } else { s3 };
                let d = t + Q_U32 as u64 - a[j + len];
                let d = if d >= Q_U32 as u64 { d - Q_U32 as u64 } else { d };
                a[j + len] = mont_mul(zi, d as u32) as u64;
            }
            start += 2 * len;
        }
        len <<= 1;
    }
    for v in a.iter_mut() {
        *v = mont_mul(*v as u32, INV_256_MONT) as u64;
        *v = from_mont(*v);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mont_roundtrip() {
        for x in [0u64, 1, 2, 1000, 8380416, 4190208] {
            assert_eq!(from_mont(to_mont(x)), x, "x={}", x);
        }
        let a = 12345u64; let b = 67890u64;
        let am = to_mont(a); let bm = to_mont(b);
        let p = mont_mul(am as u32, bm as u32) as u64;
        assert_eq!(from_mont(p), (a * b) % Q_U32 as u64);
    }

    #[test]
    fn ntt_roundtrip() {
        let mut f = [0u64; 256];
        for i in 0..256 { f[i] = ((i * 7 + 3) % Q_U32 as usize) as u64; }
        let orig = f;
        ntt(&mut f);
        invntt(&mut f);
        assert_eq!(f, orig);
    }
}
