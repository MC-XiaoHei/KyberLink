use kyberlink_crypto::mldsa_mont;

fn main() {
    let mut a: [u32; 256] = core::array::from_fn(|i| ((i * 7 + 3) % 8380417) as u32);
    let orig = a;
    mldsa_mont::ntt(&mut a);
    mldsa_mont::invntt(&mut a);
    let barrett_ok = a == orig;
    println!("barrett roundtrip ok = {}", barrett_ok);
    if !barrett_ok {
        for i in 0..256 {
            if a[i] != orig[i] {
                println!("diff {}: got {} want {}", i, a[i], orig[i]);
                break;
            }
        }
    }
}
