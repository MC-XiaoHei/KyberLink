#![cfg_attr(target_arch = "riscv32", no_std)]
#![cfg_attr(target_arch = "riscv32", no_main)]

#[cfg(target_arch = "riscv32")]
mod firmware;

#[cfg(target_arch = "riscv32")]
mod panic_report;

#[cfg(target_arch = "riscv32")]
#[panic_handler]
fn panic(info: &core::panic::PanicInfo) -> ! {
    panic_report::report(info);
    loop {}
}

#[cfg(not(target_arch = "riscv32"))]
fn main() {}
