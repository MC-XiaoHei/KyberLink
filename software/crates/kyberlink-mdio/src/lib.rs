#![cfg_attr(not(any(feature = "std", test)), no_std)]

pub mod bus;
pub mod clause45;
pub mod dp83867;
pub mod frame;
pub mod regs;

#[cfg(test)]
mod test_support;

pub use bus::{MdioError, MdioPins};
pub use frame::{read, write};

pub const ADDR_BITS: u8 = 5;
pub const ADDR_MAX: u8 = (1 << ADDR_BITS) - 1;
