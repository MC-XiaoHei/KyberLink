use kyberlink_crypto::kem_internal::{decaps_internal, encaps_internal, keygen_internal};
use kyberlink_crypto::mldsa_internal::{keygen_internal as dsa_keygen, sign_internal, verify_internal};
use std::time::Instant;

fn main() {
    let seed = [7u8; 32];

    let t = Instant::now();
    let (vk, sk) = dsa_keygen(&seed);
    let t_keygen = t.elapsed();
    println!("self ML-DSA keygen : {:?}", t_keygen);

    let t = Instant::now();
    let sig = sign_internal(&sk, &seed, b"");
    let t_sign = t.elapsed();
    println!("self ML-DSA sign   : {:?}", t_sign);

    let t = Instant::now();
    let ok = verify_internal(&vk, &seed, b"", &sig);
    let t_verify = t.elapsed();
    println!("self ML-DSA verify : {:?} ok={}", t_verify, ok);

    use kyberlink_crypto::sign::{sign, verify, SignKeyPair};
    let t = Instant::now();
    let kp = SignKeyPair::from_seed(&seed);
    let t_kp = t.elapsed();
    println!("ml-dsa   keygen     : {:?}", t_kp);

    let t = Instant::now();
    let sig_std = sign(&kp.sk, &seed);
    let t_sig = t.elapsed();
    println!("ml-dsa   sign       : {:?}", t_sig);

    let t = Instant::now();
    let ok_std = verify(&kp.vk, &seed, &sig_std);
    let t_ver = t.elapsed();
    println!("ml-dsa   verify     : {:?} ok={:?}", t_ver, ok_std.is_ok());

    let (ek, dk) = keygen_internal(&seed, &seed);

    let t = Instant::now();
    let (ss, ct) = encaps_internal(&ek, &seed);
    println!("self ML-KEM encaps : {:?}", t.elapsed());

    let t = Instant::now();
    let ss2 = decaps_internal(&dk, &ct);
    println!("self ML-KEM decaps : {:?}", t.elapsed());

    use kyberlink_crypto::kem::{encapsulate_deterministic, decapsulate, KemKeyPair};
    let t = Instant::now();
    let kpk = KemKeyPair::from_seed(&[7u8; 64]);
    println!("ml-kem   keygen     : {:?}", t.elapsed());

    let t = Instant::now();
    let (ct_std, ss_std) = encapsulate_deterministic(&kpk.ek, &[2u8; 32]);
    println!("ml-kem   encaps     : {:?}", t.elapsed());

    let t = Instant::now();
    let ss2_std = decapsulate(&kpk.dk, &ct_std);
    println!("ml-kem   decaps     : {:?}", t.elapsed());
}
