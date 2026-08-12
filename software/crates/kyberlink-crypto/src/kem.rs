use ml_kem::kem::Seed;
use ml_kem::{Decapsulate, Encapsulate, FromSeed, Kem, KeyExport, MlKem768};

pub type DecapsulationKey = ml_kem::DecapsulationKey<MlKem768>;
pub type EncapsulationKey = ml_kem::EncapsulationKey<MlKem768>;
pub type Ciphertext = ml_kem::Ciphertext<MlKem768>;
pub type SharedSecret = ml_kem::kem::SharedKey<MlKem768>;

pub struct KemKeyPair {
    pub dk: DecapsulationKey,
    pub ek: EncapsulationKey,
}

impl KemKeyPair {
    pub fn generate() -> Self {
        let (dk, ek) = MlKem768::generate_keypair();
        Self { dk, ek }
    }

    pub fn from_seed(seed: &[u8; 64]) -> Self {
        let seed: Seed<MlKem768> = (*seed).into();
        let (dk, ek) = MlKem768::from_seed(&seed);
        Self { dk, ek }
    }

    pub fn seed(&self) -> Option<[u8; 64]> {
        self.dk.to_seed().map(Into::into)
    }
}

pub fn encapsulate(ek: &EncapsulationKey) -> (Ciphertext, SharedSecret) {
    ek.encapsulate()
}

pub fn encapsulate_deterministic(
    ek: &EncapsulationKey,
    m: &[u8; 32],
) -> (Ciphertext, SharedSecret) {
    ek.encapsulate_deterministic(&(*m).into())
}

pub fn decapsulate(dk: &DecapsulationKey, ct: &Ciphertext) -> SharedSecret {
    dk.decapsulate(ct)
}

pub fn encaps_key_bytes(ek: &EncapsulationKey) -> [u8; 1184] {
    ek.to_bytes().as_slice().try_into().unwrap()
}

pub fn encaps_key_from_bytes(b: &[u8; 1184]) -> Result<EncapsulationKey, ml_kem::InvalidKey> {
    EncapsulationKey::new(&(*b).into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip() {
        let kp = KemKeyPair::generate();
        let (ct, ss) = encapsulate(&kp.ek);
        assert_eq!(decapsulate(&kp.dk, &ct).as_slice(), ss.as_slice());
    }

    #[test]
    fn seed_deterministic() {
        let seed = [7u8; 64];
        let a = KemKeyPair::from_seed(&seed);
        let b = KemKeyPair::from_seed(&seed);
        assert_eq!(encaps_key_bytes(&a.ek), encaps_key_bytes(&b.ek));
        let (ct, ss) = encapsulate_deterministic(&a.ek, &[1u8; 32]);
        assert_eq!(decapsulate(&b.dk, &ct).as_slice(), ss.as_slice());
    }

    #[test]
    fn wrong_key_rejects() {
        let a = KemKeyPair::generate();
        let b = KemKeyPair::generate();
        let (ct, ss) = encapsulate(&a.ek);
        assert_ne!(decapsulate(&b.dk, &ct).as_slice(), ss.as_slice());
    }

    #[test]
    fn key_bytes_roundtrip() {
        let kp = KemKeyPair::generate();
        let bytes = encaps_key_bytes(&kp.ek);
        let ek = encaps_key_from_bytes(&bytes).unwrap();
        assert_eq!(encaps_key_bytes(&ek), bytes);
    }
}
