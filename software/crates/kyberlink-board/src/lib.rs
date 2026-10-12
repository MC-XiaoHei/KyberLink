#![cfg_attr(target_arch = "riscv32", no_std)]

#[cfg(target_arch = "riscv32")]
pub mod bringup;
#[cfg(target_arch = "riscv32")]
pub mod mdio;
#[cfg(target_arch = "riscv32")]
pub mod pinmap;
#[cfg(target_arch = "riscv32")]
pub mod spi;
#[cfg(target_arch = "riscv32")]
pub mod uart;
