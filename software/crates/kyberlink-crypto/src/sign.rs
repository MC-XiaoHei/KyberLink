use ml_dsa::signature::{Keypair, SignatureEncoding, Signer, Verifier};
use ml_dsa::{KeyExport, MlDsa65, SigningKey, VerifyingKey};

pub type Signature = ml_dsa::Signature<MlDsa65>;
pub type VerificationError = ml_dsa::Error;

pub struct SignKeyPair {
    pub sk: SigningKey<MlDsa65>,
    pub vk: VerifyingKey<MlDsa65>,
}

impl SignKeyPair {
    pub fn from_seed(seed: &[u8; 32]) -> Self {
        let sk = SigningKey::<MlDsa65>::from_seed(&(*seed).into());
        let vk = sk.verifying_key();
        Self { sk, vk }
    }

    pub fn seed(&self) -> [u8; 32] {
        self.sk.to_seed().into()
    }
}

pub fn sign(sk: &SigningKey<MlDsa65>, msg: &[u8]) -> Signature {
    sk.sign(msg)
}

pub fn verify(
    vk: &VerifyingKey<MlDsa65>,
    msg: &[u8],
    sig: &Signature,
) -> Result<(), VerificationError> {
    vk.verify(msg, sig)
}

pub fn sig_bytes(sig: &Signature) -> [u8; 3309] {
    sig.to_bytes().into()
}

pub fn sig_from_bytes(b: &[u8; 3309]) -> Result<Signature, VerificationError> {
    Signature::decode(&(*b).into()).ok_or_else(ml_dsa::Error::new)
}

pub fn vk_bytes(vk: &VerifyingKey<MlDsa65>) -> [u8; 1952] {
    vk.to_bytes().as_slice().try_into().unwrap()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip() {
        let kp = SignKeyPair::from_seed(&[1u8; 32]);
        let msg = b"hello kyberlink";
        let sig = sign(&kp.sk, msg);
        assert!(verify(&kp.vk, msg, &sig).is_ok());
    }

    #[test]
    fn seed_deterministic() {
        let seed = [9u8; 32];
        let a = SignKeyPair::from_seed(&seed);
        let b = SignKeyPair::from_seed(&seed);
        assert_eq!(vk_bytes(&a.vk), vk_bytes(&b.vk));
        assert_eq!(a.seed(), b.seed());
    }

    #[test]
    fn wrong_sig_rejects() {
        let kp = SignKeyPair::from_seed(&[1u8; 32]);
        let msg = b"attack at dawn";
        let mut sig = sig_bytes(&sign(&kp.sk, msg));
        sig[0] ^= 1;
        let sig = sig_from_bytes(&sig).unwrap();
        assert!(verify(&kp.vk, msg, &sig).is_err());
    }

    #[test]
    fn sig_bytes_roundtrip() {
        let kp = SignKeyPair::from_seed(&[1u8; 32]);
        let sig = sign(&kp.sk, b"x");
        assert_eq!(sig_from_bytes(&sig_bytes(&sig)).unwrap(), sig);
    }
}
