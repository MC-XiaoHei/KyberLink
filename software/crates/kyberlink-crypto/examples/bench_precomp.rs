use kyberlink_crypto::mldsa_internal::{
    keygen_internal, sign_internal, verify_internal, verify_precomp, verify_precomp_new,
};
use kyberlink_crypto::sign::{verify, SignKeyPair};
use std::time::Instant;

fn main() {
    let seed = [7u8; 32];
    let (vk, sk) = keygen_internal(&seed);
    let msg = [0x42u8; 64];
    let sig = sign_internal(&sk, &msg, b"");

    let t = Instant::now();
    let pc = verify_precomp_new(&vk);
    println!("precomp new   : {:?}", t.elapsed());

    let t = Instant::now();
    let mut ms = kyberlink_crypto::scratch::MldsaScratch::new();
    let ok_pc = verify_precomp(&pc, &msg, b"", &sig, &mut ms);
    println!("self verify+pc: {:?} ok={}", t.elapsed(), ok_pc);

    let t = Instant::now();
    let ok_self = verify_internal(&vk, &msg, b"", &sig, &mut ms);
    println!("self verify   : {:?} ok={}", t.elapsed(), ok_self);

    let kp = SignKeyPair::from_seed(&seed);
    let sig_std = kyberlink_crypto::sign::sign(&kp.sk, &msg);
    let t = Instant::now();
    let ok_std = verify(&kp.vk, &msg, &sig_std);
    println!("std verify    : {:?} ok={:?}", t.elapsed(), ok_std.is_ok());
}
