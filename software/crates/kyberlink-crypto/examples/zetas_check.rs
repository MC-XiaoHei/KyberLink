fn main() {
    let zeta = 1753u64;
    fn pow_mod(mut b: u64, mut e: u64) -> u64 {
        let mut r = 1u64;
        while e > 0 {
            if e & 1 == 1 {
                r = r * b % 8380417;
            }
            b = b * b % 8380417;
            e >>= 1;
        }
        r
    }
    fn bitrev8(x: u64) -> u64 {
        x.reverse_bits() >> 56
    }
    let zetas: Vec<u32> = (0..256)
        .map(|i| pow_mod(zeta, bitrev8(i as u64)) as u32)
        .collect();
    let const_rs: Vec<u32> = include_str!("../src/zetas_const.rs")
        .lines()
        .flat_map(|l| {
            l.trim_start_matches("    ")
                .trim_end_matches(",")
                .split(", ")
                .filter_map(|s| s.parse::<u32>().ok())
        })
        .collect();
    println!("len zetas={} const={}", zetas.len(), const_rs.len());
    for i in 0..256 {
        if zetas[i] != const_rs[i] {
            println!("MISMATCH at {}: run={} const={}", i, zetas[i], const_rs[i]);
            return;
        }
    }
    println!("MATCH: all 256 entries agree");
}
