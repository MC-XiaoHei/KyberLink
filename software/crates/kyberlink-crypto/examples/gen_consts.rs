fn main() {
    let seed = [7u8; 32];
    let (vk, sk) = kyberlink_crypto::mldsa_internal::keygen_internal(&seed);
    let msg = [0x42u8; 64];
    let sig = kyberlink_crypto::mldsa_internal::sign_internal(&sk, &msg, b"");
    println!("const MSG: [u8; 64] = {:?};", msg);
    print!("const VK: [u8; 1952] = [");
    for (i, b) in vk.iter().enumerate() {
        if i % 16 == 0 { print!("\n    "); }
        print!("{:#04x}, ", b);
    }
    println!("\n];");
    print!("const SIG: [u8; 3309] = [");
    for (i, b) in sig.iter().enumerate() {
        if i % 16 == 0 { print!("\n    "); }
        print!("{:#04x}, ", b);
    }
    println!("\n];");
}
