#![cfg_attr(not(any(feature = "std", test)), no_std)]
#[cfg(any(feature = "std", test))]
extern crate std;
#[cfg(feature = "gcm")]
pub mod gcm;
pub mod entropy;
pub mod handshake;
pub mod kem;
pub mod kem_internal;
pub mod mldsa_internal;
pub mod mldsa_mont;
pub mod ntt;
pub mod scratch;
pub mod shake;
pub mod sign;
