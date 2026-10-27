use kyberlink_crypto::handshake::{self, Identity};
use kyberlink_crypto::mldsa_internal::{sign_precomp_new_into, SignPrecomp, VK_LEN};
use std::time::Instant;

struct TestIdentity {
    vk: [u8; VK_LEN],
    kk: [u8; handshake::KK_LEN],
    tr: [u8; handshake::TR_LEN],
    spc: SignPrecomp,
}

impl TestIdentity {
    fn new(seed: [u8; 32]) -> Self {
        let (vk, sk) = kyberlink_crypto::mldsa_internal::keygen_internal(&seed);
        let mut spc = SignPrecomp::default();
        sign_precomp_new_into(&mut spc, &sk);
        TestIdentity {
            vk,
            kk: handshake::kk_of(&sk),
            tr: handshake::tr_of(&sk),
            spc,
        }
    }
}

impl Identity for TestIdentity {
    fn vk(&self) -> &[u8; VK_LEN] {
        &self.vk
    }
    fn kk(&self) -> &[u8; handshake::KK_LEN] {
        &self.kk
    }
    fn tr(&self) -> &[u8; handshake::TR_LEN] {
        &self.tr
    }
    fn spc(&self) -> &SignPrecomp {
        &self.spc
    }
}

fn main() {
    let id_i = TestIdentity::new([3u8; 32]);
    let id_r = TestIdentity::new([7u8; 32]);
    let fp_i = id_i.fingerprint();
    let fp_r = id_r.fingerprint();

    let mut kem = kyberlink_crypto::scratch::Scratch::new();
    let t = Instant::now();
    let mut st_i = handshake::InitiatorState::empty();
    let mut m1b = [0u8; handshake::M1_LEN];
    let n1 = handshake::initiator_start(
        &id_i,
        &kyberlink_crypto::entropy::KemSeeds { d: [1u8; 32], z: [2u8; 32], nonce: [5u8; 32] },
        &mut kem,
        &mut st_i,
        &mut m1b,
    );
    let m1 = &m1b[..n1];
    println!("kem keygen+M1: {:?}", t.elapsed());

    let t = Instant::now();
    let mut st_r = handshake::ResponderState::empty();
    let mut m2b = [0u8; handshake::M2_LEN];
    let n2 = handshake::responder_start(
        &id_r,
        &kyberlink_crypto::entropy::KemSeeds { d: [5u8; 32], z: [6u8; 32], nonce: [9u8; 32] },
        m1,
        &fp_i,
        &mut kem,
        &mut st_r,
        &mut m2b,
    )
    .unwrap();
    let m2 = &m2b[..n2];
    println!("resp M2+sign : {:?}", t.elapsed());

    let t = Instant::now();
    let mut m3b = [0u8; handshake::M3_LEN];
    let (n3, spi_i) =
        handshake::initiator_recv_m2(&mut st_i, &id_i, m2, &fp_r, None, &mut kem, &mut m3b)
            .unwrap();
    let m3 = &m3b[..n3];
    println!("init verifyM2: {:?}", t.elapsed());

    let t = Instant::now();
    let mut m4b = [0u8; handshake::M4_LEN];
    let (n4, sa) =
        handshake::responder_recv_m3(&mut st_r, &id_r, m3, spi_i, None, &mut kem, &mut m4b)
            .unwrap();
    let m4 = &m4b[..n4];
    println!("resp verifyM3: {:?}", t.elapsed());

    let t = Instant::now();
    let sa2 = handshake::initiator_recv_m4(&mut st_i, m4, spi_i, None, &mut kem).unwrap();
    println!("init verifyM4: {:?}", t.elapsed());
    println!("sa == sa2: {}", sa.spi_i == sa2.spi_i);
}
