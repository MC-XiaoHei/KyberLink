use std::net::UdpSocket;
use std::time::{Duration, Instant};

use kyberlink_core::handshake_fsm::{FsmOutcome, Role};
use kyberlink_crypto::entropy::KemSeeds;
use kyberlink_peer::esp::DataPlane;
use kyberlink_peer::identity::MemIdentity;
use kyberlink_peer::peer::Peer;
use kyberlink_peer::udp::UdpLink;

const BUDGET: Duration = Duration::from_secs(20);

fn seeds(tag: u8) -> KemSeeds {
    KemSeeds {
        d: [tag; 32],
        z: [tag ^ 0x5A; 32],
        nonce: [tag ^ 0xA5; 32],
    }
}

#[test]
fn two_peers_over_udp() {
    let id_a = MemIdentity::from_seed(&[3u8; 32]);
    let id_b = MemIdentity::from_seed(&[4u8; 32]);
    let fp_a = id_a.fingerprint();
    let fp_b = id_b.fingerprint();

    let sock_a = UdpSocket::bind("127.0.0.1:0").unwrap();
    let sock_b = UdpSocket::bind("127.0.0.1:0").unwrap();
    let data_a = sock_a.try_clone().unwrap();
    let data_b = sock_b.try_clone().unwrap();
    let addr_a = sock_a.local_addr().unwrap();
    let addr_b = sock_b.local_addr().unwrap();

    let mut a = Peer::new(
        fp_b,
        seeds(3),
        id_a,
        Box::new(UdpLink::from_socket(sock_a, addr_b)),
    );
    let mut b = Peer::new(
        fp_a,
        seeds(4),
        id_b,
        Box::new(UdpLink::from_socket(sock_b, addr_a)),
    );

    let deadline = Instant::now() + BUDGET;
    let mut sa_a = None;
    let mut sa_b = None;
    while Instant::now() < deadline && (sa_a.is_none() || sa_b.is_none()) {
        if let FsmOutcome::Sa(sa) = a.poll() {
            if sa_a.is_none() {
                sa_a = Some(sa);
            }
        }
        if let FsmOutcome::Sa(sa) = b.poll() {
            if sa_b.is_none() {
                sa_b = Some(sa);
            }
        }
    }

    let sa_a = sa_a.expect("first peer did not complete over udp");
    let sa_b = sa_b.expect("second peer did not complete over udp");
    assert_eq!(sa_a.sk_ei, sa_b.sk_ei, "direction keys differ");
    assert_eq!(sa_a.sk_er, sa_b.sk_er, "direction keys differ");
    assert_ne!(a.bus().reg(0x44), 0, "encryption key register is empty");
    assert_ne!(b.bus().reg(0x44), 0, "encryption key register is empty");

    assert_ne!(
        a.role() == Role::Initiator,
        b.role() == Role::Initiator,
        "both peers claim the same role"
    );
    let mut da = DataPlane::from_bus(&a.bus());
    let mut db = DataPlane::from_bus(&b.bus());

    let mut pkt = [0u8; 256];
    let mut out = [0u8; 256];
    for inner in [b"first frame".as_slice(), b"second frame".as_slice()] {
        let n = da.seal(inner, &mut pkt).unwrap();
        data_a.send_to(&pkt[..n], addr_b).unwrap();
        let got = recv_open(&data_b, &mut db, &mut out);
        assert_eq!(&out[..got], inner, "responder failed to open the frame");

        let n = db.seal(inner, &mut pkt).unwrap();
        data_b.send_to(&pkt[..n], addr_a).unwrap();
        let got = recv_open(&data_a, &mut da, &mut out);
        assert_eq!(&out[..got], inner, "initiator failed to open the frame");
    }
}

fn recv_open(sock: &UdpSocket, plane: &mut DataPlane, out: &mut [u8]) -> usize {
    let mut scratch = [0u8; 2048];
    let deadline = Instant::now() + Duration::from_secs(2);
    while Instant::now() < deadline {
        if let Ok(n) = sock.recv(&mut scratch) {
            if let Some(m) = plane.open(&scratch[..n], out) {
                return m;
            }
            continue;
        }
        std::thread::sleep(Duration::from_millis(1));
    }
    panic!("no datagram arrived");
}
