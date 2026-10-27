use kyberlink_core::handshake_fsm::{write_sa, REG_KEY_DEC, REG_KEY_ENC};
use kyberlink_crypto::handshake::SaParams;
use kyberlink_peer::bus::PeerBus;
use kyberlink_peer::esp::{DataPlane, HEADER, TAG};
use kyberlink_vecgen::cipher::GcmCipher;

fn sa() -> SaParams {
    SaParams {
        spi_i: 0x1122_3344,
        spi_r: 0x5566_7788,
        sk_ei: core::array::from_fn(|i| i as u8 + 1),
        sk_er: core::array::from_fn(|i| i as u8 + 0x40),
        sa_salt: core::array::from_fn(|i| i as u8 + 0x80),
    }
}

fn plane(initiator: bool) -> (PeerBus, DataPlane) {
    let bus = PeerBus::new();
    write_sa(&bus, &sa(), initiator, 1);
    let plane = DataPlane::from_bus(&bus);
    (bus, plane)
}

#[test]
fn wire_layout_matches_rtl() {
    let sa = sa();
    let (_bus, mut tx) = plane(true);
    let inner = b"kyberlink inner frame";
    let pad = (16 - ((inner.len() + 2) & 0xF)) & 0xF;
    let plain_len = inner.len() + pad + 2;
    let mut pkt = [0u8; 128];
    let n = tx.seal(inner, &mut pkt).unwrap();
    assert_eq!(n, HEADER + plain_len + TAG);
    assert_eq!(&pkt[..4], &sa.spi_i.to_be_bytes());
    assert_eq!(&pkt[4..8], &1u32.to_be_bytes());
    assert_eq!(&pkt[8..12], &1u32.to_be_bytes());
    assert_eq!(&pkt[12..HEADER], &sa.sa_salt[..8]);

    let mut nonce = [0u8; 12];
    nonce[..4].copy_from_slice(&1u32.to_be_bytes());
    nonce[4..].copy_from_slice(&sa.sa_salt[..8]);
    let mut aad = [0u8; 8];
    aad[..4].copy_from_slice(&sa.spi_i.to_be_bytes());
    aad[4..8].copy_from_slice(&1u32.to_be_bytes());

    let mut expect = inner.to_vec();
    expect.extend(std::iter::repeat_n(pad as u8, pad));
    expect.push(pad as u8);
    expect.push(0x04);
    let mut tag = [0u8; TAG];
    GcmCipher::new(&sa.sk_ei)
        .encrypt_in_place(&nonce, &aad, &mut expect, &mut tag)
        .unwrap();
    assert_eq!(&pkt[HEADER..HEADER + plain_len], expect.as_slice());
    assert_eq!(&pkt[HEADER + plain_len..n], &tag);
}

#[test]
fn plane_is_driven_by_the_registers() {
    let (a_bus, _a) = plane(true);
    let (b_bus, _b) = plane(false);
    for i in 0..8u8 {
        assert_eq!(
            a_bus.reg(REG_KEY_ENC + i),
            b_bus.reg(REG_KEY_DEC + i),
            "initiator encryption key is not the responder decryption key"
        );
        assert_eq!(
            b_bus.reg(REG_KEY_ENC + i),
            a_bus.reg(REG_KEY_DEC + i),
            "responder encryption key is not the initiator decryption key"
        );
    }
}

#[test]
fn round_trip_between_roles() {
    let (_ab, mut a) = plane(true);
    let (_bb, mut b) = plane(false);
    let mut out = [0u8; 128];
    let mut pkt = [0u8; 128];
    let n = a.seal(b"hello", &mut pkt).unwrap();
    let m = b.open(&pkt[..n], &mut out).unwrap();
    assert_eq!(&out[..m], b"hello");
    let n2 = b.seal(b"world", &mut pkt).unwrap();
    let m2 = a.open(&pkt[..n2], &mut out).unwrap();
    assert_eq!(&out[..m2], b"world");
}

#[test]
fn replay_and_forgery() {
    let (_ab, mut a) = plane(true);
    let (_bb, mut b) = plane(false);
    let mut out = [0u8; 128];
    let mut pkt = [0u8; 128];
    let n = a.seal(b"one", &mut pkt).unwrap();
    assert_eq!(b.open(&pkt[..n], &mut out), Some(3));
    assert_eq!(b.open(&pkt[..n], &mut out), None);

    let len = HEADER + 3 + TAG;
    let mut forged = [0u8; 128];
    forged[..len].copy_from_slice(&pkt[..len]);
    forged[4..8].copy_from_slice(&0xFFFF_0000u32.to_be_bytes());
    assert_eq!(b.open(&forged[..len], &mut out), None);

    let mut tampered = [0u8; 128];
    tampered[..len].copy_from_slice(&pkt[..len]);
    tampered[0] ^= 1;
    assert_eq!(b.open(&tampered[..len], &mut out), None);

    let n2 = a.seal(b"two", &mut pkt).unwrap();
    assert_eq!(b.open(&pkt[..n2], &mut out), Some(3));
}
