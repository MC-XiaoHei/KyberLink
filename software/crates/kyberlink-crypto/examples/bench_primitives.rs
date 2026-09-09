use kyberlink_crypto::kem_internal::{keygen_internal as kem_keygen, encaps_internal, decaps_internal};
use kyberlink_crypto::mldsa_internal::{keygen_internal as dsa_keygen, sign_internal, verify_internal};
use kyberlink_crypto::{ntt, mldsa_mont};
use std::time::Instant;

fn main() {
    let seed = [7u8; 32];

    let t = Instant::now();
    let (ek, dk) = kem_keygen(&seed, &seed);
    println!("ML-KEM keygen : {:?}", t.elapsed());

    let t = Instant::now();
    let (ss, ct) = encaps_internal(&ek, &seed);
    println!("ML-KEM encaps : {:?}", t.elapsed());

    let t = Instant::now();
    let ss2 = decaps_internal(&dk, &ct);
    println!("ML-KEM decaps : {:?}", t.elapsed());

    let t = Instant::now();
    let (vk, sk) = dsa_keygen(&seed);
    println!("ML-DSA keygen : {:?}", t.elapsed());

    let t = Instant::now();
    let sig = sign_internal(&sk, &seed, b"");
    println!("ML-DSA sign   : {:?}", t.elapsed());

    let t = Instant::now();
    let _ = verify_internal(&vk, &seed, b"", &sig);
    println!("ML-DSA verify : {:?}", t.elapsed());

    let mut f = [0u16; 256];
    let t = Instant::now();
    for _ in 0..1000 { ntt::ntt(&mut f); }
    println!("Kyber NTT x1000: {:?}", t.elapsed());

    let mut g = [0u32; 256];
    let t = Instant::now();
    for _ in 0..1000 {
        mldsa_mont::ntt(&mut g);
        mldsa_mont::invntt(&mut g);
    }
    println!("ML-DSA NTT+inv x1000: {:?}", t.elapsed());
}
