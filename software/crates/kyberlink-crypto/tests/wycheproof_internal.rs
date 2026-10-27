use std::path::{Path, PathBuf};

use serde_json::Value;

use kyberlink_crypto::kem_internal as ki;

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .ancestors()
        .nth(3)
        .unwrap()
        .to_path_buf()
}

fn load_json(subdir: &str, file: &str) -> Value {
    let p = repo_root().join("vectors").join(subdir).join(file);
    serde_json::from_str(&std::fs::read_to_string(&p).expect("vector file")).unwrap()
}

fn hex_arr<const N: usize>(v: &Value) -> [u8; N] {
    hex::decode(v.as_str().unwrap())
        .unwrap()
        .try_into()
        .unwrap()
}

#[test]
fn mlkem_keygen_internal() {
    let mut kem = ki::KemScratch::new();
    let j = load_json("wycheproof", "mlkem_768_keygen_seed_test.json");
    for g in j["testGroups"].as_array().unwrap() {
        for t in g["tests"].as_array().unwrap() {
            let valid = t["result"].as_str() == Some("valid");
            let seed_ok = t["seed"].as_str().map(|s| s.len() == 128).unwrap_or(false);
            let ek_ok = t["ek"]
                .as_str()
                .map(|s| s.len() == 2 * ki::EK_LEN)
                .unwrap_or(false);
            let dk_ok = t["dk"]
                .as_str()
                .map(|s| s.len() == 2 * ki::DK_LEN)
                .unwrap_or(false);
            if !seed_ok || !ek_ok || !dk_ok {
                assert!(!valid, "tcId={}", t["tcId"]);
                continue;
            }
            let seed = hex_arr::<64>(&t["seed"]);
            let mut d = [0u8; 32];
            let mut z = [0u8; 32];
            d.copy_from_slice(&seed[..32]);
            z.copy_from_slice(&seed[32..]);
            let mut ek = [0u8; ki::EK_LEN];
            let mut dk = [0u8; ki::DK_LEN];
            ki::keygen_internal(&d, &z, &mut kem, &mut ek, &mut dk);
            let ek_e = hex::decode(t["ek"].as_str().unwrap()).unwrap();
            let dk_e = hex::decode(t["dk"].as_str().unwrap()).unwrap();
            if valid {
                assert_eq!(ek.as_slice(), ek_e.as_slice(), "tcId={}", t["tcId"]);
                assert_eq!(dk.as_slice(), dk_e.as_slice(), "tcId={}", t["tcId"]);
            } else {
                assert_ne!(ek.as_slice(), ek_e.as_slice(), "tcId={}", t["tcId"]);
            }
        }
    }
}

#[test]
fn mlkem_encaps_internal() {
    let mut kem = ki::KemScratch::new();
    let j = load_json("wycheproof", "mlkem_768_encaps_test.json");
    for g in j["testGroups"].as_array().unwrap() {
        for t in g["tests"].as_array().unwrap() {
            let valid = t["result"].as_str() == Some("valid");
            let m_ok = t["m"].as_str().map(|s| s.len() == 64).unwrap_or(false);
            let ek_ok = t["ek"]
                .as_str()
                .map(|s| s.len() == 2 * ki::EK_LEN)
                .unwrap_or(false);
            let c_ok = t["c"]
                .as_str()
                .map(|s| s.len() == 2 * ki::CT_LEN)
                .unwrap_or(false);
            let k_ok = t["K"].as_str().map(|s| s.len() == 64).unwrap_or(false);
            if !m_ok || !ek_ok || !c_ok || !k_ok {
                assert!(!valid, "tcId={}", t["tcId"]);
                continue;
            }
            let ek: [u8; ki::EK_LEN] = hex::decode(t["ek"].as_str().unwrap())
                .unwrap()
                .try_into()
                .unwrap();
            let m = hex_arr::<32>(&t["m"]);
            let mut k = [0u8; 32];
            let mut c = [0u8; ki::CT_LEN];
            ki::encaps_internal(&ek, &m, &mut kem, &mut k, &mut c);
            let c_e = hex::decode(t["c"].as_str().unwrap()).unwrap();
            let k_e = hex_arr::<32>(&t["K"]);
            if valid {
                assert_eq!(k.as_slice(), &k_e, "tcId={}", t["tcId"]);
                assert_eq!(c.as_slice(), c_e.as_slice(), "tcId={}", t["tcId"]);
            } else {
                assert_ne!(k.as_slice(), &k_e, "tcId={}", t["tcId"]);
            }
        }
    }
}

#[test]
fn mlkem_decaps_internal() {
    let mut kem = ki::KemScratch::new();
    let j = load_json("wycheproof", "mlkem_768_test.json");
    for g in j["testGroups"].as_array().unwrap() {
        for t in g["tests"].as_array().unwrap() {
            let valid = t["result"].as_str() == Some("valid");
            let seed_ok = t["seed"].as_str().map(|s| s.len() == 128).unwrap_or(false);
            let k_ok = t["K"].as_str().map(|s| s.len() == 64).unwrap_or(false);
            let c = hex::decode(t["c"].as_str().unwrap()).unwrap();
            if !seed_ok || !k_ok || c.len() != ki::CT_LEN {
                assert!(!valid, "tcId={}", t["tcId"]);
                continue;
            }
            let seed = hex_arr::<64>(&t["seed"]);
            let mut d = [0u8; 32];
            let mut z = [0u8; 32];
            d.copy_from_slice(&seed[..32]);
            z.copy_from_slice(&seed[32..]);
            let mut ek = [0u8; ki::EK_LEN];
            let mut dk = [0u8; ki::DK_LEN];
            ki::keygen_internal(&d, &z, &mut kem, &mut ek, &mut dk);
            let got = ki::decaps_internal(&dk, &c, &mut kem);
            let expect = hex_arr::<32>(&t["K"]);
            if valid {
                assert_eq!(got.as_slice(), &expect, "tcId={}", t["tcId"]);
            } else {
                assert_ne!(got.as_slice(), &expect, "tcId={}", t["tcId"]);
            }
        }
    }
}
