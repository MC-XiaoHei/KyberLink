use kyberlink_crypto::kem_internal::{
    KeygenMid, EncapsMid, DecapsMid, keygen_mid,
};

fn main() {
    println!("KeygenMid  size = {} bytes", std::mem::size_of::<KeygenMid>());
    println!("EncapsMid  size = {} bytes", std::mem::size_of::<EncapsMid>());
    println!("DecapsMid  size = {} bytes", std::mem::size_of::<DecapsMid>());
    let d = [1u8; 32];
    let z = [2u8; 32];
    let (_k, _mid) = keygen_mid(&d, &z);
    println!("keygen_mid OK, KeygenMid = {} bytes", std::mem::size_of_val(&_mid));
}
