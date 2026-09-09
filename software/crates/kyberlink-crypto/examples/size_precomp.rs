use kyberlink_crypto::mldsa_internal::VerifyPrecomp;

fn main() {
    println!("VerifyPrecomp size = {} bytes ({} KB)", std::mem::size_of::<VerifyPrecomp>(), std::mem::size_of::<VerifyPrecomp>() / 1024);
}
