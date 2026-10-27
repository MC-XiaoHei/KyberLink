use std::path::{Path, PathBuf};

use serde_json::Value;

use kyberlink_crypto::mldsa_internal as mi;

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

fn hex_vec(v: &Value) -> Vec<u8> {
    v.as_str()
        .map(|s| hex::decode(s).unwrap())
        .unwrap_or_default()
}

fn hex_arr<const N: usize>(v: &Value) -> [u8; N] {
    hex::decode(v.as_str().unwrap())
        .unwrap()
        .try_into()
        .unwrap()
}

fn ctx_of(t: &Value) -> Vec<u8> {
    t.get("ctx")
        .and_then(|c| c.as_str())
        .map(hex::decode)
        .map(|r| r.unwrap())
        .unwrap_or_default()
}

fn has_flag(t: &Value, flag: &str) -> bool {
    t["flags"]
        .as_array()
        .map(|a| a.iter().any(|v| v.as_str() == Some(flag)))
        .unwrap_or(false)
}

#[test]
fn mldsa_sign_seed_internal() {
    let mut ms = mi::MldsaScratch::new();
    let j = load_json("wycheproof", "mldsa_65_sign_seed_test.json");
    for g in j["testGroups"].as_array().unwrap() {
        if g["privateSeed"].as_str().map(|s| s.len()).unwrap_or(0) != 64 {
            continue;
        }
        let seed = hex_arr::<32>(&g["privateSeed"]);
        let (vk, sk) = mi::keygen_internal(&seed);
        assert_eq!(vk.to_vec(), hex_vec(&g["publicKey"]), "vk mismatch");
        for t in g["tests"].as_array().unwrap() {
            if t["result"].as_str() != Some("valid") {
                continue;
            }
            if has_flag(t, "Internal") {
                let mu = hex_arr::<64>(&t["mu"]);
                let sig = mi::sign_mu_internal(&sk, &mu);
                assert_eq!(sig.to_vec(), hex_vec(&t["sig"]), "tcId={}", t["tcId"]);
            } else if has_flag(t, "Randomized") {
                let msg = hex_vec(&t["msg"]);
                let ctx = ctx_of(t);
                let ref_sig: [u8; 3309] = hex_vec(&t["sig"]).try_into().unwrap();
                assert!(
                    mi::verify_internal(&vk, &msg, &ctx, &ref_sig, &mut ms),
                    "randomized sig rejected tcId={}",
                    t["tcId"]
                );
            } else {
                let msg = hex_vec(&t["msg"]);
                let ctx = ctx_of(t);
                let sig = mi::sign_rnd_internal(&sk, &msg, &ctx, &[0u8; 32]);
                assert_eq!(sig.to_vec(), hex_vec(&t["sig"]), "tcId={}", t["tcId"]);
            }
        }
    }
}

#[test]
fn mldsa_sign_noseed_internal() {
    let mut ms = mi::MldsaScratch::new();
    let j = load_json("wycheproof", "mldsa_65_sign_noseed_test.json");
    for g in j["testGroups"].as_array().unwrap() {
        if g["privateKey"].as_str().map(|s| s.len()).unwrap_or(0) != 8064 {
            continue;
        }
        let vk = hex_arr::<1952>(&g["publicKey"]);
        for t in g["tests"].as_array().unwrap() {
            if t["result"].as_str() != Some("valid") {
                continue;
            }
            let sig = hex_arr::<3309>(&t["sig"]);
            if has_flag(t, "Internal") {
                let mu = hex_arr::<64>(&t["mu"]);
                assert!(
                    mi::verify_mu_internal(&vk, &mu, &sig, &mut ms),
                    "ref sig rejected tcId={}",
                    t["tcId"]
                );
            } else {
                let msg = hex_vec(&t["msg"]);
                let ctx = ctx_of(t);
                assert!(
                    mi::verify_internal(&vk, &msg, &ctx, &sig, &mut ms),
                    "ref sig rejected tcId={}",
                    t["tcId"]
                );
            }
        }
    }
}

#[test]
fn mldsa_verify_internal() {
    let mut ms = mi::MldsaScratch::new();
    let j = load_json("wycheproof", "mldsa_65_verify_test.json");
    for g in j["testGroups"].as_array().unwrap() {
        if g["publicKey"].as_str().map(|s| s.len()).unwrap_or(0) != 3904 {
            continue;
        }
        let vk = hex_arr::<1952>(&g["publicKey"]);
        for t in g["tests"].as_array().unwrap() {
            let msg = hex_vec(&t["msg"]);
            let ctx = ctx_of(t);
            let sig = hex_vec(&t["sig"]);
            let valid = t["result"].as_str() == Some("valid");
            let got = if sig.len() == mi::SIG_LEN {
                let sig_arr: [u8; 3309] = sig.as_slice().try_into().unwrap();
                mi::verify_internal(&vk, &msg, &ctx, &sig_arr, &mut ms)
            } else {
                false
            };
            assert_eq!(got, valid, "tcId={}", t["tcId"]);
        }
    }
}
