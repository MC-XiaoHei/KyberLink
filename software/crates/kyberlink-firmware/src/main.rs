#![cfg_attr(target_arch = "riscv32", no_std)]
#![cfg_attr(target_arch = "riscv32", no_main)]

#[cfg(target_arch = "riscv32")]
mod firmware;

#[cfg(target_arch = "riscv32")]
mod pinmap;

#[cfg(target_arch = "riscv32")]
mod usb;

#[cfg(target_arch = "riscv32")]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}

#[cfg(not(target_arch = "riscv32"))]
fn main() {}
