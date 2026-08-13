use std::env;
use std::path::{Path, PathBuf};

use sha3::digest::{ExtendableOutput, Update, XofReader};
use sha3::Shake256;
use serde_json::json;

use kyberlink_crypto::cipher::GcmCipher;
use kyberlink_crypto::kem;
use kyberlink_crypto::ntt;
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

const Q: u16 = 3329;

fn shake_stream(out: &mut [u8], label: &[u8]) {
    use sha3::digest::{ExtendableOutput, Update, XofReader};
    if out.len() == 840 {
        let mut x = sha3::Shake128::default();
        x.update(label);
        x.finalize_xof().read(out);
    } else {
        let mut x = sha3::Shake256::default();
        x.update(label);
        x.finalize_xof().read(out);
    }
}

fn sample_ntt(seed: &[u8; 34]) -> Vec<u16> {
    let mut stream = vec![0u8; 840];
    shake_stream(&mut stream, seed);
    let mut coeffs = Vec::with_capacity(256);
    let mut pos = 0;
    while coeffs.len() < 256 {
        let b0 = stream[pos] as u16;
        let b1 = stream[pos + 1] as u16;
        let b2 = stream[pos + 2] as u16;
        pos += 3;
        let d1 = b0 + 256 * (b1 % 16);
        let d2 = b1 / 16 + 16 * b2;
        if d1 < Q {
            coeffs.push(d1);
        }
        if d2 < Q && coeffs.len() < 256 {
            coeffs.push(d2);
        }
    }
    coeffs
}

fn sample_cbd(seed: &[u8; 33]) -> Vec<i16> {
    let mut stream = vec![0u8; 128];
    shake_stream(&mut stream, seed);
    let mut coeffs = Vec::with_capacity(256);
    for b in stream.chunks(4) {
        let d = b[0] as u32 | ((b[1] as u32) << 8) | ((b[2] as u32) << 16) | ((b[3] as u32) << 24);
        for k in 0..8 {
            let bits = (d >> (4 * k)) & 0xF;
            let pos = (bits & 0b11).count_ones() as i16;
            let neg = ((bits >> 2) & 0b11).count_ones() as i16;
            coeffs.push(pos - neg);
        }
    }
    coeffs
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

    if mode == "shake" || mode == "all" {
        let mut v256 = Vec::new();
        let mut v128 = Vec::new();
        let mut vlong = Vec::new();
        for i in 0..n {
            let len = (i % 169) as usize;
            let mut msg = vec![0u8; len];
            if len > 0 {
                shake(&mut msg, b"shake-msg", i);
            }
            let mut d = [0u8; 32];
            {
                use sha3::digest::{ExtendableOutput, Update, XofReader};
                let mut x = sha3::Shake256::default();
                x.update(&msg);
                x.finalize_xof().read(&mut d);
            }
            v256.push(json!({
                "index": i,
                "msg": hex::encode(&msg),
                "digest": hex::encode(d),
            }));
            let mut d128 = [0u8; 32];
            {
                use sha3::digest::{ExtendableOutput, Update, XofReader};
                let mut x = sha3::Shake128::default();
                x.update(&msg);
                x.finalize_xof().read(&mut d128);
            }
            if len <= 136 {
                v128.push(json!({
                    "index": i,
                    "msg": hex::encode(&msg),
                    "digest": hex::encode(d128),
                }));
                let mut out256 = vec![0u8; 272];
                let mut out128 = vec![0u8; 336];
                {
                    use sha3::digest::{ExtendableOutput, Update, XofReader};
                    let mut x = sha3::Shake256::default();
                    x.update(&msg);
                    x.finalize_xof().read(&mut out256);
                }
                {
                    use sha3::digest::{ExtendableOutput, Update, XofReader};
                    let mut x = sha3::Shake128::default();
                    x.update(&msg);
                    x.finalize_xof().read(&mut out128);
                }
                vlong.push(json!({
                    "index": i,
                    "msg": hex::encode(&msg),
                    "shake256_272": hex::encode(&out256),
                    "shake128_336": hex::encode(&out128),
                }));
            }
        }
        std::fs::write(out_dir.join("shake.json"), serde_json::to_string_pretty(&v256).unwrap()).unwrap();
        std::fs::write(out_dir.join("shake128.json"), serde_json::to_string_pretty(&v128).unwrap()).unwrap();
        std::fs::write(out_dir.join("shakelong.json"), serde_json::to_string_pretty(&vlong).unwrap()).unwrap();
        println!("shake: {} vectors (256/128/long)", n);
    }

    if mode == "ntt" || mode == "all" {
        let mut v = Vec::new();
        for i in 0..n {
            let mut stream = [0u8; 512];
            shake(&mut stream, b"ntt-in", i);
            let mut f = [0u16; 256];
            for k in 0..256 {
                f[k] = u16::from_le_bytes([stream[2 * k], stream[2 * k + 1]]) % Q;
            }
            let mut g = f;
            ntt::ntt(&mut g);
            v.push(json!({
                "index": i,
                "coeffs_in": f.to_vec(),
                "coeffs_out": g.to_vec(),
            }));
        }
        std::fs::write(out_dir.join("ntt.json"), serde_json::to_string_pretty(&v).unwrap()).unwrap();
        println!("ntt: {} vectors", n);
    }

    if mode == "invntt" || mode == "all" {
        let mut v = Vec::new();
        for i in 0..n {
            let mut stream = [0u8; 512];
            shake(&mut stream, b"invntt-in", i);
            let mut f = [0u16; 256];
            for k in 0..256 {
                f[k] = u16::from_le_bytes([stream[2 * k], stream[2 * k + 1]]) % Q;
            }
            let mut g = f;
            ntt::invntt(&mut g);
            v.push(json!({
                "index": i,
                "coeffs_in": f.to_vec(),
                "coeffs_out": g.to_vec(),
            }));
        }
        std::fs::write(out_dir.join("invntt.json"), serde_json::to_string_pretty(&v).unwrap()).unwrap();
        println!("invntt: {} vectors", n);
    }

    if mode == "basemul" || mode == "all" {
        let mut v = Vec::new();
        for i in 0..n {
            let mut sa = [0u8; 512];
            let mut sb = [0u8; 512];
            shake(&mut sa, b"basemul-a", i);
            shake(&mut sb, b"basemul-b", i);
            let mut a = [0u16; 256];
            let mut b = [0u16; 256];
            for k in 0..256 {
                a[k] = u16::from_le_bytes([sa[2 * k], sa[2 * k + 1]]) % Q;
                b[k] = u16::from_le_bytes([sb[2 * k], sb[2 * k + 1]]) % Q;
            }
            let mut c = [0u16; 256];
            for k in 0..128 {
                let r = ntt::basemul(&[a[2 * k], a[2 * k + 1]], &[b[2 * k], b[2 * k + 1]], ntt::GAMMAS[k]);
                c[2 * k] = r[0];
                c[2 * k + 1] = r[1];
            }
            v.push(json!({
                "index": i,
                "coeffs_a": a.to_vec(),
                "coeffs_b": b.to_vec(),
                "coeffs_out": c.to_vec(),
            }));
        }
        std::fs::write(out_dir.join("basemul.json"), serde_json::to_string_pretty(&v).unwrap()).unwrap();
        println!("basemul: {} vectors", n);
    }

    if mode == "sample" || mode == "all" {
        let mut ntt = Vec::new();
        for i in 0..n {
            let mut seed = [0u8; 34];
            shake(&mut seed[..32], b"sample-rho", i);
            seed[32] = (i % 3) as u8;
            seed[33] = (i / 3 % 3) as u8;
            let coeffs = sample_ntt(&seed);
            ntt.push(json!({
                "index": i,
                "seed": hex::encode(seed),
                "coeffs": coeffs,
            }));
        }
        std::fs::write(out_dir.join("sample_ntt.json"), serde_json::to_string_pretty(&ntt).unwrap()).unwrap();

        let mut cbd = Vec::new();
        for i in 0..n {
            let mut seed = [0u8; 33];
            shake(&mut seed[..32], b"sample-cbd", i);
            seed[32] = (i % 3) as u8;
            let coeffs = sample_cbd(&seed);
            cbd.push(json!({
                "index": i,
                "seed": hex::encode(seed),
                "coeffs": coeffs,
            }));
        }
        std::fs::write(out_dir.join("sample_cbd.json"), serde_json::to_string_pretty(&cbd).unwrap()).unwrap();
        println!("sample: {} ntt + {} cbd vectors", n, n);
    }

    if mode == "aes" || mode == "all" {
        use aes::cipher::generic_array::GenericArray;
        use aes::cipher::{BlockEncrypt, KeyInit};
        let mut v = Vec::new();
        for i in 0..n {
            let mut key = [0u8; 32];
            shake(&mut key, b"aes-key", i);
            let mut block = [0u8; 16];
            shake(&mut block, b"aes-block", i);
            let cipher = aes::Aes256::new_from_slice(&key).unwrap();
            let mut gb = GenericArray::from_slice(&block).clone();
            cipher.encrypt_block(&mut gb);
            v.push(json!({
                "index": i,
                "key": hex::encode(key),
                "block": hex::encode(block),
                "ciphertext": hex::encode(gb.as_slice()),
            }));
        }
        std::fs::write(out_dir.join("aes.json"), serde_json::to_string_pretty(&v).unwrap()).unwrap();
        println!("aes: {} vectors", n);
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
