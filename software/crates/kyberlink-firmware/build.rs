use kyberlink_crypto::mldsa_internal::{keygen_internal, sign_precomp_new_into, SignPrecomp};
use kyberlink_stamp::PLACEHOLDER_SEED;

fn main() {
    println!("cargo:rustc-link-arg-bins=-Tlink.x");
    println!("cargo:rustc-link-arg-bins=--defsym=_hart_stack_size=12K");
    println!("cargo:rerun-if-changed=build.rs");

    let (vk, sk) = keygen_internal(&PLACEHOLDER_SEED);
    let mut pc = SignPrecomp::default();
    sign_precomp_new_into(&mut pc, &sk);

    let n = core::mem::size_of::<SignPrecomp>();
    let spc = unsafe { core::slice::from_raw_parts(&pc as *const SignPrecomp as *const u8, n) };

    let mut out = String::new();
    out.push_str(&format!(
        "pub const SPC_SIZE: usize = {};\n",
        core::mem::size_of::<SignPrecomp>()
    ));
    push_rom(&mut out, "SPC_ROM", spc, true);
    push_rom(&mut out, "KK_ROM", &sk[32..64], false);
    push_rom(&mut out, "TR_ROM", &sk[64..128], false);
    push_rom(&mut out, "VK_ROM", &vk, false);

    let out_dir = std::path::PathBuf::from(std::env::var("OUT_DIR").unwrap());
    std::fs::write(out_dir.join("spc_rom.rs"), &out).unwrap();

    let fp = kyberlink_crypto::shake::sha3_256(&vk);
    std::fs::write(
        out_dir.join("fp_rom.rs"),
        format!("pub const FP_ROM: [u8; 32] = {:?};\n", fp),
    )
    .unwrap();
}

fn push_rom(out: &mut String, name: &str, bytes: &[u8], big: bool) {
    let kind = if big { "static" } else { "const" };
    out.push_str(&format!("pub {kind} {}: [u8; {}] = [\n", name, bytes.len()));
    for (i, b) in bytes.iter().enumerate() {
        if i % 32 == 0 {
            out.push('\n');
        }
        out.push_str(&b.to_string());
        out.push(',');
    }
    out.push_str("\n];\n");
}
