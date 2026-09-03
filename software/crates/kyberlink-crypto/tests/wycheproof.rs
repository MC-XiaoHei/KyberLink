use std::path::{Path, PathBuf};

use ml_dsa::signature::Verifier;
use ml_dsa::{MlDsa65, Signature, VerifyingKey};
use ml_kem::{DecapsulationKey, MlKem768};
use serde_json::Value;

use kyberlink_crypto::kem as k;

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
fn mlkem_decaps_negative() {
    let j = load_json("wycheproof", "mlkem_768_test.json");
    for g in j["testGroups"].as_array().unwrap() {
        for t in g["tests"].as_array().unwrap() {
            let valid = t["result"].as_str() == Some("valid");
            let seed_ok = t["seed"].as_str().map(|s| s.len() == 128).unwrap_or(false);
            let k_ok = t["K"].as_str().map(|s| s.len() == 64).unwrap_or(false);
            let c = hex::decode(t["c"].as_str().unwrap()).unwrap();
            if !seed_ok || !k_ok || c.len() != 1088 {
                assert!(!valid, "tcId={}", t["tcId"]);
                continue;
            }
            let seed: ml_kem::Seed = hex_arr::<64>(&t["seed"]).into();
            let dk = DecapsulationKey::<MlKem768>::from_seed(seed);
            let ct: ml_kem::Ciphertext<MlKem768> = c.as_slice().try_into().expect("ct len");
            let got = k::decapsulate(&dk, &ct);
            let expect = hex_arr::<32>(&t["K"]);
            if valid {
                assert_eq!(got.as_slice(), &expect, "tcId={}", t["tcId"]);
            } else {
                assert_ne!(got.as_slice(), &expect, "tcId={}", t["tcId"]);
            }
        }
    }
}

#[test]
fn mldsa_verify_negative() {
    let j = load_json("wycheproof", "mldsa_65_verify_test.json");
    for g in j["testGroups"].as_array().unwrap() {
        let pk = hex::decode(g["publicKey"].as_str().unwrap()).unwrap();
        if pk.len() != 1952 {
            continue;
        }
        let pk_arr: [u8; 1952] = pk.try_into().unwrap();
        let vk = VerifyingKey::<MlDsa65>::decode(&pk_arr.into());
        for t in g["tests"].as_array().unwrap() {
            if t["comment"].as_str().unwrap().contains("context") {
                continue;
            }
            let msg = hex::decode(t["msg"].as_str().unwrap()).unwrap();
            let sig = hex::decode(t["sig"].as_str().unwrap()).unwrap();
            let got = if sig.len() == 3309 {
                let sig_arr: [u8; 3309] = sig.try_into().unwrap();
                match Signature::<MlDsa65>::decode(&sig_arr.into()) {
                    Some(sig) => vk.verify(&msg, &sig).is_ok(),
                    None => false,
                }
            } else {
                false
            };
            let valid = t["result"].as_str() == Some("valid");
            assert_eq!(got, valid, "tcId={}", t["tcId"]);
        }
    }
}
