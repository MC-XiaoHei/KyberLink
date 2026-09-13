use kyberlink_crypto::handshake as hs;
use kyberlink_crypto::kem_internal::EK_LEN;
use kyberlink_crypto::mldsa_internal::{VerifyPrecomp, VK_LEN};

pub trait SpiBus {
    /// # Safety
    /// `addr` must be a valid register address.
    unsafe fn write_reg(&self, addr: u8, data: u32);
    /// # Safety
    /// `addr` must be a valid register address.
    unsafe fn read_reg(&self, addr: u8) -> u32;
}

pub const REG_CTRL: u8 = 0x00;
pub const REG_STATUS: u8 = 0x04;
pub const REG_SPI: u8 = 0x08;
pub const REG_SALT_LO: u8 = 0x0C;
pub const REG_SALT_HI: u8 = 0x10;
pub const REG_HSK_RX_LEN: u8 = 0x34;
pub const REG_HSK_RX_DATA: u8 = 0x38;
pub const REG_HSK_TX_LEN: u8 = 0x3C;
pub const REG_HSK_TX_DATA: u8 = 0x40;
pub const REG_KEY_ENC: u8 = 0x44;
pub const REG_KEY_DEC: u8 = 0x64;
pub const REG_SEQ: u8 = 0x74;

const CTRL_KEY_LOAD: u32 = 1 << 0;
const CTRL_HSK_SEND: u32 = 1 << 1;
const STATUS_RX_PENDING: u32 = 1 << 0;
const STATUS_TX_BUSY: u32 = 1 << 1;

pub struct Config {
    pub role_initiator: bool,
    pub peer_fp: [u8; 32],
    pub seed_kem_d: [u8; 32],
    pub seed_kem_z: [u8; 32],
    pub nonce: [u8; 32],
    pub identity: &'static dyn hs::Identity,
}

pub fn write_sa<S: SpiBus>(spi: &S, sa: &hs::SaParams, initiator: bool, seq: u32) {
    unsafe {
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
}

pub const HSK_CHUNK: usize = 1004;
pub const HSK_ACK: u32 = 0xFFFF_FFFF;
pub const HSK_ACK_RETRY: u32 = 200;

fn hsk_send_blk<S: SpiBus>(spi: &S, total: u32, off: usize, blk: &[u8]) {
    let words = blk.len().div_ceil(4) + 2;
    unsafe {
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
}

fn hsk_send_ack<S: SpiBus>(spi: &S, off: usize) {
    unsafe {
        spi.write_reg(REG_HSK_TX_LEN, 8);
        spi.write_reg(REG_HSK_TX_DATA, HSK_ACK);
        spi.write_reg(REG_HSK_TX_DATA, off as u32);
        spi.write_reg(REG_CTRL, CTRL_HSK_SEND);
    }
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

pub fn hsk_tx_step<S: SpiBus>(spi: &S, j: &mut TxJob, rx: &mut RxSink, elapsed_ms: u32) {
    if let Some(want) = j.wait_off {
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
            } else {
                return;
            }
        } else if j.off >= j.len {
            return;
        }
    }
    if j.off >= j.len {
        return;
    }
    if unsafe { spi.read_reg(REG_STATUS) } & STATUS_TX_BUSY != 0 {
        return;
    }
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
    /// 被数据块挡在 FIFO 后面的 ACK，留给发送侧的等待逻辑取用。
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
        let status = unsafe { spi.read_reg(REG_STATUS) };
        if status & STATUS_RX_PENDING == 0 {
            return None;
        }
        let len = (unsafe { spi.read_reg(REG_HSK_RX_LEN) } & 0xFFFF) as usize;
        if len < 8 {
            for _ in 0..len.div_ceil(4) {
                unsafe { spi.read_reg(REG_HSK_RX_DATA) };
            }
            return None;
        }
        let mut hdr = [0u8; 8];
        let mut hn = 0usize;
        while hn < 8 {
            let w = unsafe { spi.read_reg(REG_HSK_RX_DATA) };
            let b = w.to_be_bytes();
            let take = core::cmp::min(4, 8 - hn);
            hdr[hn..hn + take].copy_from_slice(&b[..take]);
            hn += take;
        }
        let tl = u32::from_be_bytes([hdr[0], hdr[1], hdr[2], hdr[3]]);
        let ofs = u32::from_be_bytes([hdr[4], hdr[5], hdr[6], hdr[7]]) as usize;
        let mut blk = HskBlock {
            total: tl,
            off: ofs,
            ack_off: None,
            data_off: None,
            len: 0,
            data: [0u8; HSK_CHUNK],
        };
        if tl == HSK_ACK {
            blk.ack_off = Some(ofs);
            return Some(blk);
        }
        blk.data_off = Some(ofs);
        let body = len.saturating_sub(8);
        let mut dn = 0usize;
        while dn < body {
            let w = unsafe { spi.read_reg(REG_HSK_RX_DATA) };
            let b = w.to_be_bytes();
            let take = core::cmp::min(4, body - dn);
            if dn < HSK_CHUNK {
                let e = core::cmp::min(dn + take, HSK_CHUNK);
                blk.data[dn..e].copy_from_slice(&b[..e - dn]);
            }
            dn += take;
        }
        blk.len = core::cmp::min(dn, HSK_CHUNK);
        Some(blk)
    }
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
        let blk = match rx.take_block(spi) {
            Some(b) => b,
            None => {
                if got == 0 || got < total {
                    return 0;
                }
                return got;
            }
        };
        if let Some(off) = blk.ack_off {
            rx.note_ack(off);
            continue;
        }
        let ofs = blk.data_off.unwrap_or(0);
        if ofs > buf.len() || blk.len > buf.len() - ofs || blk.total as usize > buf.len() {
            return 0;
        }
        let end = ofs + blk.len;
        buf[ofs..end].copy_from_slice(&blk.data[..blk.len]);
        got = core::cmp::max(got, ofs + blk.len);
        if blk.total != 0 {
            total = blk.total as usize;
        }
        *ack_out = Some(ofs);
        if total != 0 && got >= total {
            return total;
        }
    }
}

use embassy_sync::blocking_mutex::CriticalSectionMutex;

pub enum FsmOutcome {
    Sa(hs::SaParams),
    Wait,
}

// 无堆目标上每个节点只有一份 Session，变体大小差异不带来实际开销
#[allow(clippy::large_enum_variant)]
pub enum Session {
    Initiator(hs::InitiatorState),
    Responder(hs::ResponderState),
}

pub struct Fsm<'a, S: SpiBus> {
    pub cfg: &'a Config,
    pub spi: &'a S,
    pub role_initiator: bool,
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
    /// 握手结果，等最后一帧发完才交给宿主。
    pub pending_sa: Option<hs::SaParams>,
}

static PC_CACHE: CriticalSectionMutex<Option<VerifyPrecomp>> = CriticalSectionMutex::new(None);

impl<'a, S: SpiBus> Fsm<'a, S> {
    pub fn new(cfg: &'a Config, spi: &'a S) -> Self {
        Fsm {
            cfg,
            spi,
            role_initiator: cfg.role_initiator,
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

    fn ensure_pc(&mut self, vk: &[u8]) {
        let vk_hash = hs::fingerprint(vk);
        let need = PC_CACHE.lock(|s| match s.as_ref() {
            Some(pc) => pc.vk_hash != vk_hash,
            None => true,
        });
        if need {
            let mut vk_arr = [0u8; VK_LEN];
            vk_arr.copy_from_slice(vk);
            unsafe {
                PC_CACHE.lock_mut(|s| {
                    let pc = s.get_or_insert_default();
                    kyberlink_crypto::mldsa_internal::verify_precomp_new_into(pc, &vk_arr);
                });
            }
        }
    }

    pub fn poll(&mut self) -> FsmOutcome {
        self.poll_ms(1)
    }

    pub fn poll_ms(&mut self, elapsed_ms: u32) -> FsmOutcome {
        if let Some(off) = self.ack_pend.take() {
            hsk_send_ack(self.spi, off);
        }
        if let Some(j) = self.tx.as_mut() {
            hsk_tx_step(self.spi, j, &mut self.rx, elapsed_ms);
            self.tx_total_ms = self.tx_total_ms.saturating_add(elapsed_ms);
            if j.done() {
                self.tx = None;
                self.tx_total_ms = 0;
            } else if self.tx_total_ms >= TX_TOTAL_TIMEOUT_MS {
                self.tx = None;
                self.tx_total_ms = 0;
                self.pending_sa = None;
                self.phase = 0;
                self.session = None;
                self.phase_ms = 0;
                return FsmOutcome::Wait;
            }
        } else {
            self.tx_total_ms = 0;
        }
        if self.tx.is_none() {
            if let Some(sa) = self.pending_sa.take() {
                self.phase = 0;
                self.phase_ms = 0;
                return FsmOutcome::Sa(sa);
            }
        }
        self.phase_ms = self.phase_ms.saturating_add(elapsed_ms);
        if self.phase_ms >= PHASE_TIMEOUT_MS && self.tx.is_none() {
            self.phase_ms = 0;
            self.phase = 0;
            self.session = None;
            return FsmOutcome::Wait;
        }
        if self.role_initiator {
            self.poll_initiator()
        } else {
            self.poll_responder()
        }
    }

    fn poll_initiator(&mut self) -> FsmOutcome {
        match self.phase {
            0 => {
                let (st, m1) = hs::initiator_start(
                    self.cfg.identity,
                    &self.cfg.seed_kem_d,
                    &self.cfg.seed_kem_z,
                    &self.cfg.nonce,
                );
                self.session = Some(Session::Initiator(st));
                self.tx = Some(TxJob::new(&m1));
                self.phase = 1;
                self.phase_ms = 0;
                FsmOutcome::Wait
            }
            1 => {
                let mut ack = None;
                let n = hsk_recv(self.spi, &mut self.rx, &mut self.buf, &mut ack);
                if ack.is_some() {
                    self.ack_pend = ack;
                }
                if n == 0 {
                    return FsmOutcome::Wait;
                }
                let mut vk_tmp = [0u8; VK_LEN];
                vk_tmp.copy_from_slice(&self.buf[32 + EK_LEN..32 + EK_LEN + VK_LEN]);
                self.pc_vk = vk_tmp;
                let vk = self.pc_vk;
                self.ensure_pc(&vk);
                let Session::Initiator(st) = self.session.as_mut().unwrap() else {
                    return FsmOutcome::Wait;
                };
                PC_CACHE.lock(|s| {
                    match hs::initiator_recv_m2(
                        st,
                        self.cfg.identity,
                        &self.buf[..n],
                        &self.cfg.peer_fp,
                        s.as_ref(),
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
            _ => {
                let mut ack = None;
                let n = hsk_recv(self.spi, &mut self.rx, &mut self.buf, &mut ack);
                if ack.is_some() {
                    self.ack_pend = ack;
                }
                if n == 0 {
                    return FsmOutcome::Wait;
                }
                let vk = self.pc_vk;
                self.ensure_pc(&vk);
                let Session::Initiator(st) = self.session.as_mut().unwrap() else {
                    return FsmOutcome::Wait;
                };
                PC_CACHE.lock(|s| {
                    match hs::initiator_recv_m4(st, &self.buf[..n], self.spi_i, s.as_ref()) {
                        Ok(sa) => {
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
    }

    fn poll_responder(&mut self) -> FsmOutcome {
        match self.phase {
            0 => {
                let mut ack = None;
                let n = hsk_recv(self.spi, &mut self.rx, &mut self.buf, &mut ack);
                if ack.is_some() {
                    self.ack_pend = ack;
                }
                if n == 0 {
                    return FsmOutcome::Wait;
                }
                let mut vk_tmp = [0u8; VK_LEN];
                vk_tmp.copy_from_slice(&self.buf[32 + EK_LEN..32 + EK_LEN + VK_LEN]);
                self.pc_vk = vk_tmp;
                let vk = self.pc_vk;
                self.ensure_pc(&vk);
                match hs::responder_start(
                    self.cfg.identity,
                    &self.cfg.seed_kem_d,
                    &self.cfg.seed_kem_z,
                    &self.cfg.nonce,
                    &self.buf[..n],
                    &self.cfg.peer_fp,
                ) {
                    Ok((st, m2)) => {
                        self.session = Some(Session::Responder(st));
                        let mut vk_tmp = [0u8; VK_LEN];
                        vk_tmp.copy_from_slice(&self.buf[32 + EK_LEN..32 + EK_LEN + VK_LEN]);
                        self.ensure_pc(&vk_tmp);
                        self.tx = Some(TxJob::new(&m2));
                        self.phase = 1;
                        self.phase_ms = 0;
                        FsmOutcome::Wait
                    }
                    Err(_) => FsmOutcome::Wait,
                }
            }
            _ => {
                let mut ack = None;
                let n = hsk_recv(self.spi, &mut self.rx, &mut self.buf, &mut ack);
                if ack.is_some() {
                    self.ack_pend = ack;
                }
                if n == 0 {
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
                        self.cfg.identity,
                        &self.buf[..n],
                        self.spi_i,
                        s.as_ref(),
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

    impl Default for MockSpi {
        fn default() -> Self {
            Self::new()
        }
    }

    impl SpiBus for MockSpi {
        unsafe fn write_reg(&self, addr: u8, data: u32) {
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

        unsafe fn read_reg(&self, addr: u8) -> u32 {
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
        sk: [u8; hs::SK_LEN],
        spc: hs::SignPrecomp,
    }

    impl hs::Identity for TestIdentity {
        fn vk(&self) -> &[u8; hs::VK_LEN] {
            &self.vk
        }
        fn sk(&self) -> &[u8; hs::SK_LEN] {
            &self.sk
        }
        fn spc(&self) -> &hs::SignPrecomp {
            &self.spc
        }
    }

    static IDENTITY_I: std::sync::OnceLock<TestIdentity> = std::sync::OnceLock::new();
    static IDENTITY_R: std::sync::OnceLock<TestIdentity> = std::sync::OnceLock::new();

    fn identity_i() -> &'static TestIdentity {
        IDENTITY_I.get_or_init(|| {
            let (vk, sk) = kyberlink_crypto::mldsa_internal::keygen_internal(&[3u8; 32]);
            let mut spc = hs::SignPrecomp::default();
            sign_precomp_new_into(&mut spc, &sk);
            TestIdentity { vk, sk, spc }
        })
    }

    fn identity_r() -> &'static TestIdentity {
        IDENTITY_R.get_or_init(|| {
            let (vk, sk) = kyberlink_crypto::mldsa_internal::keygen_internal(&[7u8; 32]);
            let mut spc = hs::SignPrecomp::default();
            sign_precomp_new_into(&mut spc, &sk);
            TestIdentity { vk, sk, spc }
        })
    }

    #[test]
    fn fsm_end_to_end_handshake() {
        let id_i = identity_i();
        let id_r = identity_r();
        let fp_i = id_i.fingerprint();
        let fp_r = id_r.fingerprint();

        let cfg_i = Config {
            role_initiator: true,
            peer_fp: fp_r,
            seed_kem_d: [1u8; 32],
            seed_kem_z: [2u8; 32],
            nonce: [4u8; 32],
            identity: id_i,
        };
        let cfg_r = Config {
            role_initiator: false,
            peer_fp: fp_i,
            seed_kem_d: [5u8; 32],
            seed_kem_z: [6u8; 32],
            nonce: [8u8; 32],
            identity: id_r,
        };
        let bus_i = MockSpi::default();
        let bus_r = MockSpi::default();
        let mut fi = Fsm::new(&cfg_i, &bus_i);
        let mut fr = Fsm::new(&cfg_r, &bus_r);
        let mut sa_i = None;
        let mut sa_r = None;
        for _ in 0..400 {
            match fi.poll() {
                FsmOutcome::Sa(sa) => sa_i = Some(sa),
                FsmOutcome::Wait => {}
            }
            bus_i.pump(&bus_r);
            match fr.poll() {
                FsmOutcome::Sa(sa) => sa_r = Some(sa),
                FsmOutcome::Wait => {}
            }
            bus_r.pump(&bus_i);
            if let (Some(a), Some(b)) = (&sa_i, &sa_r) {
                assert_eq!(a.spi_i, b.spi_i);
                assert_eq!(a.spi_r, b.spi_r);
                assert_eq!(a.sk_ei, b.sk_ei);
                assert_eq!(a.sk_er, b.sk_er);
                assert_eq!(a.sa_salt, b.sa_salt);
                return;
            }
        }
        panic!("handshake did not complete");
    }

    #[test]
    fn initiator_bad_m2_restarts() {
        let cfg = Config {
            role_initiator: true,
            peer_fp: [9u8; 32],
            seed_kem_d: [1u8; 32],
            seed_kem_z: [2u8; 32],
            nonce: [4u8; 32],
            identity: identity_i(),
        };
        let bus = MockSpi::default();
        let mut f = Fsm::new(&cfg, &bus);
        for _ in 0..4 {
            let _ = f.poll();
        }
        let m1 = bus.outbox.borrow()[0].clone();
        assert_eq!(m1[0..4], [0, 0, 12, 96], "m1 chunk header (3168B total)");
        bus.outbox.borrow_mut().clear();
        bus.push_rx(&[0xEE; 64]);
        for _ in 0..400 {
            let _ = f.poll();
        }
        let resent = bus.outbox.borrow().iter().any(|p| p == &m1);
        assert!(resent, "m1 must be resent after bad m2");
    }
}
