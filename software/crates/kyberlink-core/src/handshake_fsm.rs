use core::cell::RefCell;

use kyberlink_crypto::handshake as hs;
use kyberlink_crypto::kem_internal::EK_LEN;
use kyberlink_crypto::mldsa_internal::{VerifyPrecomp, VK_LEN};

use crate::cfg_msg::Binding;

pub trait SpiBus {
    fn write_reg(&self, addr: u8, data: u32);
    fn read_reg(&self, addr: u8) -> u32;
}

pub const REG_CTRL: u8 = 0x00;
pub const REG_STATUS: u8 = 0x04;
pub const REG_SPI: u8 = 0x08;
pub const REG_SALT_LO: u8 = 0x0C;
pub const REG_SALT_HI: u8 = 0x10;
pub const REG_SRC_IP: u8 = 0x14;
pub const REG_DST_IP: u8 = 0x18;
pub const REG_SRC_PORT: u8 = 0x1C;
pub const REG_DST_PORT: u8 = 0x20;
pub const REG_SRC_MAC_LO: u8 = 0x24;
pub const REG_SRC_MAC_HI: u8 = 0x28;
pub const REG_DST_MAC_LO: u8 = 0x2C;
pub const REG_DST_MAC_HI: u8 = 0x30;
pub const REG_HSK_RX_LEN: u8 = 0x34;
pub const REG_HSK_RX_DATA: u8 = 0x38;
pub const REG_HSK_TX_LEN: u8 = 0x3C;
pub const REG_HSK_TX_DATA: u8 = 0x40;
pub const REG_KEY_ENC: u8 = 0x44;
pub const REG_ERR: u8 = 0x50;
pub const REG_KEY_DEC: u8 = 0x64;
pub const REG_SEQ: u8 = 0x74;

const CTRL_KEY_LOAD: u32 = 1 << 0;
const CTRL_HSK_SEND: u32 = 1 << 1;
const STATUS_RX_PENDING: u32 = 1 << 0;
const STATUS_TX_BUSY: u32 = 1 << 1;

pub struct Config<I: hs::Identity> {
    pub peer_fp: [u8; 32],
    pub seeds: CriticalSectionMutex<RefCell<kyberlink_crypto::entropy::KemSeeds>>,
    pub identity: I,
}

impl<I: hs::Identity> Config<I> {
    pub fn from_parts(
        binding: &Binding,
        seeds: kyberlink_crypto::entropy::KemSeeds,
        identity: I,
    ) -> Config<I> {
        Config {
            peer_fp: binding.peer_fp,
            seeds: CriticalSectionMutex::new(RefCell::new(seeds)),
            identity,
        }
    }
}

pub fn write_data_plane<S: SpiBus>(spi: &S, b: &Binding) {
    spi.write_reg(REG_SRC_IP, u32::from_be_bytes(b.src_ip));
    spi.write_reg(REG_DST_IP, u32::from_be_bytes(b.dst_ip));
    spi.write_reg(REG_SRC_PORT, b.src_port as u32);
    spi.write_reg(REG_DST_PORT, b.dst_port as u32);
    spi.write_reg(REG_SRC_MAC_LO, mac_lo(&b.src_mac));
    spi.write_reg(REG_SRC_MAC_HI, mac_hi(&b.src_mac));
    spi.write_reg(REG_DST_MAC_LO, mac_lo(&b.dst_mac));
    spi.write_reg(REG_DST_MAC_HI, mac_hi(&b.dst_mac));
}

fn mac_lo(m: &[u8; 6]) -> u32 {
    u32::from_be_bytes([m[2], m[3], m[4], m[5]])
}

fn mac_hi(m: &[u8; 6]) -> u32 {
    u16::from_be_bytes([m[0], m[1]]) as u32
}

pub fn write_sa<S: SpiBus>(spi: &S, sa: &hs::SaParams, initiator: bool, seq: u32) {
    let (enc_key, dec_key) = if initiator {
        (&sa.sk_ei, &sa.sk_er)
    } else {
        (&sa.sk_er, &sa.sk_ei)
    };
    spi.write_reg(REG_SPI, sa.spi_i);
    for (i, k) in enc_key.chunks(4).enumerate() {
        let w = u32::from_be_bytes([k[0], k[1], k[2], k[3]]);
        spi.write_reg(REG_KEY_ENC + i as u8, w);
    }
    for (i, k) in dec_key.chunks(4).enumerate() {
        let w = u32::from_be_bytes([k[0], k[1], k[2], k[3]]);
        spi.write_reg(REG_KEY_DEC + i as u8, w);
    }
    let s = u64::from_be_bytes([
        sa.sa_salt[0],
        sa.sa_salt[1],
        sa.sa_salt[2],
        sa.sa_salt[3],
        sa.sa_salt[4],
        sa.sa_salt[5],
        sa.sa_salt[6],
        sa.sa_salt[7],
    ]);
    spi.write_reg(REG_SALT_LO, (s & 0xFFFF_FFFF) as u32);
    spi.write_reg(REG_SALT_HI, (s >> 32) as u32);
    spi.write_reg(REG_SEQ, seq - 1);
    spi.write_reg(REG_CTRL, CTRL_KEY_LOAD);
}

pub const HSK_CHUNK: usize = 1004;
pub const HSK_ACK: u32 = 0xFFFF_FFFF;
pub const HSK_ACK_RETRY: u32 = 200;

fn hsk_send_blk<S: SpiBus>(spi: &S, total: u32, off: usize, blk: &[u8]) {
    let words = blk.len().div_ceil(4) + 2;
    spi.write_reg(REG_HSK_TX_LEN, (words * 4) as u32);
    let mut w = [0u8; 4];
    w.copy_from_slice(&total.to_be_bytes());
    spi.write_reg(REG_HSK_TX_DATA, u32::from_be_bytes(w));
    w.copy_from_slice(&(off as u32).to_be_bytes());
    spi.write_reg(REG_HSK_TX_DATA, u32::from_be_bytes(w));
    for chunk in blk.chunks(4) {
        let mut b = [0u8; 4];
        b[..chunk.len()].copy_from_slice(chunk);
        spi.write_reg(REG_HSK_TX_DATA, u32::from_be_bytes(b));
    }
    spi.write_reg(REG_CTRL, CTRL_HSK_SEND);
}

fn hsk_send_ack<S: SpiBus>(spi: &S, off: usize) {
    spi.write_reg(REG_HSK_TX_LEN, 8);
    spi.write_reg(REG_HSK_TX_DATA, HSK_ACK);
    spi.write_reg(REG_HSK_TX_DATA, off as u32);
    spi.write_reg(REG_CTRL, CTRL_HSK_SEND);
}

pub struct TxJob {
    msg: [u8; HSK_MAX_MSG],
    len: usize,
    off: usize,
    wait_off: Option<usize>,
    wait_ms: u32,
}

pub const HSK_MAX_MSG: usize = 6528;

impl TxJob {
    pub fn new(msg: &[u8]) -> Self {
        let mut j = TxJob {
            msg: [0u8; HSK_MAX_MSG],
            len: msg.len(),
            off: 0,
            wait_off: None,
            wait_ms: 0,
        };
        j.msg[..msg.len()].copy_from_slice(msg);
        j
    }
    pub fn done(&self) -> bool {
        self.off >= self.len && self.wait_off.is_none()
    }
}

const TX_ACK_TIMEOUT_MS: u32 = 120;
const PHASE_TIMEOUT_MS: u32 = 30000;
const TX_TOTAL_TIMEOUT_MS: u32 = 8000;
const PHASE_DONE: u8 = 3;

pub fn hsk_tx_step<S: SpiBus>(spi: &S, j: &mut TxJob, rx: &mut RxSink, elapsed_ms: u32) {
    if !wait_ack(spi, j, rx, elapsed_ms) {
        return;
    }
    if j.off >= j.len || spi.read_reg(REG_STATUS) & STATUS_TX_BUSY != 0 {
        return;
    }
    send_chunk(spi, j);
}

fn wait_ack<S: SpiBus>(spi: &S, j: &mut TxJob, rx: &mut RxSink, elapsed_ms: u32) -> bool {
    let Some(want) = j.wait_off else {
        return true;
    };
    let mut progressed = false;
    if let Some(off) = rx.take_ack() {
        if off == want {
            j.wait_off = None;
            j.wait_ms = 0;
            progressed = true;
        }
    } else if let Some(blk) = rx.take_block(spi) {
        if blk.ack_off == Some(want) {
            j.wait_off = None;
            j.wait_ms = 0;
            progressed = true;
        } else if blk.data_off.is_some() {
            rx.stash(blk);
            progressed = true;
        }
    }
    if !progressed {
        j.wait_ms = j.wait_ms.saturating_add(elapsed_ms);
    }
    if j.wait_off.is_some() {
        if j.wait_ms >= TX_ACK_TIMEOUT_MS {
            j.wait_ms = 0;
            j.off = want;
            j.wait_off = None;
            return true;
        }
        return false;
    }
    true
}

fn send_chunk<S: SpiBus>(spi: &S, j: &mut TxJob) {
    let end = core::cmp::min(j.off + HSK_CHUNK, j.len);
    hsk_send_blk(spi, j.len as u32, j.off, &j.msg[j.off..end]);
    j.wait_off = Some(j.off);
    j.off = end;
    j.wait_ms = 0;
}

pub struct HskBlock {
    pub total: u32,
    pub off: usize,
    pub ack_off: Option<usize>,
    pub data_off: Option<usize>,
    pub len: usize,
    pub data: [u8; HSK_CHUNK],
}

pub struct RxSink {
    pending: Option<HskBlock>,
    ack_seen: Option<usize>,
}

impl Default for RxSink {
    fn default() -> Self {
        Self::new()
    }
}

impl RxSink {
    pub const fn new() -> Self {
        RxSink {
            pending: None,
            ack_seen: None,
        }
    }

    fn stash(&mut self, b: HskBlock) {
        self.pending = Some(b);
    }

    fn note_ack(&mut self, off: usize) {
        self.ack_seen = Some(off);
    }

    fn take_ack(&mut self) -> Option<usize> {
        self.ack_seen.take()
    }

    pub fn take_block<S: SpiBus>(&mut self, spi: &S) -> Option<HskBlock> {
        if let Some(b) = self.pending.take() {
            return Some(b);
        }
        if spi.read_reg(REG_STATUS) & STATUS_RX_PENDING == 0 {
            return None;
        }
        let len = (spi.read_reg(REG_HSK_RX_LEN) & 0xFFFF) as usize;
        if len < 8 {
            drain_words(spi, len.div_ceil(4));
            return None;
        }
        let mut hdr = [0u8; 8];
        read_bytes(spi, &mut hdr);
        let total = u32::from_be_bytes([hdr[0], hdr[1], hdr[2], hdr[3]]);
        let off = u32::from_be_bytes([hdr[4], hdr[5], hdr[6], hdr[7]]) as usize;
        let mut blk = HskBlock::new(total, off);
        if total == HSK_ACK {
            blk.ack_off = Some(off);
            return Some(blk);
        }
        blk.data_off = Some(off);
        blk.len = read_body(spi, len - 8, &mut blk.data);
        Some(blk)
    }
}

impl HskBlock {
    fn new(total: u32, off: usize) -> HskBlock {
        HskBlock {
            total,
            off,
            ack_off: None,
            data_off: None,
            len: 0,
            data: [0u8; HSK_CHUNK],
        }
    }
}

fn read_word<S: SpiBus>(spi: &S) -> u32 {
    spi.read_reg(REG_HSK_RX_DATA)
}

fn drain_words<S: SpiBus>(spi: &S, words: usize) {
    for _ in 0..words {
        read_word(spi);
    }
}

fn read_bytes<S: SpiBus>(spi: &S, out: &mut [u8]) {
    let mut n = 0;
    while n < out.len() {
        let word = read_word(spi).to_be_bytes();
        let take = core::cmp::min(4, out.len() - n);
        out[n..n + take].copy_from_slice(&word[..take]);
        n += take;
    }
}

fn read_body<S: SpiBus>(spi: &S, body: usize, out: &mut [u8; HSK_CHUNK]) -> usize {
    let mut read = 0;
    let mut stored = 0;
    while read < body {
        let word = read_word(spi).to_be_bytes();
        let take = core::cmp::min(4, body - read);
        if stored < HSK_CHUNK {
            let end = core::cmp::min(stored + take, HSK_CHUNK);
            out[stored..end].copy_from_slice(&word[..end - stored]);
            stored = end;
        }
        read += take;
    }
    stored
}

fn hsk_recv<S: SpiBus>(
    spi: &S,
    rx: &mut RxSink,
    buf: &mut [u8],
    ack_out: &mut Option<usize>,
) -> usize {
    let mut got = 0usize;
    let mut total = 0usize;
    loop {
        let Some(blk) = rx.take_block(spi) else {
            return if got > 0 && got >= total { got } else { 0 };
        };
        if let Some(off) = blk.ack_off {
            rx.note_ack(off);
            continue;
        }
        let Some(end) = place_block(&blk, buf) else {
            return 0;
        };
        got = core::cmp::max(got, end);
        if blk.total != 0 {
            total = blk.total as usize;
        }
        *ack_out = Some(blk.data_off.unwrap_or(0));
        if total != 0 && got >= total {
            return total;
        }
    }
}

fn place_block(blk: &HskBlock, buf: &mut [u8]) -> Option<usize> {
    let ofs = blk.data_off?;
    if ofs > buf.len() || blk.len > buf.len() - ofs || blk.total as usize > buf.len() {
        return None;
    }
    buf[ofs..ofs + blk.len].copy_from_slice(&blk.data[..blk.len]);
    Some(ofs + blk.len)
}

use embassy_sync::blocking_mutex::CriticalSectionMutex;

pub enum FsmOutcome {
    Sa(hs::SaParams),
    Wait,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Role {
    Undecided,
    Initiator,
    Responder,
}

#[allow(clippy::large_enum_variant)]
pub enum Session {
    Initiator(hs::InitiatorState),
    Responder(hs::ResponderState),
}

pub struct Fsm<S: SpiBus, I: hs::Identity> {
    pub cfg: Config<I>,
    pub spi: S,
    pub role: Role,
    pub self_fp: [u8; 32],
    pub session: Option<Session>,
    pub spi_i: u32,
    pub phase: u8,
    pub buf: [u8; 6528],
    pub pc_vk: [u8; VK_LEN],
    pub tx: Option<TxJob>,
    pub rx: RxSink,
    pub ack_pend: Option<usize>,
    pub phase_ms: u32,
    pub tx_total_ms: u32,
    pub pending_sa: Option<hs::SaParams>,
}

static PC_CACHE: CriticalSectionMutex<RefCell<Option<VerifyPrecomp>>> =
    CriticalSectionMutex::new(RefCell::new(None));

impl<S: SpiBus, I: hs::Identity> Fsm<S, I> {
    pub fn new(cfg: Config<I>, spi: S) -> Self {
        Fsm {
            self_fp: hs::fingerprint(cfg.identity.vk()),
            cfg,
            spi,
            role: Role::Undecided,
            session: None,
            spi_i: 0,
            phase: 0,
            buf: [0; 6528],
            pc_vk: [0; VK_LEN],
            tx: None,
            rx: RxSink::new(),
            ack_pend: None,
            phase_ms: 0,
            tx_total_ms: 0,
            pending_sa: None,
        }
    }

    pub fn reseed(&mut self, seeds: kyberlink_crypto::entropy::KemSeeds) {
        self.cfg.seeds.lock(|s| *s.borrow_mut() = seeds);
        self.reset_session();
        self.spi_i = 0;
        self.tx_total_ms = 0;
    }

    fn ensure_pc(&mut self, vk: &[u8]) {
        let vk_hash = hs::fingerprint(vk);
        let need = PC_CACHE.lock(|s| match s.borrow().as_ref() {
            Some(pc) => pc.vk_hash != vk_hash,
            None => true,
        });
        if need {
            let mut vk_arr = [0u8; VK_LEN];
            vk_arr.copy_from_slice(vk);
            PC_CACHE.lock(|s| {
                let mut binding = s.borrow_mut();
                let pc = binding.get_or_insert_default();
                kyberlink_crypto::mldsa_internal::verify_precomp_new_into(pc, &vk_arr);
            });
        }
    }

    pub fn poll(&mut self) -> FsmOutcome {
        self.poll_ms(1)
    }

    pub fn poll_ms(&mut self, elapsed_ms: u32) -> FsmOutcome {
        if let Some(off) = self.ack_pend.take() {
            hsk_send_ack(&self.spi, off);
        }
        if self.advance_tx(elapsed_ms) {
            self.reset_session();
            return FsmOutcome::Wait;
        }
        if self.tx.is_none() {
            if let Some(sa) = self.pending_sa.take() {
                self.phase = PHASE_DONE;
                self.phase_ms = 0;
                return FsmOutcome::Sa(sa);
            }
        }
        if self.phase != PHASE_DONE && self.phase_expired(elapsed_ms) {
            self.reset_session();
            return FsmOutcome::Wait;
        }
        if self.phase == PHASE_DONE {
            return self.poll_done();
        }
        match self.role {
            Role::Initiator => self.poll_initiator(),
            Role::Responder => self.poll_responder(),
            Role::Undecided => self.poll_undecided(),
        }
    }

    fn poll_done(&mut self) -> FsmOutcome {
        let Some(n) = self.recv_msg() else {
            return FsmOutcome::Wait;
        };
        if n != hs::M1_LEN {
            return FsmOutcome::Wait;
        }
        self.accept_m1(n)
    }

    fn poll_undecided(&mut self) -> FsmOutcome {
        if self.tx.is_some() {
            return FsmOutcome::Wait;
        }
        if let Some(n) = self.recv_msg() {
            if n == hs::M1_LEN {
                return self.accept_m1(n);
            }
            return FsmOutcome::Wait;
        }
        self.initiator_start()
    }

    fn advance_tx(&mut self, elapsed_ms: u32) -> bool {
        let Some(j) = self.tx.as_mut() else {
            self.tx_total_ms = 0;
            return false;
        };
        hsk_tx_step(&self.spi, j, &mut self.rx, elapsed_ms);
        self.tx_total_ms = self.tx_total_ms.saturating_add(elapsed_ms);
        if j.done() {
            self.tx = None;
            self.tx_total_ms = 0;
            return false;
        }
        if self.tx_total_ms >= TX_TOTAL_TIMEOUT_MS {
            self.tx = None;
            self.tx_total_ms = 0;
            return true;
        }
        false
    }

    fn phase_expired(&mut self, elapsed_ms: u32) -> bool {
        self.phase_ms = self.phase_ms.saturating_add(elapsed_ms);
        self.phase_ms >= PHASE_TIMEOUT_MS && self.tx.is_none()
    }

    fn reset_session(&mut self) {
        self.pending_sa = None;
        self.phase = 0;
        self.phase_ms = 0;
        self.role = Role::Undecided;
        self.session = None;
        self.tx = None;
        self.rx = RxSink::new();
        self.ack_pend = None;
        self.buf = [0u8; HSK_MAX_MSG];
    }

    fn enter_phase(&mut self, phase: u8) {
        self.phase = phase;
        self.phase_ms = 0;
    }

    fn recv_msg(&mut self) -> Option<usize> {
        let mut ack = None;
        let n = hsk_recv(&self.spi, &mut self.rx, &mut self.buf, &mut ack);
        if ack.is_some() {
            self.ack_pend = ack;
        }
        (n > 0).then_some(n)
    }

    fn capture_peer_vk(&mut self) {
        self.pc_vk
            .copy_from_slice(&self.buf[32 + EK_LEN..32 + EK_LEN + VK_LEN]);
    }

    fn poll_initiator(&mut self) -> FsmOutcome {
        match self.phase {
            0 => self.initiator_start(),
            1 => self.initiator_recv_m2(),
            _ => self.initiator_recv_m4(),
        }
    }

    fn initiator_start(&mut self) -> FsmOutcome {
        let (seed_d, seed_z, nonce) = self.cfg.seeds.lock(|s| {
            let s = s.borrow();
            (s.d, s.z, s.nonce)
        });
        let (st, m1) = hs::initiator_start(&self.cfg.identity, &seed_d, &seed_z, &nonce);
        self.role = Role::Initiator;
        self.session = Some(Session::Initiator(st));
        self.tx = Some(TxJob::new(&m1));
        self.enter_phase(1);
        FsmOutcome::Wait
    }

    fn initiator_recv_m2(&mut self) -> FsmOutcome {
        let Some(n) = self.recv_msg() else {
            return FsmOutcome::Wait;
        };
        if n == hs::M1_LEN && self.self_fp > self.cfg.peer_fp {
            return self.accept_m1(n);
        }
        if n != hs::M2_LEN {
            return FsmOutcome::Wait;
        }
        self.capture_peer_vk();
        if hs::fingerprint(&self.pc_vk) != self.cfg.peer_fp {
            return FsmOutcome::Wait;
        }
        let vk = self.pc_vk;
        self.ensure_pc(&vk);
        let Session::Initiator(st) = self.session.as_mut().unwrap() else {
            return FsmOutcome::Wait;
        };
        PC_CACHE.lock(|s| {
            match hs::initiator_recv_m2(
                st,
                &self.cfg.identity,
                &self.buf[..n],
                &self.cfg.peer_fp,
                s.borrow().as_ref(),
            ) {
                Ok((m3, spi_i)) => {
                    self.spi_i = spi_i;
                    self.tx = Some(TxJob::new(&m3));
                    self.phase = 2;
                    self.phase_ms = 0;
                    FsmOutcome::Wait
                }
                Err(_) => {
                    self.phase = 0;
                    FsmOutcome::Wait
                }
            }
        })
    }

    fn initiator_recv_m4(&mut self) -> FsmOutcome {
        let Some(n) = self.recv_msg() else {
            return FsmOutcome::Wait;
        };
        if n != hs::M4_LEN {
            return FsmOutcome::Wait;
        }
        let vk = self.pc_vk;
        self.ensure_pc(&vk);
        let Session::Initiator(st) = self.session.as_mut().unwrap() else {
            return FsmOutcome::Wait;
        };
        PC_CACHE.lock(
            |s| match hs::initiator_recv_m4(st, &self.buf[..n], self.spi_i, s.borrow().as_ref()) {
                Ok(sa) => {
                    self.pending_sa = Some(sa);
                    FsmOutcome::Wait
                }
                Err(_) => {
                    self.phase = 0;
                    FsmOutcome::Wait
                }
            },
        )
    }

    fn poll_responder(&mut self) -> FsmOutcome {
        if self.phase == 0 {
            self.responder_recv_m1()
        } else {
            self.responder_recv_m3()
        }
    }

    fn responder_recv_m1(&mut self) -> FsmOutcome {
        let Some(n) = self.recv_msg() else {
            return FsmOutcome::Wait;
        };
        if n != hs::M1_LEN {
            return FsmOutcome::Wait;
        }
        self.accept_m1(n)
    }

    fn accept_m1(&mut self, n: usize) -> FsmOutcome {
        self.capture_peer_vk();
        if hs::fingerprint(&self.pc_vk) != self.cfg.peer_fp {
            return FsmOutcome::Wait;
        }
        let vk = self.pc_vk;
        self.ensure_pc(&vk);
        let (seed_d, seed_z, nonce) = self.cfg.seeds.lock(|s| {
            let s = s.borrow();
            (s.d, s.z, s.nonce)
        });
        match hs::responder_start(
            &self.cfg.identity,
            &seed_d,
            &seed_z,
            &nonce,
            &self.buf[..n],
            &self.cfg.peer_fp,
        ) {
            Ok((st, m2)) => {
                self.role = Role::Responder;
                self.pending_sa = None;
                self.rx = RxSink::new();
                self.session = Some(Session::Responder(st));
                self.tx = Some(TxJob::new(&m2));
                self.enter_phase(1);
                FsmOutcome::Wait
            }
            Err(_) => FsmOutcome::Wait,
        }
    }

    fn responder_recv_m3(&mut self) -> FsmOutcome {
        let Some(n) = self.recv_msg() else {
            return FsmOutcome::Wait;
        };
        if n != hs::M3_LEN {
            return FsmOutcome::Wait;
        }
        let mut sb = [0u8; 4];
        sb.copy_from_slice(&self.buf[hs::SPI_OFF..hs::SPI_OFF + 4]);
        self.spi_i = u32::from_be_bytes(sb);
        let vk = self.pc_vk;
        self.ensure_pc(&vk);
        let Session::Responder(st) = self.session.as_mut().unwrap() else {
            return FsmOutcome::Wait;
        };
        PC_CACHE.lock(|s| {
            match hs::responder_recv_m3(
                st,
                &self.cfg.identity,
                &self.buf[..n],
                self.spi_i,
                s.borrow().as_ref(),
            ) {
                Ok((m4, sa)) => {
                    self.tx = Some(TxJob::new(&m4));
                    self.pending_sa = Some(sa);
                    FsmOutcome::Wait
                }
                Err(_) => {
                    self.phase = 0;
                    FsmOutcome::Wait
                }
            }
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use core::cell::RefCell;
    use kyberlink_crypto::mldsa_internal::sign_precomp_new_into;

    struct MockSpi {
        regs: RefCell<[u32; 128]>,
        tx_buf: RefCell<Vec<u8>>,
        outbox: RefCell<Vec<Vec<u8>>>,
        blocks: RefCell<Vec<(usize, Vec<u32>)>>,
    }

    impl MockSpi {
        fn new() -> Self {
            MockSpi {
                regs: RefCell::new([0; 128]),
                tx_buf: RefCell::new(Vec::new()),
                outbox: RefCell::new(Vec::new()),
                blocks: RefCell::new(Vec::new()),
            }
        }

        fn w(&self, addr: u8) -> u32 {
            self.regs.borrow()[addr as usize]
        }

        fn pump(&self, dst: &MockSpi) {
            self.deliver(dst);
            let blocks: Vec<Vec<u8>> = dst.outbox.borrow_mut().drain(..).collect();
            for payload in blocks {
                let mut words = Vec::new();
                for chunk in payload.chunks(4) {
                    let mut b = [0u8; 4];
                    b[..chunk.len()].copy_from_slice(chunk);
                    words.push(u32::from_be_bytes(b));
                }
                self.blocks.borrow_mut().push((payload.len(), words));
            }
        }

        fn deliver(&self, dst: &MockSpi) {
            let blocks: Vec<Vec<u8>> = self.outbox.borrow_mut().drain(..).collect();
            for payload in blocks {
                let mut words = Vec::new();
                for chunk in payload.chunks(4) {
                    let mut b = [0u8; 4];
                    b[..chunk.len()].copy_from_slice(chunk);
                    words.push(u32::from_be_bytes(b));
                }
                dst.blocks.borrow_mut().push((payload.len(), words));
            }
        }

        fn push_rx(&self, msg: &[u8]) {
            let total = msg.len() as u32;
            let mut payload = Vec::new();
            payload.extend_from_slice(&total.to_be_bytes());
            payload.extend_from_slice(&0u32.to_be_bytes());
            payload.extend_from_slice(msg);
            let mut words = Vec::new();
            for chunk in payload.chunks(4) {
                let mut b = [0u8; 4];
                b[..chunk.len()].copy_from_slice(chunk);
                words.push(u32::from_be_bytes(b));
            }
            self.blocks.borrow_mut().push((payload.len(), words));
        }
    }

    #[test]
    fn write_data_plane_sets_network_registers() {
        let m = MockSpi::new();
        let b = crate::cfg_msg::Binding {
            peer_fp: [0xAB; 32],
            src_mac: [0x00, 0x11, 0x22, 0x33, 0x44, 0x55],
            dst_mac: [0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB],
            src_ip: [192, 168, 1, 1],
            dst_ip: [192, 168, 1, 2],
            src_port: 4500,
            dst_port: 4501,
        };
        write_data_plane(&m, &b);
        assert_eq!(m.w(REG_SRC_IP), 0xC0A8_0101);
        assert_eq!(m.w(REG_DST_IP), 0xC0A8_0102);
        assert_eq!(m.w(REG_SRC_PORT), 4500);
        assert_eq!(m.w(REG_DST_PORT), 4501);
        assert_eq!(m.w(REG_SRC_MAC_LO), 0x2233_4455);
        assert_eq!(m.w(REG_SRC_MAC_HI), 0x0011);
        assert_eq!(m.w(REG_DST_MAC_LO), 0x8899_AABB);
        assert_eq!(m.w(REG_DST_MAC_HI), 0x6677);
    }

    impl Default for MockSpi {
        fn default() -> Self {
            Self::new()
        }
    }

    impl SpiBus for MockSpi {
        fn write_reg(&self, addr: u8, data: u32) {
            self.regs.borrow_mut()[addr as usize] = data;
            if addr == REG_HSK_TX_DATA {
                self.tx_buf
                    .borrow_mut()
                    .extend_from_slice(&data.to_be_bytes());
            } else if addr == REG_CTRL && data & CTRL_HSK_SEND != 0 {
                let len = self.regs.borrow()[REG_HSK_TX_LEN as usize] as usize;
                let mut q = self.tx_buf.borrow_mut();
                let start = q.len().saturating_sub(len);
                let tail = q[start..].to_vec();
                q.clear();
                self.outbox.borrow_mut().push(tail);
            }
        }

        fn read_reg(&self, addr: u8) -> u32 {
            match addr {
                REG_STATUS => {
                    if self.blocks.borrow().is_empty() {
                        0
                    } else {
                        STATUS_RX_PENDING
                    }
                }
                REG_HSK_RX_LEN => self.blocks.borrow()[0].0 as u32,
                REG_HSK_RX_DATA => {
                    let mut q = self.blocks.borrow_mut();
                    if q[0].1.len() <= 1 {
                        q.remove(0).1[0]
                    } else {
                        q[0].1.remove(0)
                    }
                }
                _ => self.regs.borrow()[addr as usize],
            }
        }
    }

    fn sa() -> hs::SaParams {
        hs::SaParams {
            spi_i: 0x11223344,
            spi_r: 0x55667788,
            sk_ei: core::array::from_fn(|i| i as u8),
            sk_er: core::array::from_fn(|i| 0x80 + i as u8),
            sa_salt: core::array::from_fn(|i| i as u8 + 1),
        }
    }

    fn key_words(k: &[u8]) -> Vec<u32> {
        (0..8)
            .map(|i| u32::from_be_bytes(k[i * 4..i * 4 + 4].try_into().unwrap()))
            .collect()
    }

    #[test]
    fn write_sa_initiator_key_order() {
        let m = MockSpi::default();
        let s = sa();
        write_sa(&m, &s, true, 1);
        let enc = key_words(&s.sk_ei);
        let dec = key_words(&s.sk_er);
        for i in 0..8u8 {
            assert_eq!(m.w(REG_KEY_ENC + i), enc[i as usize]);
            assert_eq!(m.w(REG_KEY_DEC + i), dec[i as usize]);
        }
        assert_eq!(m.w(REG_SPI), s.spi_i);
        assert_eq!(
            m.w(REG_SALT_LO),
            u32::from_be_bytes(s.sa_salt[4..8].try_into().unwrap())
        );
        assert_eq!(
            m.w(REG_SALT_HI),
            u32::from_be_bytes(s.sa_salt[0..4].try_into().unwrap())
        );
        assert_eq!(m.w(REG_CTRL), CTRL_KEY_LOAD);
        assert_eq!(m.w(REG_SEQ), 0);
    }

    #[test]
    fn write_sa_responder_swaps_keys() {
        let a = MockSpi::default();
        let b = MockSpi::default();
        let s = sa();
        write_sa(&a, &s, true, 1);
        write_sa(&b, &s, false, 1);
        for i in 0..8u8 {
            assert_eq!(b.w(REG_KEY_ENC + i), a.w(REG_KEY_DEC + i));
            assert_eq!(b.w(REG_KEY_DEC + i), a.w(REG_KEY_ENC + i));
        }
        assert_eq!(
            b.w(REG_KEY_ENC),
            u32::from_be_bytes(s.sk_er[0..4].try_into().unwrap())
        );
    }

    #[test]
    fn hsk_send_frames_words() {
        let m = MockSpi::default();
        let mut j = TxJob::new(&[1, 2, 3, 4, 5]);
        let mut rx = RxSink::new();
        hsk_tx_step(&m, &mut j, &mut rx, 1);
        assert_eq!(m.w(REG_CTRL), CTRL_HSK_SEND);
        assert_eq!(m.outbox.borrow().len(), 1);
        assert_eq!(
            m.outbox.borrow()[0],
            vec![0, 0, 0, 5, 0, 0, 0, 0, 1, 2, 3, 4, 5, 0, 0, 0]
        );
        assert!(m.tx_buf.borrow().is_empty());
        assert!(!j.done(), "waiting for ack");
        m.blocks.borrow_mut().push((8, vec![HSK_ACK, 0]));
        hsk_tx_step(&m, &mut j, &mut rx, 1);
        assert!(j.done());
    }

    #[test]
    fn hsk_recv_reads_fifo() {
        let m = MockSpi::default();
        let mut rx = RxSink::new();
        let mut ack = None;
        assert_eq!(hsk_recv(&m, &mut rx, &mut [0u8; 16], &mut ack), 0);
        m.push_rx(&[0xAA, 0xBB, 0xCC, 0xDD, 0xEE]);
        let mut buf = [0u8; 16];
        let mut ack = None;
        let n = hsk_recv(&m, &mut rx, &mut buf, &mut ack);
        assert_eq!(n, 5);
        assert_eq!(&buf[..5], &[0xAA, 0xBB, 0xCC, 0xDD, 0xEE]);
        assert_eq!(ack, Some(0));
        assert!(m.blocks.borrow().is_empty());
    }

    use kyberlink_crypto::handshake::Identity as _;

    struct TestIdentity {
        vk: [u8; hs::VK_LEN],
        kk: [u8; hs::KK_LEN],
        tr: [u8; hs::TR_LEN],
        spc: hs::SignPrecomp,
    }

    impl hs::Identity for TestIdentity {
        fn vk(&self) -> &[u8; hs::VK_LEN] {
            &self.vk
        }
        fn kk(&self) -> &[u8; hs::KK_LEN] {
            &self.kk
        }
        fn tr(&self) -> &[u8; hs::TR_LEN] {
            &self.tr
        }
        fn spc(&self) -> &hs::SignPrecomp {
            &self.spc
        }
    }

    static IDENTITY_I: std::sync::OnceLock<TestIdentity> = std::sync::OnceLock::new();
    static IDENTITY_R: std::sync::OnceLock<TestIdentity> = std::sync::OnceLock::new();

    fn cfg_of(
        peer_fp: [u8; 32],
        d: u8,
        z: u8,
        nonce: u8,
        identity: &'static TestIdentity,
    ) -> Config<&'static TestIdentity> {
        Config {
            peer_fp,
            seeds: CriticalSectionMutex::new(RefCell::new(kyberlink_crypto::entropy::KemSeeds {
                d: [d; 32],
                z: [z; 32],
                nonce: [nonce; 32],
            })),
            identity,
        }
    }

    fn identity_i() -> &'static TestIdentity {
        IDENTITY_I.get_or_init(|| {
            let (vk, sk) = kyberlink_crypto::mldsa_internal::keygen_internal(&[3u8; 32]);
            let mut spc = hs::SignPrecomp::default();
            sign_precomp_new_into(&mut spc, &sk);
            TestIdentity {
                vk,
                kk: hs::kk_of(&sk),
                tr: hs::tr_of(&sk),
                spc,
            }
        })
    }

    fn identity_r() -> &'static TestIdentity {
        IDENTITY_R.get_or_init(|| {
            let (vk, sk) = kyberlink_crypto::mldsa_internal::keygen_internal(&[7u8; 32]);
            let mut spc = hs::SignPrecomp::default();
            sign_precomp_new_into(&mut spc, &sk);
            TestIdentity {
                vk,
                kk: hs::kk_of(&sk),
                tr: hs::tr_of(&sk),
                spc,
            }
        })
    }

    #[test]
    #[cfg_attr(miri, ignore)]
    fn fsm_end_to_end_handshake() {
        let id_i = identity_i();
        let id_r = identity_r();
        let fp_i = id_i.fingerprint();
        let fp_r = id_r.fingerprint();

        let cfg_i = cfg_of(fp_r, 1, 2, 4, id_i);
        let cfg_r = cfg_of(fp_i, 5, 6, 8, id_r);
        let mut fi = Fsm::new(cfg_i, MockSpi::default());
        let mut fr = Fsm::new(cfg_r, MockSpi::default());
        let mut sa_i = None;
        let mut sa_r = None;
        for _ in 0..400 {
            match fi.poll() {
                FsmOutcome::Sa(sa) => sa_i = Some(sa),
                FsmOutcome::Wait => {}
            }
            fi.spi.pump(&fr.spi);
            match fr.poll() {
                FsmOutcome::Sa(sa) => sa_r = Some(sa),
                FsmOutcome::Wait => {}
            }
            fr.spi.pump(&fi.spi);
            if let (Some(a), Some(b)) = (&sa_i, &sa_r) {
                assert_eq!(a.spi_i, b.spi_i);
                assert_eq!(a.spi_r, b.spi_r);
                assert_eq!(a.sk_ei, b.sk_ei);
                assert_eq!(a.sk_er, b.sk_er);
                assert_eq!(a.sa_salt, b.sa_salt);
                break;
            }
        }
        assert!(sa_i.is_some() && sa_r.is_some(), "handshake did not complete");
        fi.spi.outbox.borrow_mut().clear();
        fr.spi.outbox.borrow_mut().clear();
        for _ in 0..100 {
            assert!(matches!(fi.poll(), FsmOutcome::Wait));
            assert!(matches!(fr.poll(), FsmOutcome::Wait));
        }
        assert!(fi.spi.outbox.borrow().is_empty(), "initiator restarted after sa");
        assert!(fr.spi.outbox.borrow().is_empty(), "responder restarted after sa");
    }

    #[test]
    #[cfg_attr(miri, ignore)]
    fn initiator_bad_m2_restarts() {
        let cfg = cfg_of([9u8; 32], 1, 2, 4, identity_i());
        let mut f = Fsm::new(cfg, MockSpi::default());
        for _ in 0..4 {
            let _ = f.poll();
        }
        let m1 = f.spi.outbox.borrow()[0].clone();
        assert_eq!(m1[0..4], [0, 0, 12, 96], "m1 chunk header (3168B total)");
        f.spi.outbox.borrow_mut().clear();
        f.spi.push_rx(&[0xEE; 64]);
        for _ in 0..400 {
            let _ = f.poll();
        }
        let resent = f.spi.outbox.borrow().iter().any(|p| p == &m1);
        assert!(resent, "m1 must be resent after bad m2");
    }

    #[test]
    #[cfg_attr(miri, ignore)]
    fn simultaneous_start_breaks_tie_by_fingerprint() {
        let id_i = identity_i();
        let id_r = identity_r();
        let fp_i = id_i.fingerprint();
        let fp_r = id_r.fingerprint();
        assert_ne!(fp_i, fp_r);
        let cfg_i = cfg_of(fp_r, 1, 2, 4, id_i);
        let cfg_r = cfg_of(fp_i, 5, 6, 8, id_r);
        let mut fi = Fsm::new(cfg_i, MockSpi::default());
        let mut fr = Fsm::new(cfg_r, MockSpi::default());

        for _ in 0..4000 {
            let _ = fi.poll();
            let _ = fr.poll();
            fi.spi.pump(&fr.spi);
            if fi.role != Role::Undecided
                && fr.role != Role::Undecided
                && (fi.role == Role::Initiator) != (fr.role == Role::Initiator)
            {
                break;
            }
        }
        let (want_i, want_r) = if fp_i < fp_r {
            (Role::Initiator, Role::Responder)
        } else {
            (Role::Responder, Role::Initiator)
        };
        assert_eq!(fi.role, want_i, "lower fingerprint must win the tie");
        assert_eq!(fr.role, want_r);
    }
}
