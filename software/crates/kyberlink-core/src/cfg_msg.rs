use kyberlink_crypto::handshake::RomIdentity;
use kyberlink_crypto::mldsa_internal::{SignPrecomp, VK_LEN};

use crate::cfg_store::{
    self, CfgError, NorFlash, BINDING_BASE, BINDING_PAGES, IDENTITY_BASE, MAGIC_BINDING,
    MAGIC_IDENTITY,
};

pub use kyberlink_crypto::handshake::{KK_LEN, TR_LEN};
pub const FP_LEN: usize = 32;
pub const MAC_LEN: usize = 6;
pub const IP_LEN: usize = 4;
pub const SPC_LEN: usize = core::mem::size_of::<SignPrecomp>();

const VK_OFF: usize = 0;
const KK_OFF: usize = VK_OFF + VK_LEN;
const TR_OFF: usize = KK_OFF + KK_LEN;
const SPC_OFF: usize = TR_OFF + TR_LEN;
pub const IDENTITY_LEN: usize = SPC_OFF + SPC_LEN;

const B_ROLE: usize = 0;
const B_PEER_FP: usize = B_ROLE + 1;
const B_SRC_MAC: usize = B_PEER_FP + FP_LEN;
const B_DST_MAC: usize = B_SRC_MAC + MAC_LEN;
const B_SRC_IP: usize = B_DST_MAC + MAC_LEN;
const B_DST_IP: usize = B_SRC_IP + IP_LEN;
const B_SRC_PORT: usize = B_DST_IP + IP_LEN;
const B_DST_PORT: usize = B_SRC_PORT + 2;
pub const BINDING_LEN: usize = B_DST_PORT + 2;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Identity<'a> {
    pub vk: &'a [u8],
    pub kk: &'a [u8],
    pub tr: &'a [u8],
    pub spc: &'a [u8],
}

impl<'a> Identity<'a> {
    pub fn decode(payload: &'a [u8]) -> Result<Self, CfgError> {
        if payload.len() != IDENTITY_LEN {
            return Err(CfgError::Length);
        }
        Ok(Identity {
            vk: &payload[VK_OFF..KK_OFF],
            kk: &payload[KK_OFF..TR_OFF],
            tr: &payload[TR_OFF..SPC_OFF],
            spc: &payload[SPC_OFF..IDENTITY_LEN],
        })
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Binding {
    pub role_initiator: bool,
    pub peer_fp: [u8; FP_LEN],
    pub src_mac: [u8; MAC_LEN],
    pub dst_mac: [u8; MAC_LEN],
    pub src_ip: [u8; IP_LEN],
    pub dst_ip: [u8; IP_LEN],
    pub src_port: u16,
    pub dst_port: u16,
}

impl Default for Binding {
    fn default() -> Self {
        Binding {
            role_initiator: false,
            peer_fp: [0; FP_LEN],
            src_mac: [0; MAC_LEN],
            dst_mac: [0; MAC_LEN],
            src_ip: [0; IP_LEN],
            dst_ip: [0; IP_LEN],
            src_port: 0,
            dst_port: 0,
        }
    }
}

impl Binding {
    pub fn encode(&self, out: &mut [u8]) -> Result<(), CfgError> {
        if out.len() < BINDING_LEN {
            return Err(CfgError::Length);
        }
        out[B_ROLE] = self.role_initiator as u8;
        out[B_PEER_FP..B_SRC_MAC].copy_from_slice(&self.peer_fp);
        out[B_SRC_MAC..B_DST_MAC].copy_from_slice(&self.src_mac);
        out[B_DST_MAC..B_SRC_IP].copy_from_slice(&self.dst_mac);
        out[B_SRC_IP..B_DST_IP].copy_from_slice(&self.src_ip);
        out[B_DST_IP..B_SRC_PORT].copy_from_slice(&self.dst_ip);
        out[B_SRC_PORT..B_DST_PORT].copy_from_slice(&self.src_port.to_be_bytes());
        out[B_DST_PORT..BINDING_LEN].copy_from_slice(&self.dst_port.to_be_bytes());
        Ok(())
    }

    pub fn decode(b: &[u8]) -> Result<Self, CfgError> {
        if b.len() < BINDING_LEN {
            return Err(CfgError::Length);
        }
        if b[B_ROLE] > 1 {
            return Err(CfgError::Value);
        }
        let mut peer_fp = [0u8; FP_LEN];
        peer_fp.copy_from_slice(&b[B_PEER_FP..B_SRC_MAC]);
        let mut src_mac = [0u8; MAC_LEN];
        src_mac.copy_from_slice(&b[B_SRC_MAC..B_DST_MAC]);
        let mut dst_mac = [0u8; MAC_LEN];
        dst_mac.copy_from_slice(&b[B_DST_MAC..B_SRC_IP]);
        let mut src_ip = [0u8; IP_LEN];
        src_ip.copy_from_slice(&b[B_SRC_IP..B_DST_IP]);
        let mut dst_ip = [0u8; IP_LEN];
        dst_ip.copy_from_slice(&b[B_DST_IP..B_SRC_PORT]);
        Ok(Binding {
            role_initiator: b[B_ROLE] == 1,
            peer_fp,
            src_mac,
            dst_mac,
            src_ip,
            dst_ip,
            src_port: u16::from_be_bytes([b[B_SRC_PORT], b[B_SRC_PORT + 1]]),
            dst_port: u16::from_be_bytes([b[B_DST_PORT], b[B_DST_PORT + 1]]),
        })
    }

    pub fn load<F: NorFlash>(flash: &mut F) -> Result<Binding, CfgError> {
        cfg_store::verify(flash, BINDING_BASE, &MAGIC_BINDING, BINDING_LEN as u16)?;
        let mut buf = [0u8; BINDING_LEN];
        cfg_store::read_payload(flash, BINDING_BASE, 0, &mut buf)?;
        Binding::decode(&buf)
    }

    pub fn store<F: NorFlash>(&self, flash: &mut F) -> Result<(), CfgError> {
        let mut buf = [0u8; BINDING_LEN];
        self.encode(&mut buf)?;
        cfg_store::write_frame(flash, BINDING_BASE, BINDING_PAGES, MAGIC_BINDING, &buf)
    }
}

pub fn load_identity<F: NorFlash>(flash: &mut F) -> Result<RomIdentity, CfgError> {
    cfg_store::verify(flash, IDENTITY_BASE, &MAGIC_IDENTITY, IDENTITY_LEN as u16)?;
    let payload = flash
        .map(IDENTITY_BASE + cfg_store::HEADER_LEN as u32, IDENTITY_LEN)
        .ok_or(CfgError::Unmapped)?;
    let parts = Identity::decode(payload)?;
    Ok(RomIdentity {
        vk: parts.vk.try_into().map_err(|_| CfgError::Length)?,
        kk: parts.kk.try_into().map_err(|_| CfgError::Length)?,
        tr: parts.tr.try_into().map_err(|_| CfgError::Length)?,
        spc: unsafe { &*(parts.spc.as_ptr() as *const SignPrecomp) },
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cfg_store::tests::MemFlash;
    use crate::cfg_store::{FrameStream, IDENTITY_PAGES};

    fn write_identity_frame(f: &mut MemFlash, payload: &[u8]) {
        let mut s = FrameStream::begin(f, IDENTITY_BASE, IDENTITY_PAGES, MAGIC_IDENTITY).unwrap();
        for chunk in payload.chunks(251) {
            s.write(f, chunk).unwrap();
        }
        s.finish(f).unwrap();
    }

    #[test]
    fn load_identity_borrows_flash_payload() {
        let mut f = MemFlash::new(0x4_0000);
        let mut payload = [0u8; IDENTITY_LEN];
        payload[VK_OFF..KK_OFF].fill(0x11);
        payload[KK_OFF..TR_OFF].fill(0x22);
        payload[TR_OFF..SPC_OFF].fill(0x33);
        payload[SPC_OFF..].fill(0x44);
        write_identity_frame(&mut f, &payload);

        let id = load_identity(&mut f).unwrap();
        assert_eq!(id.vk[0], 0x11);
        assert_eq!(id.vk[VK_LEN - 1], 0x11);
        assert_eq!(id.kk[0], 0x22);
        assert_eq!(id.kk[KK_LEN - 1], 0x22);
        assert_eq!(id.tr[0], 0x33);
        assert_eq!(id.tr[TR_LEN - 1], 0x33);
        let spc = unsafe {
            core::slice::from_raw_parts(id.spc as *const SignPrecomp as *const u8, SPC_LEN)
        };
        assert_eq!(spc[0], 0x44);
        assert_eq!(spc[SPC_LEN - 1], 0x44);
    }

    #[test]
    fn load_identity_rejects_blank_flash() {
        let mut f = MemFlash::new(0x4_0000);
        assert!(load_identity(&mut f).is_err());
    }

    fn sample_binding() -> Binding {
        Binding {
            role_initiator: true,
            peer_fp: [0xAB; FP_LEN],
            src_mac: [1, 2, 3, 4, 5, 6],
            dst_mac: [7, 8, 9, 10, 11, 12],
            src_ip: [192, 168, 1, 1],
            dst_ip: [192, 168, 1, 2],
            src_port: 4500,
            dst_port: 4501,
        }
    }

    #[test]
    fn binding_roundtrip() {
        let b = sample_binding();
        let mut buf = [0u8; BINDING_LEN];
        b.encode(&mut buf).unwrap();
        assert_eq!(Binding::decode(&buf).unwrap(), b);
        let mut r = b;
        r.role_initiator = false;
        r.encode(&mut buf).unwrap();
        assert_eq!(Binding::decode(&buf).unwrap(), r);
    }

    #[test]
    fn binding_role_out_of_range_rejected() {
        let mut buf = [0u8; BINDING_LEN];
        sample_binding().encode(&mut buf).unwrap();
        buf[B_ROLE] = 2;
        assert_eq!(Binding::decode(&buf), Err(CfgError::Value));
    }

    #[test]
    fn binding_short_slice_rejected() {
        assert_eq!(
            Binding::decode(&[0u8; BINDING_LEN - 1]),
            Err(CfgError::Length)
        );
    }

    #[test]
    fn identity_layout_splits_payload() {
        let payload: Vec<u8> = (0..IDENTITY_LEN).map(|i| (i % 251) as u8).collect();
        let id = Identity::decode(&payload).unwrap();
        assert_eq!(id.vk.len(), VK_LEN);
        assert_eq!(id.kk.len(), KK_LEN);
        assert_eq!(id.tr.len(), TR_LEN);
        assert_eq!(id.spc.len(), SPC_LEN);
        assert_eq!(id.vk[0], payload[0]);
        assert_eq!(id.kk[0], payload[VK_OFF + VK_LEN]);
        assert_eq!(id.tr[0], payload[KK_OFF + KK_LEN]);
        assert_eq!(id.spc[0], payload[TR_OFF + TR_LEN]);
        assert_eq!(id.spc[SPC_LEN - 1], payload[IDENTITY_LEN - 1]);
    }

    #[test]
    fn identity_wrong_length_rejected() {
        assert_eq!(Identity::decode(&[0u8; 100]).err(), Some(CfgError::Length));
    }
}
