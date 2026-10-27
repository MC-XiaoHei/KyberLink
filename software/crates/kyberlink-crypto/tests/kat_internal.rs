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
    let p = repo_root().join("vectors/kat").join(subdir).join(file);
    serde_json::from_str(&std::fs::read_to_string(&p).expect("vector file")).unwrap()
}

fn hex_arr<const N: usize>(v: &Value) -> [u8; N] {
    hex::decode(v.as_str().unwrap())
        .unwrap()
        .try_into()
        .unwrap()
}

fn hex_vec(v: &Value) -> Vec<u8> {
    hex::decode(v.as_str().unwrap()).unwrap()
}

fn groups(v: &Value) -> &Vec<Value> {
    v["testGroups"].as_array().unwrap()
}

#[test]
fn kem_keygen() {
    let mut kem = ki::KemScratch::new();
    let prompt = load_json("ML-KEM-keyGen-FIPS203", "prompt.json");
    let expected = load_json("ML-KEM-keyGen-FIPS203", "expectedResults.json");
    for (pg, eg) in groups(&prompt).iter().zip(groups(&expected)) {
        if pg["parameterSet"] != "ML-KEM-768" {
            continue;
        }
        for (pt, et) in pg["tests"]
            .as_array()
            .unwrap()
            .iter()
            .zip(eg["tests"].as_array().unwrap())
        {
            let d = hex_arr::<32>(&pt["d"]);
            let z = hex_arr::<32>(&pt["z"]);
            let mut ek = [0u8; ki::EK_LEN];
            let mut dk = [0u8; ki::DK_LEN];
            ki::keygen_internal(&d, &z, &mut kem, &mut ek, &mut dk);
            assert_eq!(hex_vec(&et["ek"]), ek, "tcId={}", pt["tcId"]);
            assert_eq!(hex_vec(&et["dk"]), dk, "tcId={}", pt["tcId"]);
        }
    }
}

#[test]
fn kem_encap() {
    let mut kem = ki::KemScratch::new();
    let prompt = load_json("ML-KEM-encapDecap-FIPS203", "prompt.json");
    let expected = load_json("ML-KEM-encapDecap-FIPS203", "expectedResults.json");
    for (pg, eg) in groups(&prompt).iter().zip(groups(&expected)) {
        if pg["parameterSet"] != "ML-KEM-768" || pg["function"] != "encapsulation" {
            continue;
        }
        for (pt, et) in pg["tests"]
            .as_array()
            .unwrap()
            .iter()
            .zip(eg["tests"].as_array().unwrap())
        {
            let ek = hex_arr::<1184>(&pt["ek"]);
            let m = hex_arr::<32>(&pt["m"]);
            let mut k = [0u8; 32];
            let mut c = [0u8; ki::CT_LEN];
            ki::encaps_internal(&ek, &m, &mut kem, &mut k, &mut c);
            assert_eq!(hex_vec(&et["c"]), c, "tcId={}", pt["tcId"]);
            assert_eq!(hex_vec(&et["k"]), k, "tcId={}", pt["tcId"]);
        }
    }
}

#[test]
fn kem_decap() {
    let mut kem = ki::KemScratch::new();
    let prompt = load_json("ML-KEM-encapDecap-FIPS203", "prompt.json");
    let expected = load_json("ML-KEM-encapDecap-FIPS203", "expectedResults.json");
    for (pg, eg) in groups(&prompt).iter().zip(groups(&expected)) {
        if pg["parameterSet"] != "ML-KEM-768" || pg["function"] != "decapsulation" {
            continue;
        }
        for (pt, et) in pg["tests"]
            .as_array()
            .unwrap()
            .iter()
            .zip(eg["tests"].as_array().unwrap())
        {
            let dk = hex_arr::<2400>(&pt["dk"]);
            let c = hex_vec(&pt["c"]);
            let k = ki::decaps_internal(&dk, &c, &mut kem);
            assert_eq!(hex_vec(&et["k"]), k, "tcId={}", pt["tcId"]);
        }
    }
}
