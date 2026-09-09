use kyberlink_crypto::mldsa_internal::{keygen_internal, sign_precomp_new_into, SignPrecomp};
use kyberlink_stamp::{PLACEHOLDER_SEED, SK_LEN, SPC_LEN, VK_LEN};

fn gen(seed: &[u8; 32]) -> (Vec<u8>, Vec<u8>, Vec<u8>) {
    let (vk, sk) = keygen_internal(seed);
    let mut pc = SignPrecomp::default();
    sign_precomp_new_into(&mut pc, &sk);
    let spc = unsafe {
        core::slice::from_raw_parts(&pc as *const SignPrecomp as *const u8, SPC_LEN)
    };
    (vk.to_vec(), sk.to_vec(), spc.to_vec())
}

fn dump(b: &[u8]) -> String {
    b.iter().map(|x| format!("{:02x}", x)).collect()
}

fn os_random() -> [u8; 32] {
    let mut buf = [0u8; 32];
    getrandom::getrandom(&mut buf).expect("os random");
    buf
}

fn main() {
    let mut args: Vec<String> = std::env::args().skip(1).collect();
    let mut out_path = None;
    let mut firmware = None;
    let mut i = 0;
    while i < args.len() {
        let a = &args[i];
        if a == "-o" {
            if out_path.is_some() {
                eprintln!("duplicate -o");
                std::process::exit(1);
            }
            out_path = Some(
                args.get(i + 1)
                    .cloned()
                    .expect("usage: kyberlink-stamp <firmware> [-o out]"),
            );
            i += 2;
        } else {
            if firmware.is_some() {
                eprintln!("unexpected extra argument: {}", a);
                std::process::exit(1);
            }
            firmware = Some(a.clone());
            i += 1;
        }
    }
    let fw = firmware.expect("usage: kyberlink-stamp <firmware> [-o out]");
    let out_path = out_path.unwrap_or_else(|| {
        let p = std::path::Path::new(&fw);
        let file = p.file_name().unwrap_or_default().to_string_lossy();
        p.with_file_name(format!("{}.id.bin", file)).display().to_string()
    });

    let data = std::fs::read(&fw).expect("read firmware");

    let (vk_ph, sk_ph, spc_ph) = gen(&PLACEHOLDER_SEED);
    assert_eq!(vk_ph.len(), VK_LEN);
    assert_eq!(sk_ph.len(), SK_LEN);
    assert_eq!(spc_ph.len(), SPC_LEN);

    let find_unique = |needle: &[u8], name: &str| -> usize {
        let first = data
            .windows(needle.len())
            .position(|w| w == needle)
            .unwrap_or_else(|| panic!("placeholder {} not found (image already personalized?)", name));
        assert!(
            !data.windows(needle.len()).skip(first + 1).any(|w| w == needle),
            "placeholder {} found multiple times (ambiguous)",
            name
        );
        first
    };
    let pos = find_unique(&vk_ph, "VK");
    let pos_sk = find_unique(&sk_ph, "SK");
    let pos_spc = find_unique(&spc_ph, "SPC");

    let seed = os_random();
    let (vk, sk, spc) = gen(&seed);

    let mut out = data.clone();
    out[pos..pos + VK_LEN].copy_from_slice(&vk);
    out[pos_sk..pos_sk + SK_LEN].copy_from_slice(&sk);
    out[pos_spc..pos_spc + SPC_LEN].copy_from_slice(&spc);
    std::fs::write(&out_path, &out).expect("write stamped image");

    let fp = kyberlink_crypto::shake::sha3_256(&vk);
    println!("stamped: {} ({} bytes)", out_path, out.len());
    println!("own fingerprint: {}", dump(&fp));
}
