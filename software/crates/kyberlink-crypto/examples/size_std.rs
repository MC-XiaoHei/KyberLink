use kyberlink_crypto::sign::{SignKeyPair, Signature};
use kyberlink_crypto::kem::KemKeyPair;

fn main() {
    let kp = SignKeyPair::from_seed(&[7u8; 32]);
    println!("SigningKey   size = {} bytes", std::mem::size_of_val(&kp.sk));
    println!("VerifyingKey size = {} bytes", std::mem::size_of_val(&kp.vk));
    println!("Signature    size = {} bytes", std::mem::size_of::<Signature>());
    let kek = KemKeyPair::from_seed(&[7u8; 64]);
    println!("EncapsKey    size = {} bytes", std::mem::size_of_val(&kek.ek));
    println!("DecapsKey    size = {} bytes", std::mem::size_of_val(&kek.dk));
    println!("Total kp+kem keys = {} bytes", 
        std::mem::size_of_val(&kp.sk) + std::mem::size_of_val(&kp.vk) 
        + std::mem::size_of_val(&kek.ek) + std::mem::size_of_val(&kek.dk));
}
