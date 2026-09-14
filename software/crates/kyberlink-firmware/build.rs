fn main() {
    println!("cargo:rustc-link-arg-bins=-Tlink.x");
    println!("cargo:rustc-link-arg-bins=--defsym=_hart_stack_size=12K");
    println!("cargo:rerun-if-changed=build.rs");
}
