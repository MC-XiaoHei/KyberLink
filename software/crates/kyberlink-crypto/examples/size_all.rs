fn main() {
    println!("VerifyPrecomp = {} bytes", std::mem::size_of::<kyberlink_crypto::mldsa_internal::VerifyPrecomp>());
    println!("InitiatorState = {} bytes", std::mem::size_of::<kyberlink_crypto::handshake::InitiatorState>());
}
