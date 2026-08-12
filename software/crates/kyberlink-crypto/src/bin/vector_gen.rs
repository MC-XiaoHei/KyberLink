use std::env;
use std::path::{Path, PathBuf};

use sha3::digest::{ExtendableOutput, Update, XofReader};
use sha3::Shake256;
use serde_json::json;

use kyberlink_crypto::cipher::GcmCipher;
use kyberlink_crypto::kem;
use kyberlink_crypto::sign;

const BASE: &[u8] = b"KyberLink vector generator v1";

fn shake(out: &mut [u8], label: &[u8], i: u64) {
    let mut x = Shake256::default();
    x.update(BASE);
    x.update(label);
    x.update(&i.to_le_bytes());
    x.finalize_xof().read(out);
}

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .ancestors()
        .nth(3)
        .unwrap()
        .to_path_buf()
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let mode = args.get(1).map(String::as_str).unwrap_or("all");
    let n: u64 = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(32);
    let out_dir = repo_root().join("vectors/generated");
    std::fs::create_dir_all(&out_dir).unwrap();

    if mode == "kem" || mode == "all" {
        let mut v = Vec::new();
        for i in 0..n {
            let mut seed = [0u8; 64];
            shake(&mut seed, b"kem-seed", i);
            let mut m = [0u8; 32];
            shake(&mut m, b"kem-m", i);
            let kp = kem::KemKeyPair::from_seed(&seed);
            let (ct, ss) = kem::encapsulate_deterministic(&kp.ek, &m);
            v.push(json!({
                "index": i,
                "seed": hex::encode(seed),
                "pk": hex::encode(kem::encaps_key_bytes(&kp.ek)),
                "ct": hex::encode(ct.as_slice()),
                "ss": hex::encode(ss.as_slice()),
            }));
        }
        std::fs::write(out_dir.join("kem.json"), serde_json::to_string_pretty(&v).unwrap()).unwrap();
        println!("kem: {} vectors", n);
    }

    if mode == "sign" || mode == "all" {
        let mut v = Vec::new();
        for i in 0..n {
            let mut seed = [0u8; 32];
            shake(&mut seed, b"sign-seed", i);
            let mut msg = [0u8; 64];
            shake(&mut msg, b"sign-msg", i);
            let kp = sign::SignKeyPair::from_seed(&seed);
            let sig = sign::sign(&kp.sk, &msg);
            v.push(json!({
                "index": i,
                "seed": hex::encode(seed),
                "pk": hex::encode(sign::vk_bytes(&kp.vk)),
                "msg": hex::encode(msg),
                "sig": hex::encode(sign::sig_bytes(&sig)),
            }));
        }
        std::fs::write(out_dir.join("sign.json"), serde_json::to_string_pretty(&v).unwrap()).unwrap();
        println!("sign: {} vectors", n);
    }

    if mode == "cipher" || mode == "all" {
        let mut v = Vec::new();
        for i in 0..n {
            let mut key = [0u8; 32];
            shake(&mut key, b"cipher-key", i);
            let mut nonce = [0u8; 12];
            shake(&mut nonce, b"cipher-nonce", i);
            let mut aad = vec![0u8; 16];
            shake(&mut aad, b"cipher-aad", i);
            let mut pt = vec![0u8; 128];
            shake(&mut pt, b"cipher-pt", i);
            let mut buffer = pt.clone();
            let mut tag = [0u8; 16];
            let c = GcmCipher::new(&key);
            c.encrypt_in_place(&nonce, &aad, &mut buffer, &mut tag).unwrap();
            v.push(json!({
                "index": i,
                "key": hex::encode(key),
                "nonce": hex::encode(nonce),
                "aad": hex::encode(aad),
                "plaintext": hex::encode(pt),
                "ciphertext_tag": hex::encode([buffer.as_slice(), &tag].concat()),
            }));
        }
        std::fs::write(out_dir.join("cipher.json"), serde_json::to_string_pretty(&v).unwrap()).unwrap();
        println!("cipher: {} vectors", n);
    }
}
