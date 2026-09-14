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

fn hex_arr<const N: usize>(s: &str) -> [u8; N] {
    hex::decode(s).unwrap().try_into().unwrap()
}

fn gen_aes(n: u64, out_dir: &Path) {
    use aes::cipher::generic_array::GenericArray;
    use aes::cipher::{BlockEncrypt, KeyInit};
    let kat_keys: [[u8; 32]; 2] = [
        hex_arr("603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4"),
        hex_arr("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"),
    ];
    let kat_blocks: [[u8; 16]; 2] = [
        hex_arr("6bc1bee22e409f96e93d7e117393172a"),
        hex_arr("00112233445566778899aabbccddeeff"),
    ];
    let mut kat = Vec::new();
    for (key, block) in kat_keys.iter().zip(kat_blocks.iter()) {
        let cipher = aes::Aes256::new_from_slice(key).unwrap();
        let mut gb = *GenericArray::from_slice(block);
        cipher.encrypt_block(&mut gb);
        kat.push(json!({
            "key": hex::encode(key),
            "block": hex::encode(block),
            "ciphertext": hex::encode(gb.as_slice()),
        }));
    }
    let ksch = [
        "000102030405060708090a0b0c0d0e0f",
        "101112131415161718191a1b1c1d1e1f",
        "a573c29fa176c498a97fce93a572c09c",
        "1651a8cd0244beda1a5da4c10640bade",
        "ae87dff00ff11b68a68ed5fb03fc1567",
        "6de1f1486fa54f9275f8eb5373b8518d",
        "c656827fc9a799176f294cec6cd5598b",
        "3de23a75524775e727bf9eb45407cf39",
        "0bdc905fc27b0948ad5245a4c1871c2f",
        "45f5a66017b2d387300d4d33640a820a",
        "7ccff71cbeb4fe5413e6bbf0d261a7df",
        "f01afafee7a82979d7a5644ab3afe640",
        "2541fe719bf500258813bbd55a721c0a",
        "4e5a6699a9f24fe07e572baacdf8cdea",
        "24fc79ccbf0979e9371ac23c6d68de36",
    ];
    let mut random = Vec::new();
    for i in 0..n {
        let mut key = [0u8; 32];
        shake(&mut key, b"aes-key", i);
        let mut block = [0u8; 16];
        shake(&mut block, b"aes-block", i);
        let cipher = aes::Aes256::new_from_slice(&key).unwrap();
        let mut gb = *GenericArray::from_slice(&block);
        cipher.encrypt_block(&mut gb);
        random.push(json!({
            "index": i,
            "key": hex::encode(key),
            "block": hex::encode(block),
            "ciphertext": hex::encode(gb.as_slice()),
        }));
    }
    let obj = json!({"kat": kat, "ksch": ksch, "random": random});
    fs::write(
        out_dir.join("aes.json"),
        serde_json::to_string_pretty(&obj).unwrap(),
    )
    .unwrap();
    println!(
        "aes: {} kat + {} ksch + {} random",
        kat.len(),
        ksch.len(),
        random.len()
    );
}

fn gen_gcm(out_dir: &Path) {
    let key: [u8; 32] = (0u8..32).collect::<Vec<_>>().try_into().unwrap();
    let nonce = [0u8; 12];
    let p7 = |j: usize| ((j * 7 + 3) & 0xFF) as u8;
    let p11 = |j: usize| ((j * 11 + 5) & 0xFF) as u8;
    let pts: Vec<Vec<u8>> = vec![
        vec![],
        (0..16).map(|j| j as u8).collect(),
        (0..32).map(|j| j as u8).collect(),
        (0..16).map(|j| j as u8).collect(),
        (0..16).map(p7).collect(),
        (0..16).map(p7).collect(),
        (0..32).map(p7).collect(),
        (0..48).map(p7).collect(),
    ];
    let aads: Vec<Vec<u8>> = vec![
        vec![],
        vec![],
        vec![],
        (0..8).map(|j| j as u8).collect(),
        (0..8).map(p11).collect(),
        (0..16).map(p11).collect(),
        (0..8).map(p11).collect(),
        (0..16).map(p11).collect(),
    ];
    let c = GcmCipher::new(&key);
    let mut vectors = Vec::new();
    for (pt, aad) in pts.iter().zip(aads.iter()) {
        let mut buffer = pt.clone();
        let mut tag = [0u8; 16];
        c.encrypt_in_place(&nonce, aad, &mut buffer, &mut tag)
            .unwrap();
        vectors.push(json!({
            "pt": hex::encode(pt),
            "ct": hex::encode(&buffer),
            "aad": hex::encode(aad),
            "tag": hex::encode(tag),
        }));
    }
    let obj = json!({"key": hex::encode(key), "vectors": vectors});
    fs::write(
        out_dir.join("gcm.json"),
        serde_json::to_string_pretty(&obj).unwrap(),
    )
    .unwrap();
    println!("gcm: {} vectors", vectors.len());
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
            "blocks": blocks.iter().map(hex::encode).collect::<Vec<_>>(),
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
        c.encrypt_in_place(&nonce, &aad, &mut buffer, &mut tag)
            .unwrap();
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
        c.encrypt_in_place(&iv, &aad, &mut buffer, &mut tag)
            .unwrap();
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

fn gen_handshake(out_dir: &Path) {
    use kyberlink_crypto::handshake as hs;

    struct TestIdentity {
        vk: [u8; hs::VK_LEN],
        kk: [u8; hs::KK_LEN],
        tr: [u8; hs::TR_LEN],
        spc: hs::SignPrecomp,
    }

    impl hs::Identity for TestIdentity {
        fn vk(&self) -> &[u8; hs::VK_LEN] {
            &self.vk
        }
        fn kk(&self) -> &[u8; hs::KK_LEN] {
            &self.kk
        }
        fn tr(&self) -> &[u8; hs::TR_LEN] {
            &self.tr
        }
        fn spc(&self) -> &hs::SignPrecomp {
            &self.spc
        }
    }

    fn mk_identity(seed: [u8; 32]) -> TestIdentity {
        let (vk, sk) = kyberlink_crypto::mldsa_internal::keygen_internal(&seed);
        let mut spc = hs::SignPrecomp::default();
        kyberlink_crypto::mldsa_internal::sign_precomp_new_into(&mut spc, &sk);
        TestIdentity {
            vk,
            kk: hs::kk_of(&sk),
            tr: hs::tr_of(&sk),
            spc,
        }
    }

    let id_i = mk_identity([0x11u8; 32]);
    let id_r = mk_identity([0xa1u8; 32]);

    let (mut st_i, m1) = hs::initiator_start(&id_i, &[0x12u8; 32], &[0x22u8; 32], &[0x55u8; 32]);
    let fp_i = hs::fingerprint(&m1[32 + hs::EK_LEN..32 + hs::EK_LEN + hs::VK_LEN]);
    let (mut st_r, m2) = hs::responder_start(
        &id_r,
        &[0xa2u8; 32],
        &[0xa3u8; 32],
        &[0xa5u8; 32],
        &m1,
        &fp_i,
    )
    .unwrap();
    let fp_r = hs::fingerprint(&m2[32 + hs::EK_LEN..32 + hs::EK_LEN + hs::VK_LEN]);
    let (m3, spi_i) = hs::initiator_recv_m2(&mut st_i, &id_i, &m2, &fp_r, None).unwrap();
    let (m4, sa_r) = hs::responder_recv_m3(&mut st_r, &id_r, &m3, spi_i, None).unwrap();
    let sa_i = hs::initiator_recv_m4(&mut st_i, &m4, spi_i, None).unwrap();
    assert_eq!(sa_i.spi_i, sa_r.spi_i);
    assert_eq!(sa_i.spi_r, sa_r.spi_r);
    assert_eq!(sa_i.sk_ei, sa_r.sk_ei);
    assert_eq!(sa_i.sk_er, sa_r.sk_er);
    assert_eq!(sa_i.sa_salt, sa_r.sa_salt);

    let sa_json = |sa: &hs::SaParams| {
        json!({
            "spi_i": hex::encode(sa.spi_i.to_be_bytes()),
            "spi_r": hex::encode(sa.spi_r.to_be_bytes()),
            "sk_ei": hex::encode(sa.sk_ei),
            "sk_er": hex::encode(sa.sk_er),
            "sa_salt": hex::encode(sa.sa_salt),
        })
    };
    let v = vec![json!({
        "initiator": {
            "tx": [hex::encode(m1), hex::encode(m3)],
            "rx": [hex::encode(m2), hex::encode(m4)],
            "sa": sa_json(&sa_i),
        },
        "responder": {
            "rx": [hex::encode(m1), hex::encode(m3)],
            "tx": [hex::encode(m2), hex::encode(m4)],
            "sa": sa_json(&sa_r),
        },
    })];
    write_vectors(out_dir, "handshake", &v);
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
        "gcm" => gen_gcm(&out_dir),
        "ghash" => gen_ghash(n, &out_dir),
        "cipher" => gen_cipher(n, &out_dir),
        "esp" => gen_esp(n, &out_dir),
        "handshake" => gen_handshake(&out_dir),
        _ => {
            gen_shake(n, &out_dir);
            gen_aes(n, &out_dir);
            gen_gcm(&out_dir);
            gen_ghash(n, &out_dir);
            gen_cipher(n, &out_dir);
            gen_esp(n, &out_dir);
            gen_handshake(&out_dir);
        }
    }
}
