pub const PLACEHOLDER_SEED: [u8; 32] = [0xA5; 32];

pub use kyberlink_crypto::mldsa_internal::{SK_LEN, VK_LEN};

pub const SPC_LEN: usize = core::mem::size_of::<kyberlink_crypto::mldsa_internal::SignPrecomp>();
