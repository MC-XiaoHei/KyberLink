use kyberlink_crypto::handshake::{self, Identity};
use kyberlink_crypto::kem_internal::EK_LEN;
use kyberlink_crypto::mldsa_internal::{sign_precomp_new_into, SignPrecomp, SK_LEN, VK_LEN};
use std::time::Instant;

struct TestIdentity {
    vk: [u8; VK_LEN],
    sk: [u8; SK_LEN],
    spc: SignPrecomp,
}

impl TestIdentity {
    fn new(seed: [u8; 32]) -> Self {
        let (vk, sk) = kyberlink_crypto::mldsa_internal::keygen_internal(&seed);
        let mut spc = SignPrecomp::default();
        sign_precomp_new_into(&mut spc, &sk);
        TestIdentity { vk, sk, spc }
    }
}

impl Identity for TestIdentity {
    fn vk(&self) -> &[u8; VK_LEN] {
        &self.vk
    }
    fn sk(&self) -> &[u8; SK_LEN] {
        &self.sk
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

    let t = Instant::now();
    let (mut st_i, m1) = handshake::initiator_start(&id_i, &[1u8; 32], &[2u8; 32], &[5u8; 32]);
    println!("kem keygen+M1: {:?}", t.elapsed());

    let t = Instant::now();
    let (mut st_r, m2) =
        handshake::responder_start(&id_r, &[5u8; 32], &[6u8; 32], &[9u8; 32], &m1, &fp_i).unwrap();
    println!("resp M2+sign : {:?}", t.elapsed());

    let t = Instant::now();
    let (m3, spi_i) = handshake::initiator_recv_m2(&mut st_i, &id_i, &m2, &fp_r, None).unwrap();
    println!("init verifyM2: {:?}", t.elapsed());

    let t = Instant::now();
    let (m4, sa) = handshake::responder_recv_m3(&mut st_r, &id_r, &m3, spi_i, None).unwrap();
    println!("resp verifyM3: {:?}", t.elapsed());

    let t = Instant::now();
    let sa2 = handshake::initiator_recv_m4(&mut st_i, &m4, spi_i, None).unwrap();
    println!("init verifyM4: {:?}", t.elapsed());
    println!("sa == sa2: {}", sa.spi_i == sa2.spi_i);
}
