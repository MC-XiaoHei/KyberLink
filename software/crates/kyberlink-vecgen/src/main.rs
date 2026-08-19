use std::env;
use std::fs;
use std::path::{Path, PathBuf};

use serde_json::{json, Value};
use sha3::digest::{ExtendableOutput, Update, XofReader};
use sha3::{Shake128, Shake256};

mod cipher;
use cipher::GcmCipher;

const BASE: &[u8] = b"KyberLink vector generator v1";




fn shake(out: &mut [u8], label: &[u8], i: u64) {
    let mut x = Shake256::default();
    x.update(BASE);
    x.update(label);
    x.update(&i.to_le_bytes());
    x.finalize_xof().read(out);
}

fn shake128_stream(out: &mut [u8], seed: &[u8]) {
    let mut x = Shake128::default();
    x.update(seed);
    x.finalize_xof().read(out);
}

fn shake256_stream(out: &mut [u8], seed: &[u8]) {
    let mut x = Shake256::default();
    x.update(seed);
    x.finalize_xof().read(out);
}

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .ancestors()
        .nth(3)
        .unwrap()
        .to_path_buf()
}










fn write_vectors(out_dir: &Path, name: &str, v: &[Value]) {
    let path = out_dir.join(format!("{}.json", name));
    fs::write(path, serde_json::to_string_pretty(v).unwrap()).unwrap();
    println!("{}: {} vectors", name, v.len());
}

fn gen_shake(n: u64, out_dir: &Path) {
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
        shake256_stream(&mut d, &msg);
        v256.push(json!({
            "index": i,
            "msg": hex::encode(&msg),
            "digest": hex::encode(d),
        }));
        let mut d128 = [0u8; 32];
        shake128_stream(&mut d128, &msg);
        if len <= 136 {
            v128.push(json!({
                "index": i,
                "msg": hex::encode(&msg),
                "digest": hex::encode(d128),
            }));
            let mut out256 = vec![0u8; 272];
            let mut out128 = vec![0u8; 336];
            shake256_stream(&mut out256, &msg);
            shake128_stream(&mut out128, &msg);
            vlong.push(json!({
                "index": i,
                "msg": hex::encode(&msg),
                "shake256_272": hex::encode(&out256),
                "shake128_336": hex::encode(&out128),
            }));
        }
    }
    write_vectors(out_dir, "shake", &v256);
    write_vectors(out_dir, "shake128", &v128);
    write_vectors(out_dir, "shakelong", &vlong);
}

fn gen_aes(n: u64, out_dir: &Path) {
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
    write_vectors(out_dir, "aes", &v);
}

fn gen_ghash(n: u64, out_dir: &Path) {
    use ghash::universal_hash::{KeyInit, UniversalHash};
    let mut v = Vec::new();
    for i in 0..n {
        let mut h = [0u8; 16];
        shake(&mut h, b"ghash-h", i);
        let nb = (i % 8 + 1) as usize;
        let mut blocks = Vec::new();
        let mut g = ghash::GHash::new_from_slice(&h).unwrap();
        for k in 0..nb {
            let mut blk = [0u8; 16];
            shake(&mut blk, b"ghash-b", i * 16 + k as u64);
            blocks.push(blk);
            g.update_padded(&blk);
        }
        let tag = g.finalize();
        v.push(json!({
            "index": i,
            "h": hex::encode(h),
            "blocks": blocks.iter().map(|b| hex::encode(b)).collect::<Vec<_>>(),
            "tag": hex::encode(tag.as_slice()),
        }));
    }
    write_vectors(out_dir, "ghash", &v);
}

fn gen_cipher(n: u64, out_dir: &Path) {
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
    write_vectors(out_dir, "cipher", &v);
}

fn gen_esp(n: u64, out_dir: &Path) {
    let mut v = Vec::new();
    for i in 0..n {
        let mut key = [0u8; 32];
        shake(&mut key, b"esp-key", i);
        let mut spi = [0u8; 4];
        shake(&mut spi, b"esp-spi", i);
        let mut seq = [0u8; 4];
        shake(&mut seq, b"esp-seq", i);
        let mut iv = [0u8; 12];
        shake(&mut iv, b"esp-iv", i);
        let boundary = [0usize, 1, 15, 16, 17, 127, 128, 255];
        let pt_len = if (i as usize) < boundary.len() {
            boundary[i as usize]
        } else {
            ((i as usize) % 253) + 1
        };
        let mut pt = vec![0u8; pt_len];
        shake(&mut pt, b"esp-pt", i);
        let mut buffer = pt.clone();
        let mut tag = [0u8; 16];
        let aad = [spi, seq].concat();
        let c = GcmCipher::new(&key);
        c.encrypt_in_place(&iv, &aad, &mut buffer, &mut tag).unwrap();
        let mut frame = Vec::with_capacity(38 + pt_len);
        frame.extend_from_slice(&spi);
        frame.extend_from_slice(&seq);
        frame.extend_from_slice(&iv);
        frame.extend_from_slice(&buffer);
        frame.extend_from_slice(&[0x00, 0x04]);
        frame.extend_from_slice(&tag);
        v.push(json!({
            "index": i,
            "key": hex::encode(key),
            "spi": hex::encode(spi),
            "seq": hex::encode(seq),
            "iv": hex::encode(iv),
            "plaintext": hex::encode(pt),
            "plaintext_len": pt_len,
            "frame": hex::encode(frame),
        }));
    }
    write_vectors(out_dir, "esp", &v);
}


fn main() {
    let args: Vec<String> = env::args().collect();
    let mode = args.get(1).map(String::as_str).unwrap_or("all");
    let n: u64 = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(32);
    let out_dir = repo_root().join("vectors/generated");
    fs::create_dir_all(&out_dir).unwrap();

    match mode {
        "shake" => gen_shake(n, &out_dir),
        "aes" => gen_aes(n, &out_dir),
        "ghash" => gen_ghash(n, &out_dir),
        "cipher" => gen_cipher(n, &out_dir),
        "esp" => gen_esp(n, &out_dir),
        _ => {
            gen_shake(n, &out_dir);
            gen_aes(n, &out_dir);
            gen_ghash(n, &out_dir);
            gen_cipher(n, &out_dir);
            gen_esp(n, &out_dir);
        }
    }
}
