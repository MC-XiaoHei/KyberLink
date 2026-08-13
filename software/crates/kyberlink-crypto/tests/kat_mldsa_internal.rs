use std::path::{Path, PathBuf};

use serde_json::Value;
use sha2::{Digest as Sha2Digest, Sha224, Sha256, Sha384, Sha512, Sha512_224, Sha512_256};
use sha3::digest::{ExtendableOutput, Update, XofReader};
use sha3::{Shake128, Shake256, Sha3_224, Sha3_256, Sha3_384, Sha3_512};

use kyberlink_crypto::mldsa_internal as mi;

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
    hex::decode(v.as_str().unwrap()).unwrap()
}

fn prehash(alg: &str, msg: &[u8]) -> Vec<u8> {
    match alg {
        "SHA2-224" => Sha224::digest(msg).to_vec(),
        "SHA2-256" => Sha256::digest(msg).to_vec(),
        "SHA2-384" => Sha384::digest(msg).to_vec(),
        "SHA2-512" => Sha512::digest(msg).to_vec(),
        "SHA2-512/224" => Sha512_224::digest(msg).to_vec(),
        "SHA2-512/256" => Sha512_256::digest(msg).to_vec(),
        "SHA3-224" => Sha3_224::digest(msg).to_vec(),
        "SHA3-256" => Sha3_256::digest(msg).to_vec(),
        "SHA3-384" => Sha3_384::digest(msg).to_vec(),
        "SHA3-512" => Sha3_512::digest(msg).to_vec(),
        "SHAKE-128" => {
            let mut h = Shake128::default();
            h.update(msg);
            let mut out = [0u8; 32];
            h.finalize_xof().read(&mut out);
            out.to_vec()
        }
        "SHAKE-256" => {
            let mut h = Shake256::default();
            h.update(msg);
            let mut out = [0u8; 64];
            h.finalize_xof().read(&mut out);
            out.to_vec()
        }
        other => panic!("unknown hashAlg {}", other),
    }
}

fn oid(alg: &str) -> &'static [u8] {
    match alg {
        "SHA2-224" => &[0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x04],
        "SHA2-256" => &[0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01],
        "SHA2-384" => &[0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x02],
        "SHA2-512" => &[0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03],
        "SHA2-512/224" => &[0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x05],
        "SHA2-512/256" => &[0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x06],
        "SHA3-224" => &[0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x07],
        "SHA3-256" => &[0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x08],
        "SHA3-384" => &[0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x09],
        "SHA3-512" => &[0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x0A],
        "SHAKE-128" => &[0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x0B],
        "SHAKE-256" => &[0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x0C],
        other => panic!("unknown hashAlg {}", other),
    }
}

fn prehash_m2(pt: &Value) -> Vec<u8> {
    let alg = pt["hashAlg"].as_str().unwrap();
    let msg = hex_vec(&pt["message"]);
    let ph = prehash(alg, &msg);
    let ctx = ctx_of(pt);
    let mut m2 = Vec::with_capacity(2 + ctx.len() + 11 + ph.len());
    m2.push(0x01);
    m2.push(ctx.len() as u8);
    m2.extend_from_slice(&ctx);
    m2.extend_from_slice(oid(alg));
    m2.extend_from_slice(&ph);
    m2
}

fn ctx_of(pt: &Value) -> Vec<u8> {
    pt["context"].as_str().map(|c| hex::decode(c).unwrap()).unwrap_or_default()
}

#[test]
fn mldsa_keygen() {
    let prompt = load_json("ML-DSA-keyGen-FIPS204", "prompt.json");
    let expected = load_json("ML-DSA-keyGen-FIPS204", "expectedResults.json");
    for (pg, eg) in prompt["testGroups"]
        .as_array()
        .unwrap()
        .iter()
        .zip(expected["testGroups"].as_array().unwrap())
    {
        if pg["parameterSet"] != "ML-DSA-65" {
            continue;
        }
        for (pt, et) in pg["tests"].as_array().unwrap().iter().zip(eg["tests"].as_array().unwrap()) {
            let seed = hex_arr::<32>(&pt["seed"]);
            let (vk, sk) = mi::keygen_internal(&seed);
            assert_eq!(hex_vec(&et["pk"]), vk, "tcId={}", pt["tcId"]);
            assert_eq!(hex_vec(&et["sk"]), sk, "tcId={}", pt["tcId"]);
        }
    }
}

#[test]
fn mldsa_siggen() {
    let prompt = load_json("ML-DSA-sigGen-FIPS204", "prompt.json");
    let expected = load_json("ML-DSA-sigGen-FIPS204", "expectedResults.json");
    for (pg, eg) in prompt["testGroups"]
        .as_array()
        .unwrap()
        .iter()
        .zip(expected["testGroups"].as_array().unwrap())
    {
        if pg["parameterSet"] != "ML-DSA-65" {
            continue;
        }
        let det = pg["deterministic"].as_bool().unwrap_or(true);
        let pre = pg["preHash"].as_str();
        let ext_mu = pg.get("externalMu").and_then(|v| v.as_bool());
        for (pt, et) in pg["tests"].as_array().unwrap().iter().zip(eg["tests"].as_array().unwrap()) {
            let sk = hex_arr::<4032>(&pt["sk"]);
            let rnd: [u8; 32] = pt.get("rnd").map(hex_arr::<32>).unwrap_or([0u8; 32]);
            let sig = match (pre, ext_mu) {
                (Some("pure"), _) => mi::sign_rnd_internal(&sk, &hex_vec(&pt["message"]), &ctx_of(pt), &rnd),
                (Some("preHash"), _) => {
                    let m2 = prehash_m2(pt);
                    if det {
                        mi::sign_prehash_internal(&sk, &m2, &[0u8; 32])
                    } else {
                        mi::sign_prehash_rnd_internal(&sk, &m2, &rnd)
                    }
                }
                (None, Some(true)) => {
                    if pt.get("rnd").is_some() {
                        mi::sign_mu_rnd_internal(&sk, &hex_arr::<64>(&pt["mu"]), &rnd)
                    } else {
                        mi::sign_mu_internal(&sk, &hex_arr::<64>(&pt["mu"]))
                    }
                }
                (None, Some(false)) => mi::sign_prehash_internal(&sk, &hex_vec(&pt["message"]), &rnd),
                (None, None) => {
                    if pt.get("mu").is_some() {
                        mi::sign_mu_internal(&sk, &hex_arr::<64>(&pt["mu"]))
                    } else if pt.get("message").is_some() {
                        mi::sign_internal_msg(&sk, &hex_vec(&pt["message"]))
                    } else {
                        panic!("unrecognized sigGen group")
                    }
                }
                other => panic!("unrecognized group {:?}", other),
            };
            assert_eq!(hex_vec(&et["signature"]), sig, "tcId={}", pt["tcId"]);
        }
    }
}

#[test]
fn mldsa_sigver() {
    let prompt = load_json("ML-DSA-sigVer-FIPS204", "prompt.json");
    let expected = load_json("ML-DSA-sigVer-FIPS204", "expectedResults.json");
    for (pg, eg) in prompt["testGroups"]
        .as_array()
        .unwrap()
        .iter()
        .zip(expected["testGroups"].as_array().unwrap())
    {
        if pg["parameterSet"] != "ML-DSA-65" {
            continue;
        }
        let pre = pg["preHash"].as_str();
        let ext_mu = pg.get("externalMu").and_then(|v| v.as_bool());
        for (pt, et) in pg["tests"].as_array().unwrap().iter().zip(eg["tests"].as_array().unwrap()) {
            let vk = hex_arr::<1952>(&pt["pk"]);
            let sig = hex_arr::<3309>(&pt["signature"]);
            let want = et["testPassed"].as_bool().unwrap();
            let ok = match (pre, ext_mu) {
                (Some("preHash"), _) => {
                    let m2 = prehash_m2(pt);
                    mi::verify_prehash_internal(&vk, &m2, &sig)
                }
                (None, Some(true)) => mi::verify_mu_internal(&vk, &hex_arr::<64>(&pt["mu"]), &sig),
                (None, Some(false)) => mi::verify_prehash_internal(&vk, &hex_vec(&pt["message"]), &sig),
                _ => mi::verify_internal(&vk, &hex_vec(&pt["message"]), &ctx_of(pt), &sig),
            };
            assert_eq!(want, ok, "tcId={}", pt["tcId"]);
        }
    }
}
