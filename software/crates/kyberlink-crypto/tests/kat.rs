use std::path::{Path, PathBuf};

use ml_dsa::signature::{Signer, Verifier};
use ml_dsa::{ExpandedSigningKey, MlDsa65, Signature, SignatureEncoding, VerifyingKey};
use ml_kem::kem::{Ciphertext, Decapsulate};
use ml_kem::{ExpandedKeyEncoding, MlKem768};
use serde_json::Value;

use kyberlink_crypto::kem as k;
use kyberlink_crypto::sign as s;

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .ancestors()
        .nth(3)
        .unwrap()
        .to_path_buf()
}

fn load_json(subdir: &str, file: &str) -> Value {
    let p = repo_root().join("vectors/kat").join(subdir).join(file);
    serde_json::from_str(&std::fs::read_to_string(&p).expect("vector file")).unwrap()
}

fn hex_arr<const N: usize>(v: &Value) -> [u8; N] {
    hex::decode(v.as_str().unwrap()).unwrap().try_into().unwrap()
}

fn hex_vec(v: &Value) -> Vec<u8> {
    match v.as_str() {
        Some(s) => hex::decode(s).unwrap(),
        None => Vec::new(),
    }
}

fn groups(v: &Value) -> &Vec<Value> {
    v["testGroups"].as_array().unwrap()
}

#[test]
#[allow(deprecated)]
fn kem_keygen() {
    let prompt = load_json("ML-KEM-keyGen-FIPS203", "prompt.json");
    let expected = load_json("ML-KEM-keyGen-FIPS203", "expectedResults.json");
    for (pg, eg) in groups(&prompt).iter().zip(groups(&expected)) {
        if pg["parameterSet"] != "ML-KEM-768" {
            continue;
        }
        for (pt, et) in pg["tests"].as_array().unwrap().iter().zip(eg["tests"].as_array().unwrap()) {
            let d = hex_arr::<32>(&pt["d"]);
            let z = hex_arr::<32>(&pt["z"]);
            let mut seed = [0u8; 64];
            seed[..32].copy_from_slice(&d);
            seed[32..].copy_from_slice(&z);
            let kp = k::KemKeyPair::from_seed(&seed);
            assert_eq!(hex_arr::<1184>(&et["ek"]), k::encaps_key_bytes(&kp.ek));
            let dk_bytes =
                <ml_kem::DecapsulationKey<MlKem768> as ExpandedKeyEncoding>::to_expanded_bytes(&kp.dk);
            assert_eq!(hex_vec(&et["dk"]), dk_bytes.as_slice());
        }
    }
}

#[test]
#[allow(deprecated)]
fn kem_encap_decap() {
    let prompt = load_json("ML-KEM-encapDecap-FIPS203", "prompt.json");
    let expected = load_json("ML-KEM-encapDecap-FIPS203", "expectedResults.json");
    for (pg, eg) in groups(&prompt).iter().zip(groups(&expected)) {
        if pg["parameterSet"] != "ML-KEM-768" {
            continue;
        }
        let func = pg["function"].as_str().unwrap();
        for (pt, et) in pg["tests"].as_array().unwrap().iter().zip(eg["tests"].as_array().unwrap()) {
            if func == "encapsulation" {
                let ek = k::encaps_key_from_bytes(&hex_arr::<1184>(&pt["ek"])).unwrap();
                let (ct, ss) = k::encapsulate_deterministic(&ek, &hex_arr::<32>(&pt["m"]));
                assert_eq!(hex_vec(&et["c"]), ct.as_slice());
                assert_eq!(hex_vec(&et["k"]), ss.as_slice());
            } else if func == "decapsulation" {
                let enc: ml_kem::ExpandedDecapsulationKey<MlKem768> =
                    hex_arr::<2400>(&pt["dk"]).into();
                let dk =
                    <ml_kem::DecapsulationKey<MlKem768> as ExpandedKeyEncoding>::from_expanded_bytes(&enc)
                        .unwrap();
                let ct: Ciphertext<MlKem768> = hex_arr::<1088>(&pt["c"]).into();
                let ss = dk.decapsulate(&ct);
                assert_eq!(hex_vec(&et["k"]), ss.as_slice());
            }
        }
    }
}

#[test]
#[allow(deprecated)]
fn dsa_keygen() {
    let prompt = load_json("ML-DSA-keyGen-FIPS204", "prompt.json");
    let expected = load_json("ML-DSA-keyGen-FIPS204", "expectedResults.json");
    for (pg, eg) in groups(&prompt).iter().zip(groups(&expected)) {
        if pg["parameterSet"] != "ML-DSA-65" || pg["preHash"].as_str() == Some("preHash") {
            continue;
        }
        if pg["preHash"].as_bool().unwrap_or(false) {
            continue;
        }
        if !pg["deterministic"].as_bool().unwrap_or(true) {
            continue;
        }
        for (pt, et) in pg["tests"].as_array().unwrap().iter().zip(eg["tests"].as_array().unwrap()) {
            let kp = s::SignKeyPair::from_seed(&hex_arr::<32>(&pt["seed"]));
            assert_eq!(hex_arr::<1952>(&et["pk"]), s::vk_bytes(&kp.vk));
            let enc_sk = kp.sk.expanded_key().to_expanded();
            assert_eq!(hex_vec(&et["sk"]), enc_sk.as_slice());
        }
    }
}

#[test]
#[allow(deprecated)]
fn dsa_siggen() {
    let prompt = load_json("ML-DSA-sigGen-FIPS204", "prompt.json");
    let expected = load_json("ML-DSA-sigGen-FIPS204", "expectedResults.json");
    for (pg, eg) in groups(&prompt).iter().zip(groups(&expected)) {
        if pg["parameterSet"] != "ML-DSA-65" {
            continue;
        }
        if pg["preHash"].as_str() == Some("preHash") {
            continue;
        }
        if !pg["deterministic"].as_bool().unwrap_or(true) {
            continue;
        }
        if pg["signatureInterface"].as_str() == Some("internal") {
            continue;
        }
        for (pt, et) in pg["tests"].as_array().unwrap().iter().zip(eg["tests"].as_array().unwrap()) {
            let esk =
                ExpandedSigningKey::<MlDsa65>::from_expanded(&hex_arr::<4032>(&pt["sk"]).into());
            let msg = hex_vec(&pt["message"]);
            let ctx = hex_vec(&pt["context"]);
            let sig = if ctx.is_empty() {
                esk.sign(&msg)
            } else {
                esk.sign_deterministic(&msg, &ctx).unwrap()
            };
            assert_eq!(hex_vec(&et["signature"]), sig.to_bytes().as_slice());
        }
    }
}

#[test]
fn dsa_sigver() {
    let prompt = load_json("ML-DSA-sigVer-FIPS204", "prompt.json");
    let expected = load_json("ML-DSA-sigVer-FIPS204", "expectedResults.json");
    for (pg, eg) in groups(&prompt).iter().zip(groups(&expected)) {
        if pg["parameterSet"] != "ML-DSA-65" {
            continue;
        }
        if pg["preHash"].as_str() == Some("preHash") {
            continue;
        }
        if pg["signatureInterface"].as_str() == Some("internal") {
            continue;
        }
        for (pt, et) in pg["tests"].as_array().unwrap().iter().zip(eg["tests"].as_array().unwrap()) {
            let vk = VerifyingKey::<MlDsa65>::decode(&hex_arr::<1952>(&pt["pk"]).into());
            let expected = et["testPassed"].as_bool().unwrap();
            let got = match Signature::<MlDsa65>::decode(&hex_arr::<3309>(&pt["signature"]).into())
            {
                Some(sig) => {
                    vk.verify_with_context(&hex_vec(&pt["message"]), &hex_vec(&pt["context"]), &sig)
                }
                None => false,
            };
            assert_eq!(got, expected);
        }
    }
}
