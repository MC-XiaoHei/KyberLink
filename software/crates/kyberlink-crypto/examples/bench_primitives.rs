use kyberlink_crypto::kem_internal::{
    decaps_internal, encaps_internal, keygen_internal as kem_keygen, CT_LEN, DK_LEN, EK_LEN,
};
use kyberlink_crypto::mldsa_internal::{
    keygen_internal as dsa_keygen, sign_internal, verify_internal,
};
use kyberlink_crypto::{mldsa_mont, ntt};
use std::time::Instant;

fn main() {
    let mut ms = kyberlink_crypto::scratch::MldsaScratch::new();
    let seed = [7u8; 32];

    let t = Instant::now();
    let mut kem = kyberlink_crypto::scratch::KemScratch::new();
    let mut ek = [0u8; EK_LEN];
    let mut dk = [0u8; DK_LEN];
    kem_keygen(&seed, &seed, &mut kem, &mut ek, &mut dk);
    println!("ML-KEM keygen : {:?}", t.elapsed());

    let t = Instant::now();
    let mut ss = [0u8; 32];
    let mut ct = [0u8; CT_LEN];
    encaps_internal(&ek, &seed, &mut kem, &mut ss, &mut ct);
    println!("ML-KEM encaps : {:?}", t.elapsed());

    let t = Instant::now();
    let _ = decaps_internal(&dk, &ct, &mut kem);
    println!("ML-KEM decaps : {:?}", t.elapsed());

    let t = Instant::now();
    let (vk, sk) = dsa_keygen(&seed);
    println!("ML-DSA keygen : {:?}", t.elapsed());

    let t = Instant::now();
    let sig = sign_internal(&sk, &seed, b"");
    println!("ML-DSA sign   : {:?}", t.elapsed());

    let t = Instant::now();
    let _ = verify_internal(&vk, &seed, b"", &sig, &mut ms);
    println!("ML-DSA verify : {:?}", t.elapsed());

    let mut f = [0u16; 256];
    let t = Instant::now();
    for _ in 0..1000 {
        ntt::ntt(&mut f);
    }
    println!("Kyber NTT x1000: {:?}", t.elapsed());

    let mut g = [0u32; 256];
    let t = Instant::now();
    for _ in 0..1000 {
        mldsa_mont::ntt(&mut g);
        mldsa_mont::invntt(&mut g);
    }
    println!("ML-DSA NTT+inv x1000: {:?}", t.elapsed());
}
