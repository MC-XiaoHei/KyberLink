use sha3::digest::{ExtendableOutput, Update, XofReader};
use sha3::{Digest, Shake128, Shake256, Sha3_256, Sha3_512};

pub fn sha3_256(data: &[u8]) -> [u8; 32] {
    Sha3_256::digest(data).into()
}

pub fn sha3_512(data: &[u8]) -> [u8; 64] {
    Sha3_512::digest(data).into()
}

pub fn shake128_squeeze(parts: &[&[u8]], out: &mut [u8]) {
    let mut s = Shake128::default();
    for p in parts {
        s.update(p);
    }
    s.finalize_xof().read(out);
}

pub fn shake256_squeeze(parts: &[&[u8]], out: &mut [u8]) {
    let mut s = Shake256::default();
    for p in parts {
        s.update(p);
    }
    s.finalize_xof().read(out);
}
