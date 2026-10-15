use aes_gcm::aead::Tag;
use aes_gcm::aead::{AeadInPlace, Nonce};
use aes_gcm::{Aes256Gcm, Key, KeyInit};

pub type Error = aes_gcm::Error;

pub struct GcmCipher {
    cipher: Aes256Gcm,
}

impl GcmCipher {
    pub fn new(key: &[u8; 32]) -> Self {
        Self {
            cipher: Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key)),
        }
    }

    pub fn encrypt_in_place(
        &self,
        nonce: &[u8; 12],
        aad: &[u8],
        buffer: &mut [u8],
        tag: &mut [u8; 16],
    ) -> Result<(), Error> {
        let t = self.cipher.encrypt_in_place_detached(
            Nonce::<Aes256Gcm>::from_slice(nonce),
            aad,
            buffer,
        )?;
        tag.copy_from_slice(&t);
        Ok(())
    }

    pub fn decrypt_in_place(
        &self,
        nonce: &[u8; 12],
        aad: &[u8],
        buffer: &mut [u8],
        tag: &[u8; 16],
    ) -> Result<(), Error> {
        self.cipher.decrypt_in_place_detached(
            Nonce::<Aes256Gcm>::from_slice(nonce),
            aad,
            buffer,
            Tag::<Aes256Gcm>::from_slice(tag),
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip() {
        let cipher = GcmCipher::new(&[1u8; 32]);
        let nonce = [2u8; 12];
        let aad = b"esp-header";
        let mut buf = b"attack at dawn".to_vec();
        let mut tag = [0u8; 16];
        cipher
            .encrypt_in_place(&nonce, aad, buf.as_mut_slice(), &mut tag)
            .unwrap();
        assert_ne!(buf.as_slice(), b"attack at dawn");
        cipher
            .decrypt_in_place(&nonce, aad, buf.as_mut_slice(), &tag)
            .unwrap();
        assert_eq!(buf.as_slice(), b"attack at dawn");
    }

    #[test]
    fn wrong_tag_rejects() {
        let cipher = GcmCipher::new(&[1u8; 32]);
        let mut buf = b"data".to_vec();
        let mut tag = [0u8; 16];
        cipher
            .encrypt_in_place(&[2u8; 12], &[], buf.as_mut_slice(), &mut tag)
            .unwrap();
        tag[0] ^= 1;
        assert!(cipher
            .decrypt_in_place(&[2u8; 12], &[], buf.as_mut_slice(), &tag)
            .is_err());
    }

    #[test]
    fn wrong_aad_rejects() {
        let cipher = GcmCipher::new(&[1u8; 32]);
        let mut buf = b"data".to_vec();
        let mut tag = [0u8; 16];
        cipher
            .encrypt_in_place(&[2u8; 12], b"aad", buf.as_mut_slice(), &mut tag)
            .unwrap();
        assert!(cipher
            .decrypt_in_place(&[2u8; 12], b"bad", buf.as_mut_slice(), &tag)
            .is_err());
    }
}
