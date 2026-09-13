use std::time::Instant;

const Q: u32 = 8380417;

fn main() {
    let qinv: u32 = 4236238847;
    let a = 1234567u32;
    let b = 7654321u32;

    let t = Instant::now();
    let mut x = 0u32;
    for _ in 0..1000000 {
        let tt = (a as u64) * (b as u64);
        let m = (tt as u32).wrapping_mul(qinv);
        let t2 = tt + (m as u64) * (Q as u64);
        let r = (t2 >> 32) as u32;
        x ^= if r >= Q { r - Q } else { r };
    }
    println!("mont x1M: {:?}", t.elapsed());

    let t = Instant::now();
    let mut y = 0u32;
    for _ in 0..1000000 {
        let p = (a as u64) * (b as u64);
        let v = ((p as u32 as u64) * 4190208u64) >> 31;
        let r = p.wrapping_sub(v * Q as u64) as u32;
        let r = if r >= Q { r - Q } else { r };
        y ^= r;
    }
    println!("barrett x1M: {:?}", t.elapsed());
    println!("x={} y={}", x, y);
}
