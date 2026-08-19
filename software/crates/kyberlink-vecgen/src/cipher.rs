use alloc::vec;
use alloc::vec::Vec;
use aes_gcm::aead::{AeadInPlace, Nonce, Tag};
use aes_gcm::{Aes256Gcm, Key, KeyInit};
use sha3::{Digest, Sha3_256};

pub type Error = aes_gcm::Error;

const HMAC_BLOCK: usize = 136;

fn hmac_sha3_256(key: &[u8], data: &[u8]) -> [u8; 32] {
    let mut k = [0u8; HMAC_BLOCK];
    if key.len() > HMAC_BLOCK {
        k[..32].copy_from_slice(&Sha3_256::digest(key));
    } else {
        k[..key.len()].copy_from_slice(key);
    }
    let mut ipad = [0x36u8; HMAC_BLOCK];
    let mut opad = [0x5cu8; HMAC_BLOCK];
    for i in 0..HMAC_BLOCK {
        ipad[i] ^= k[i];
        opad[i] ^= k[i];
    }
    let mut inner = Sha3_256::new();
    inner.update(&ipad);
    inner.update(data);
    let inner_digest = inner.finalize();
    let mut outer = Sha3_256::new();
    outer.update(&opad);
    outer.update(inner_digest);
    outer.finalize().into()
}

pub fn hkdf_sha3_256_extract(salt: &[u8], ikm: &[u8]) -> [u8; 32] {
    hmac_sha3_256(salt, ikm)
}

pub fn hkdf_sha3_256_expand(prk: &[u8], info: &[u8], okm_len: usize) -> Vec<u8> {
    assert!(okm_len <= 255 * 32);
    let mut okm = Vec::with_capacity(okm_len);
    let mut t: Vec<u8> = Vec::new();
    let mut counter: u8 = 1;
    while okm.len() < okm_len {
        let mut msg = Vec::with_capacity(t.len() + info.len() + 1);
        msg.extend_from_slice(&t);
        msg.extend_from_slice(info);
        msg.push(counter);
        t = hmac_sha3_256(prk, &msg).to_vec();
        let need = core::cmp::min(okm_len - okm.len(), t.len());
        okm.extend_from_slice(&t[..need]);
        counter += 1;
    }
    okm
}

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
        buffer: &mut Vec<u8>,
        tag: &mut [u8; 16],
    ) -> Result<(), Error> {
        let t = self
            .cipher
            .encrypt_in_place_detached(Nonce::<Aes256Gcm>::from_slice(nonce), aad, buffer)?;
        tag.copy_from_slice(&t);
        Ok(())
    }

    pub fn decrypt_in_place(
        &self,
        nonce: &[u8; 12],
        aad: &[u8],
        buffer: &mut Vec<u8>,
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
        cipher.encrypt_in_place(&nonce, aad, &mut buf, &mut tag).unwrap();
        assert_ne!(&buf, b"attack at dawn");
        cipher.decrypt_in_place(&nonce, aad, &mut buf, &tag).unwrap();
        assert_eq!(&buf, b"attack at dawn");
    }

    #[test]
    fn wrong_tag_rejects() {
        let cipher = GcmCipher::new(&[1u8; 32]);
        let mut buf = b"data".to_vec();
        let mut tag = [0u8; 16];
        cipher.encrypt_in_place(&[2u8; 12], &[], &mut buf, &mut tag).unwrap();
        tag[0] ^= 1;
        assert!(cipher.decrypt_in_place(&[2u8; 12], &[], &mut buf, &tag).is_err());
    }

    #[test]
    fn wrong_aad_rejects() {
        let cipher = GcmCipher::new(&[1u8; 32]);
        let mut buf = b"data".to_vec();
        let mut tag = [0u8; 16];
        cipher.encrypt_in_place(&[2u8; 12], b"aad", &mut buf, &mut tag).unwrap();
        assert!(cipher.decrypt_in_place(&[2u8; 12], b"bad", &mut buf, &tag).is_err());
    }

    #[test]
    fn hmac_sha3_256_kat() {
        let key = (1u8..=32).collect::<Vec<_>>();
        assert_eq!(
            hmac_sha3_256(&key, b"attack at dawn"),
            [
                0x5a, 0xc7, 0x03, 0x80, 0xad, 0x1c, 0x10, 0x9a, 0xbb, 0xef, 0xd8, 0x4d, 0x59,
                0x3c, 0x6a, 0x0a, 0x40, 0x36, 0xeb, 0xf6, 0x37, 0xee, 0xca, 0xed, 0x3a, 0x70,
                0x57, 0x94, 0x81, 0xe3, 0x07, 0x27
            ]
        );
    }

    #[test]
    fn hkdf_sha3_256_handshake() {
        let h4 = (32u8..64).collect::<Vec<_>>();
        let ss_i = (64u8..96).collect::<Vec<_>>();
        let ss_r = (96u8..128).collect::<Vec<_>>();
        let mut ikm = Vec::with_capacity(64);
        ikm.extend_from_slice(&ss_i);
        ikm.extend_from_slice(&ss_r);
        let prk = hkdf_sha3_256_extract(&h4, &ikm);
        assert_eq!(
            prk,
            [
                0x53, 0x9f, 0xc7, 0x43, 0x83, 0x00, 0x8f, 0x43, 0xb5, 0x49, 0x7a, 0xf1, 0xf0,
                0xb5, 0xeb, 0xda, 0xde, 0xf3, 0xf2, 0x0b, 0x85, 0x9b, 0xd3, 0x19, 0x3d, 0xf6,
                0x76, 0x24, 0xf4, 0x8a, 0x8e, 0xbc
            ]
        );
        let mut info = Vec::new();
        info.extend_from_slice(b"KyberLink-v1-SA");
        info.extend_from_slice(&0x11223344u32.to_be_bytes());
        info.extend_from_slice(&0xaabbccddu32.to_be_bytes());
        let okm = hkdf_sha3_256_expand(&prk, &info, 96);
        assert_eq!(
            &okm[..],
            &[
                0x6c, 0x50, 0x78, 0xc2, 0x39, 0x65, 0xc6, 0x6b, 0xd1, 0xcf, 0x13, 0xda, 0xdb,
                0xab, 0xd5, 0xda, 0x19, 0x92, 0x32, 0x61, 0x1b, 0xf9, 0x4f, 0x1a, 0x89, 0x20,
                0x1c, 0xfc, 0x64, 0x8e, 0x44, 0xad, 0x90, 0x45, 0xdc, 0x93, 0x2b, 0x0c, 0xb3,
                0xac, 0xfe, 0xbd, 0xc6, 0x9d, 0x5a, 0xcc, 0xd0, 0xfc, 0x4e, 0xc9, 0x72, 0xcb,
                0x5e, 0x42, 0x48, 0x5c, 0xbf, 0x6e, 0x01, 0x86, 0x02, 0xc8, 0xe8, 0xc2, 0x8e,
                0xde, 0xaa, 0x04, 0xf1, 0xbe, 0xff, 0x43, 0xe6, 0xaa, 0x54, 0x98, 0xcd, 0xef,
                0x14, 0xd1, 0x93, 0x0a, 0x82, 0xda, 0xd4, 0xba, 0x28, 0x51, 0x1d, 0x85, 0x19,
                0xfb, 0x26, 0x6d, 0xb4, 0x5d
            ]
        );
    }
}
