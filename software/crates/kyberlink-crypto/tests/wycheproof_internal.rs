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
    hex::decode(v.as_str().unwrap()).unwrap().try_into().unwrap()
}

#[test]
fn mlkem_decaps_internal() {
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
            let (_, dk) = ki::keygen_internal(&d, &z);
            let got = ki::decaps_internal(&dk, &c);
            let expect = hex_arr::<32>(&t["K"]);
            if valid {
                assert_eq!(got.as_slice(), &expect, "tcId={}", t["tcId"]);
            } else {
                assert_ne!(got.as_slice(), &expect, "tcId={}", t["tcId"]);
            }
        }
    }
}
