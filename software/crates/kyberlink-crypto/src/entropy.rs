use crate::shake;

pub const SEED_LEN: usize = 32;

#[derive(Clone, Copy)]
pub struct KemSeeds {
    pub d: [u8; SEED_LEN],
    pub z: [u8; SEED_LEN],
    pub nonce: [u8; SEED_LEN],
}

pub fn derive_kem_seeds(raw: &[u8]) -> KemSeeds {
    KemSeeds {
        d: shake::sha3_256_parts(&[raw, b"kyb-kem-d"]),
        z: shake::sha3_256_parts(&[raw, b"kyb-kem-z"]),
        nonce: shake::sha3_256_parts(&[raw, b"kyb-nonce"]),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn derivation_is_deterministic_and_domain_separated() {
        let a = derive_kem_seeds(b"sample entropy");
        let b = derive_kem_seeds(b"sample entropy");
        assert_eq!(a.d, b.d);
        assert_eq!(a.z, b.z);
        assert_eq!(a.nonce, b.nonce);
        assert_ne!(a.d, a.z);
        assert_ne!(a.d, a.nonce);
        assert_ne!(a.z, a.nonce);
    }

    #[test]
    fn distinct_entropy_yields_distinct_seeds() {
        let a = derive_kem_seeds(b"entropy one");
        let b = derive_kem_seeds(b"entropy two");
        assert_ne!(a.d, b.d);
        assert_ne!(a.z, b.z);
        assert_ne!(a.nonce, b.nonce);
    }
}
