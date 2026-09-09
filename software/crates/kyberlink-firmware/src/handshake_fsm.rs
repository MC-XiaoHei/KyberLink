use kyberlink_crypto::handshake as hs;
use kyberlink_crypto::mldsa_internal::sign_precomp_new_into;
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

pub fn hsk_send<S: SpiBus>(spi: &S, data: &[u8]) {
    unsafe {
        spi.write_reg(REG_HSK_TX_LEN, data.len() as u32);
        for chunk in data.chunks(4) {
            let mut b = [0u8; 4];
            b[..chunk.len()].copy_from_slice(chunk);
            let w = u32::from_be_bytes(b);
            spi.write_reg(REG_HSK_TX_DATA, w);
        }
        spi.write_reg(REG_CTRL, CTRL_HSK_SEND);
    }
}

fn hsk_recv<S: SpiBus>(spi: &S, buf: &mut [u8]) -> usize {
    unsafe {
        let status = spi.read_reg(REG_STATUS);
        if status & STATUS_RX_PENDING == 0 {
            return 0;
        }
        let len = (spi.read_reg(REG_HSK_RX_LEN) & 0xFFFF) as usize;
        let mut n = 0;
        while n < len {
            let w = spi.read_reg(REG_HSK_RX_DATA);
            let b = w.to_be_bytes();
            let take = core::cmp::min(4, len - n);
            buf[n..n + take].copy_from_slice(&b[..take]);
            n += take;
        }
        n
    }
}

use embassy_sync::blocking_mutex::CriticalSectionMutex;

pub enum FsmOutcome {
    Sa(hs::SaParams),
    Wait,
}

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
                hsk_send(self.spi, &m1);
                self.phase = 1;
                FsmOutcome::Wait
            }
            1 => {
                let n = hsk_recv(self.spi, &mut self.buf);
                if n == 0 {
                    return FsmOutcome::Wait;
                }
                let mut vk_tmp = [0u8; VK_LEN];
                vk_tmp.copy_from_slice(&self.buf[32 + EK_LEN..32 + EK_LEN + VK_LEN]);
                self.pc_vk = vk_tmp;
                let vk = self.pc_vk;
                self.ensure_pc(&vk);
                let Session::Initiator(st) = self.session.as_mut().unwrap() else { return FsmOutcome::Wait };
                PC_CACHE.lock(|s| match hs::initiator_recv_m2(st, self.cfg.identity, &self.buf[..n], &self.cfg.peer_fp, s.as_ref()) {
                    Ok((m3, spi_i)) => {
                        self.spi_i = spi_i;
                        hsk_send(self.spi, &m3);
                        self.phase = 2;
                        FsmOutcome::Wait
                    }
                    Err(_) => {
                        self.phase = 0;
                        FsmOutcome::Wait
                    }
                })
            }
            _ => {
                let n = hsk_recv(self.spi, &mut self.buf);
                if n == 0 {
                    return FsmOutcome::Wait;
                }
                let vk = self.pc_vk;
                self.ensure_pc(&vk);
                let Session::Initiator(st) = self.session.as_mut().unwrap() else { return FsmOutcome::Wait };
                PC_CACHE.lock(|s| match hs::initiator_recv_m4(st, &self.buf[..n], self.spi_i, s.as_ref()) {
                    Ok(sa) => {
                        self.phase = 0;
                        FsmOutcome::Sa(sa)
                    }
                    Err(_) => {
                        self.phase = 0;
                        FsmOutcome::Wait
                    }
                })
            }
        }
    }

    fn poll_responder(&mut self) -> FsmOutcome {
        match self.phase {
            0 => {
                let n = hsk_recv(self.spi, &mut self.buf);
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
                        hsk_send(self.spi, &m2);
                        self.phase = 1;
                        FsmOutcome::Wait
                    }
                    Err(_) => FsmOutcome::Wait,
                }
            }
            _ => {
                let n = hsk_recv(self.spi, &mut self.buf);
                if n == 0 {
                    return FsmOutcome::Wait;
                }
                let mut sb = [0u8; 4];
                sb.copy_from_slice(&self.buf[hs::SPI_OFF..hs::SPI_OFF + 4]);
                self.spi_i = u32::from_be_bytes(sb);
                let vk = self.pc_vk;
                self.ensure_pc(&vk);
                let Session::Responder(st) = self.session.as_mut().unwrap() else { return FsmOutcome::Wait };
                PC_CACHE.lock(|s| match hs::responder_recv_m3(st, self.cfg.identity, &self.buf[..n], self.spi_i, s.as_ref()) {
                    Ok((m4, sa)) => {
                        hsk_send(self.spi, &m4);
                        self.phase = 0;
                        FsmOutcome::Sa(sa)
                    }
                    Err(_) => {
                        self.phase = 0;
                        FsmOutcome::Wait
                    }
                })
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use core::cell::{Cell, RefCell};

    struct MockSpi {
        regs: RefCell<[u32; 128]>,
        tx_buf: RefCell<Vec<u8>>,
        outbox: RefCell<Vec<Vec<u8>>>,
        inbox: RefCell<Vec<u32>>,
        rx_len: Cell<usize>,
    }

    impl MockSpi {
        fn new() -> Self {
            MockSpi {
                regs: RefCell::new([0; 128]),
                tx_buf: RefCell::new(Vec::new()),
                outbox: RefCell::new(Vec::new()),
                inbox: RefCell::new(Vec::new()),
                rx_len: Cell::new(0),
            }
        }

        fn w(&self, addr: u8) -> u32 {
            self.regs.borrow()[addr as usize]
        }

        fn deliver(&self, dst: &MockSpi) {
            let msgs: Vec<Vec<u8>> = self.outbox.borrow_mut().drain(..).collect();
            for msg in msgs {
                let mut words = Vec::new();
                for chunk in msg.chunks(4) {
                    let mut b = [0u8; 4];
                    b[..chunk.len()].copy_from_slice(chunk);
                    words.push(u32::from_be_bytes(b));
                }
                dst.inbox.borrow_mut().extend(words);
                dst.rx_len.set(msg.len());
            }
        }

        fn push_rx(&self, msg: &[u8]) {
            let mut words = Vec::new();
            for chunk in msg.chunks(4) {
                let mut b = [0u8; 4];
                b[..chunk.len()].copy_from_slice(chunk);
                words.push(u32::from_be_bytes(b));
            }
            self.inbox.borrow_mut().extend(words);
            self.rx_len.set(msg.len());
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
                let mut buf = self.tx_buf.borrow().clone();
                buf.truncate(len);
                self.outbox.borrow_mut().push(buf);
                self.tx_buf.borrow_mut().clear();
            }
        }

        unsafe fn read_reg(&self, addr: u8) -> u32 {
            match addr {
                REG_STATUS => {
                    if self.inbox.borrow().is_empty() {
                        0
                    } else {
                        STATUS_RX_PENDING
                    }
                }
                REG_HSK_RX_LEN => self.rx_len.get() as u32,
                REG_HSK_RX_DATA => self.inbox.borrow_mut().remove(0),
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
        hsk_send(&m, &[1, 2, 3, 4, 5]);
        assert_eq!(m.w(REG_HSK_TX_LEN), 5);
        assert_eq!(m.w(REG_CTRL), CTRL_HSK_SEND);
        assert_eq!(m.outbox.borrow().len(), 1);
        assert_eq!(m.outbox.borrow()[0], vec![1, 2, 3, 4, 5]);
        assert!(m.tx_buf.borrow().is_empty());
    }

    #[test]
    fn hsk_recv_reads_fifo() {
        let m = MockSpi::default();
        assert_eq!(hsk_recv(&m, &mut [0u8; 16]), 0);
        m.push_rx(&[0xAA, 0xBB, 0xCC, 0xDD, 0xEE]);
        let mut buf = [0u8; 16];
        let n = hsk_recv(&m, &mut buf);
        assert_eq!(n, 5);
        assert_eq!(&buf[..5], &[0xAA, 0xBB, 0xCC, 0xDD, 0xEE]);
        assert!(m.inbox.borrow().is_empty());
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
        for _ in 0..16 {
            match fi.poll() {
                FsmOutcome::Sa(sa) => sa_i = Some(sa),
                FsmOutcome::Wait => {}
            }
            bus_i.deliver(&bus_r);
            match fr.poll() {
                FsmOutcome::Sa(sa) => sa_r = Some(sa),
                FsmOutcome::Wait => {}
            }
            bus_r.deliver(&bus_i);
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
        assert!(matches!(f.poll(), FsmOutcome::Wait));
        assert_eq!(bus.outbox.borrow().len(), 1);
        let m1 = bus.outbox.borrow()[0].clone();
        bus.push_rx(&[0xEE; 64]);
        assert!(matches!(f.poll(), FsmOutcome::Wait));
        assert_eq!(bus.outbox.borrow().len(), 1, "bad m2 must not send m3");
        assert!(matches!(f.poll(), FsmOutcome::Wait));
        assert_eq!(bus.outbox.borrow().len(), 2, "m1 must be resent after bad m2");
        assert_eq!(bus.outbox.borrow()[1], m1);
    }
}