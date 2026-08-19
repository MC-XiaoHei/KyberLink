use std::path::{Path, PathBuf};

use ml_dsa::signature::{Signer, Verifier};
use ml_dsa::{ExpandedSigningKey, MlDsa65, Signature, SignatureEncoding};
use ml_kem::kem::Ciphertext;
use ml_kem::{DecapsulationKey, MlKem768};
use serde_json::{json, Value};

use kyberlink_crypto::kem as k;
use kyberlink_crypto::sign as s;

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .ancestors()
        .nth(3)
        .unwrap()
        .to_path_buf()
}

fn load(subdir: &str, file: &str) -> Value {
    let p = repo_root().join("vectors").join(subdir).join(file);
    serde_json::from_str(&std::fs::read_to_string(&p).expect("vector file")).unwrap()
}

fn hex_arr<const N: usize>(v: &Value) -> [u8; N] {
    hex::decode(v.as_str().unwrap()).unwrap().try_into().unwrap()
}

#[test]
fn cross_kem() {
    let vecs = load("cross", "kem.json");
    let mut out = Vec::new();
    for v in vecs.as_array().unwrap() {
        let seed: ml_kem::Seed = hex_arr::<64>(&v["seed"]).into();
        let seed_arr: [u8; 64] = seed.into();
        let kp = k::KemKeyPair::from_seed(&seed_arr);
        assert_eq!(hex_arr::<1184>(&v["ek"]), k::encaps_key_bytes(&kp.ek), "kem {}", v["index"]);
        let ct: Ciphertext<MlKem768> = hex_arr::<1088>(&v["ct"]).into();
        let ss = k::decapsulate(&kp.dk, &ct);
        let ss_expect: [u8; 32] = hex_arr::<32>(&v["ss"]);
        assert_eq!(&ss_expect[..], ss.as_slice(), "kem {}", v["index"]);
        let (ct_a, ss_a) = k::encapsulate_deterministic(&kp.ek, &[2u8; 32]);
        out.push(json!({
            "index": v["index"],
            "ct": hex::encode(ct_a.as_slice()),
            "ss": hex::encode(ss_a.as_slice()),
        }));
    }
    std::fs::write(repo_root().join("vectors/cross/kem_out.json"), serde_json::to_string(&out).unwrap()).unwrap();
}

#[test]
fn cross_dsa() {
    let vecs = load("cross", "dsa.json");
    let mut out = Vec::new();
    for v in vecs.as_array().unwrap() {
        let sk_expanded = hex_arr::<4032>(&v["sk"]);
        let esk = ExpandedSigningKey::<MlDsa65>::from_expanded(&sk_expanded.into());
        let msg = hex::decode(v["msg"].as_str().unwrap()).unwrap();
        let sig = esk.sign(&msg);
        let vk = esk.verifying_key();
        let liboqs_sig = Signature::<MlDsa65>::decode(&hex_arr::<3309>(&v["sig"]).into()).unwrap();
        assert!(vk.verify(&msg, &liboqs_sig).is_ok(), "dsa {}", v["index"]);
        out.push(json!({
            "index": v["index"],
            "msg": v["msg"],
            "pk": v["pk"],
            "sig": hex::encode(sig.to_bytes().as_slice()),
        }));
    }
    std::fs::write(repo_root().join("vectors/cross/dsa_out.json"), serde_json::to_string(&out).unwrap()).unwrap();
}
