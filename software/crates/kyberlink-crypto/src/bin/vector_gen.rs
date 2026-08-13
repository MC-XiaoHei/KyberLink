use std::env;
use std::fs;
use std::path::{Path, PathBuf};

use serde_json::{json, Value};
use sha3::digest::{ExtendableOutput, Update, XofReader};
use sha3::{Shake128, Shake256};

use kyberlink_crypto::cipher::GcmCipher;
use kyberlink_crypto::kem;
use kyberlink_crypto::ntt;
use kyberlink_crypto::sign;

const BASE: &[u8] = b"KyberLink vector generator v1";
const Q: u16 = 3329;

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

fn sample_ntt(seed: &[u8; 34]) -> Vec<u16> {
    let mut stream = vec![0u8; 840];
    shake128_stream(&mut stream, seed);
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
    shake256_stream(&mut stream, seed);
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

fn coeffs256(label: &[u8], i: u64) -> [u16; 256] {
    let mut stream = [0u8; 512];
    shake(&mut stream, label, i);
    let mut f = [0u16; 256];
    for k in 0..256 {
        f[k] = u16::from_le_bytes([stream[2 * k], stream[2 * k + 1]]) % Q;
    }
    f
}

fn write_vectors(out_dir: &Path, name: &str, v: &[Value]) {
    let path = out_dir.join(format!("{}.json", name));
    fs::write(path, serde_json::to_string_pretty(v).unwrap()).unwrap();
    println!("{}: {} vectors", name, v.len());
}

fn gen_kem(n: u64, out_dir: &Path) {
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
    write_vectors(out_dir, "kem", &v);
}

fn gen_sign(n: u64, out_dir: &Path) {
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
    write_vectors(out_dir, "sign", &v);
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

fn gen_ntt(n: u64, out_dir: &Path) {
    let mut v = Vec::new();
    for i in 0..n {
        let f = coeffs256(b"ntt-in", i);
        let mut g = f;
        ntt::ntt(&mut g);
        v.push(json!({
            "index": i,
            "coeffs_in": f.to_vec(),
            "coeffs_out": g.to_vec(),
        }));
    }
    write_vectors(out_dir, "ntt", &v);
}

fn gen_invntt(n: u64, out_dir: &Path) {
    let mut v = Vec::new();
    for i in 0..n {
        let f = coeffs256(b"invntt-in", i);
        let mut g = f;
        ntt::invntt(&mut g);
        v.push(json!({
            "index": i,
            "coeffs_in": f.to_vec(),
            "coeffs_out": g.to_vec(),
        }));
    }
    write_vectors(out_dir, "invntt", &v);
}

fn gen_basemul(n: u64, out_dir: &Path) {
    let mut v = Vec::new();
    for i in 0..n {
        let a = coeffs256(b"basemul-a", i);
        let b = coeffs256(b"basemul-b", i);
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
    write_vectors(out_dir, "basemul", &v);
}

fn gen_sample(n: u64, out_dir: &Path) {
    let mut ntt_v = Vec::new();
    for i in 0..n {
        let mut seed = [0u8; 34];
        shake(&mut seed[..32], b"sample-rho", i);
        seed[32] = (i % 3) as u8;
        seed[33] = (i / 3 % 3) as u8;
        ntt_v.push(json!({
            "index": i,
            "seed": hex::encode(seed),
            "coeffs": sample_ntt(&seed),
        }));
    }
    write_vectors(out_dir, "sample_ntt", &ntt_v);

    let mut cbd_v = Vec::new();
    for i in 0..n {
        let mut seed = [0u8; 33];
        shake(&mut seed[..32], b"sample-cbd", i);
        seed[32] = (i % 3) as u8;
        cbd_v.push(json!({
            "index": i,
            "seed": hex::encode(seed),
            "coeffs": sample_cbd(&seed),
        }));
    }
    write_vectors(out_dir, "sample_cbd", &cbd_v);
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

fn gen_sha3(n: u64, out_dir: &Path) {
    use sha3::{Digest, Sha3_256, Sha3_512};
    let mut v256 = Vec::new();
    let mut v512 = Vec::new();
    for i in 0..n {
        let mut msg = [0u8; 1184];
        shake(&mut msg, b"sha3-msg", i);
        let l256 = [0usize, 1, 32, 33, 64, 135, 136, 137, 255, 512, 1184][(i as usize) % 11];
        let h = Sha3_256::digest(&msg[..l256]);
        v256.push(json!({
            "index": i,
            "msg_len": l256,
            "msg": hex::encode(&msg[..l256]),
            "hash": hex::encode(h),
        }));
        let l512 = [0usize, 1, 32, 33, 63, 64, 71, 72, 73, 136][(i as usize) % 10];
        let h = Sha3_512::digest(&msg[..l512]);
        v512.push(json!({
            "index": i,
            "msg_len": l512,
            "msg": hex::encode(&msg[..l512]),
            "hash": hex::encode(h),
        }));
    }
    write_vectors(out_dir, "sha3_256", &v256);
    write_vectors(out_dir, "sha3_512", &v512);
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let mode = args.get(1).map(String::as_str).unwrap_or("all");
    let n: u64 = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(32);
    let out_dir = repo_root().join("vectors/generated");
    fs::create_dir_all(&out_dir).unwrap();

    match mode {
        "kem" => gen_kem(n, &out_dir),
        "sign" => gen_sign(n, &out_dir),
        "shake" => gen_shake(n, &out_dir),
        "ntt" => gen_ntt(n, &out_dir),
        "invntt" => gen_invntt(n, &out_dir),
        "basemul" => gen_basemul(n, &out_dir),
        "sample" => gen_sample(n, &out_dir),
        "aes" => gen_aes(n, &out_dir),
        "ghash" => gen_ghash(n, &out_dir),
        "cipher" => gen_cipher(n, &out_dir),
        "esp" => gen_esp(n, &out_dir),
        "sha3" => gen_sha3(n, &out_dir),
        _ => {
            gen_kem(n, &out_dir);
            gen_sign(n, &out_dir);
            gen_shake(n, &out_dir);
            gen_ntt(n, &out_dir);
            gen_invntt(n, &out_dir);
            gen_basemul(n, &out_dir);
            gen_sample(n, &out_dir);
            gen_aes(n, &out_dir);
            gen_ghash(n, &out_dir);
            gen_cipher(n, &out_dir);
            gen_esp(n, &out_dir);
            gen_sha3(n, &out_dir);
        }
    }
}
