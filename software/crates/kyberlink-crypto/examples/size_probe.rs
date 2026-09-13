use kyberlink_crypto::handshake;
use kyberlink_crypto::kem_internal::{DK_LEN, EK_LEN};
use kyberlink_crypto::mldsa_internal::{SK_LEN, VK_LEN};

fn main() {
    println!("M1_LEN   = {}", handshake::M1_LEN);
    println!("M2_LEN   = {}", handshake::M2_LEN);
    println!("M3_LEN   = {}", handshake::M3_LEN);
    println!("M4_LEN   = {}", handshake::M4_LEN);
    println!("EK_LEN   = {}", EK_LEN);
    println!("DK_LEN   = {}", DK_LEN);
    println!("SK_LEN   = {}", SK_LEN);
    println!("VK_LEN   = {}", VK_LEN);
    println!(
        "InitiatorState size = {} bytes",
        std::mem::size_of::<handshake::InitiatorState>()
    );
    println!(
        "ResponderState size = {} bytes",
        std::mem::size_of::<handshake::ResponderState>()
    );
    println!(
        "SaParams size = {} bytes",
        std::mem::size_of::<handshake::SaParams>()
    );
}
