use std::sync::atomic::{AtomicU32, Ordering};

use kyberlink_core::handshake_fsm::{
    REG_KEY_DEC, REG_KEY_ENC, REG_SALT_HI, REG_SALT_LO, REG_SEQ, REG_SPI,
};
use kyberlink_vecgen::cipher::GcmCipher;

use crate::bus::PeerBus;

pub const ESP_OVERHEAD: usize = 78;
pub const MAX_INNER: usize = 1422;
pub const HEADER: usize = 20;
pub const TAG: usize = 16;

const WINDOW: u32 = 64;
const PAD_TRAILER: usize = 2;
const MAX_PAD: usize = 15;
const PAD_MARKER: u8 = 0x04;

pub struct DataPlane {
    enc: GcmCipher,
    dec: GcmCipher,
    spi: [u8; 4],
    salt: [u8; 8],
    tx_seq: u32,
    rx_top: u32,
    rx_seen: u64,
}

pub struct Shards {
    next: AtomicU32,
}

impl Shards {
    pub fn new(first: u32) -> Self {
        Self {
            next: AtomicU32::new(first),
        }
    }

    pub fn seal(&self, plane: &mut DataPlane, payload: &[u8], frame: &mut [u8]) -> Option<usize> {
        plane.seal_at(self.next.fetch_add(1, Ordering::Relaxed), payload, frame)
    }
}

impl DataPlane {
    pub fn from_bus(bus: &PeerBus) -> Self {
        let mut enc = [0u8; 32];
        let mut dec = [0u8; 32];
        for i in 0..8u8 {
            let at = i as usize * 4;
            enc[at..at + 4].copy_from_slice(&bus.reg(REG_KEY_ENC + i).to_be_bytes());
            dec[at..at + 4].copy_from_slice(&bus.reg(REG_KEY_DEC + i).to_be_bytes());
        }
        let mut salt = [0u8; 8];
        salt[..4].copy_from_slice(&bus.reg(REG_SALT_HI).to_be_bytes());
        salt[4..].copy_from_slice(&bus.reg(REG_SALT_LO).to_be_bytes());
        let seq = bus.reg(REG_SEQ);
        Self {
            enc: GcmCipher::new(&enc),
            dec: GcmCipher::new(&dec),
            spi: bus.reg(REG_SPI).to_be_bytes(),
            salt,
            tx_seq: seq.wrapping_add(1),
            rx_top: seq,
            rx_seen: 0,
        }
    }

    pub fn from_sa(sa: &kyberlink_crypto::handshake::SaParams, initiator: bool) -> Self {
        let (enc_key, dec_key) = if initiator {
            (&sa.sk_ei, &sa.sk_er)
        } else {
            (&sa.sk_er, &sa.sk_ei)
        };
        let mut salt = [0u8; 8];
        salt.copy_from_slice(&sa.sa_salt[..8]);
        Self {
            enc: GcmCipher::new(enc_key),
            dec: GcmCipher::new(dec_key),
            spi: sa.spi_i.to_be_bytes(),
            salt,
            tx_seq: 1,
            rx_top: 0,
            rx_seen: 0,
        }
    }

    pub fn spi(&self) -> u32 {
        u32::from_be_bytes(self.spi)
    }

    pub fn tx_seq(&self) -> u32 {
        self.tx_seq
    }

    fn pad_len_for(inner_len: usize) -> usize {
        const BLOCK: usize = 16;
        (BLOCK - ((inner_len + PAD_TRAILER) % BLOCK)) % BLOCK
    }

    fn nonce(&self, seq: u32) -> [u8; 12] {
        let mut n = [0u8; 12];
        n[..4].copy_from_slice(&seq.to_be_bytes());
        n[4..].copy_from_slice(&self.salt);
        n
    }

    fn aad(spi: &[u8], seq: &[u8]) -> [u8; 8] {
        let mut a = [0u8; 8];
        a[..4].copy_from_slice(spi);
        a[4..8].copy_from_slice(seq);
        a
    }

    pub fn seal(&mut self, inner: &[u8], out: &mut [u8]) -> Option<usize> {
        let seq = self.tx_seq;
        self.tx_seq = self.tx_seq.wrapping_add(1);
        self.seal_at(seq, inner, out)
    }

    pub fn seal_at(&mut self, seq: u32, inner: &[u8], out: &mut [u8]) -> Option<usize> {
        if inner.len() > MAX_INNER || out.len() < inner.len() + HEADER + TAG {
            return None;
        }
        out[..4].copy_from_slice(&self.spi);
        out[4..8].copy_from_slice(&seq.to_be_bytes());
        out[8..12].copy_from_slice(&seq.to_be_bytes());
        out[12..HEADER].copy_from_slice(&self.salt);
        let inner_len = inner.len();
        out[HEADER..HEADER + inner_len].copy_from_slice(inner);
        let pad_len = Self::pad_len_for(inner_len);
        let body_len = inner_len + pad_len + PAD_TRAILER;
        if HEADER + body_len + TAG > out.len() {
            return None;
        }
        let body = HEADER..HEADER + body_len;
        out[body.start + inner_len..body.start + inner_len + pad_len].fill(pad_len as u8);
        out[body.start + inner_len + pad_len] = pad_len as u8;
        out[body.start + inner_len + pad_len + 1] = PAD_MARKER;
        let nonce = self.nonce(seq);
        let aad = Self::aad(&out[..4], &out[4..8]);
        let mut tag = [0u8; TAG];
        self.enc
            .encrypt_in_place(&nonce, &aad, &mut out[body], &mut tag)
            .ok()?;
        out[HEADER + body_len..HEADER + body_len + TAG].copy_from_slice(&tag);
        Some(HEADER + body_len + TAG)
    }

    pub fn open(&mut self, packet: &[u8], out: &mut [u8]) -> Option<usize> {
        if packet.len() < HEADER + TAG {
            return None;
        }
        let seq = u32::from_be_bytes(packet[4..8].try_into().ok()?);
        let n = packet.len() - HEADER - TAG;
        if n > out.len() {
            return None;
        }
        out[..n].copy_from_slice(&packet[HEADER..HEADER + n]);
        let nonce: [u8; 12] = packet[8..HEADER].try_into().ok()?;
        let aad = Self::aad(&packet[..4], &packet[4..8]);
        let tag: [u8; TAG] = packet[HEADER + n..].try_into().ok()?;
        self.dec
            .decrypt_in_place(&nonce, &aad, &mut out[..n], &tag)
            .ok()?;
        if !self.accept(seq) {
            return None;
        }
        if n <= PAD_TRAILER {
            return None;
        }
        let pad_len = out[n - PAD_TRAILER] as usize;
        if out[n - 1] != PAD_MARKER || pad_len > MAX_PAD || n < pad_len + PAD_TRAILER + 1 {
            return None;
        }
        Some(n - PAD_TRAILER - pad_len)
    }

    fn accept(&mut self, seq: u32) -> bool {
        if seq > self.rx_top {
            let shift = seq - self.rx_top;
            self.rx_seen = if shift >= WINDOW {
                1
            } else {
                (self.rx_seen << shift) | 1
            };
            self.rx_top = seq;
            return true;
        }
        let back = self.rx_top - seq;
        if back >= WINDOW {
            return false;
        }
        if self.rx_seen == 0 && seq == self.rx_top {
            self.rx_seen = 1;
            return true;
        }
        let bit = 1u64 << back;
        if self.rx_seen & bit != 0 {
            return false;
        }
        self.rx_seen |= bit;
        true
    }
}
