use std::net::UdpSocket;
use std::time::{Duration, Instant};

use kyberlink_core::handshake_fsm::write_sa;
use kyberlink_crypto::handshake::SaParams;
use kyberlink_peer::bus::PeerBus;
use kyberlink_peer::esp::{DataPlane, MAX_INNER};
use kyberlink_peer::send::fanout;
use kyberlink_peer::udp::UdpLink;

const THREADS: usize = 2;
const FRAMES: u64 = 48;

fn sa() -> SaParams {
    SaParams {
        spi_i: 0x1122_3344,
        spi_r: 0x5566_7788,
        sk_ei: [1u8; 32],
        sk_er: [2u8; 32],
        sa_salt: [3u8; 32],
    }
}

#[test]
fn parallel_senders_all_open() {
    let sink = UdpSocket::bind("127.0.0.1:0").unwrap();
    sink.set_read_timeout(Some(Duration::from_millis(200)))
        .unwrap();
    let target = sink.local_addr().unwrap();

    let bus = PeerBus::new();
    write_sa(&bus, &sa(), true, 1);
    let links: Vec<UdpLink> = (0..THREADS)
        .map(|_| UdpLink::bind("127.0.0.1:0", target).unwrap())
        .collect();
    let payload = vec![0x5Au8; 64];
    let handles = fanout(&bus, links, &payload, FRAMES / THREADS as u64);

    let peer = PeerBus::new();
    write_sa(&peer, &sa(), false, 1);
    let mut plane = DataPlane::from_bus(&peer);
    let mut buf = [0u8; MAX_INNER + 78];
    let mut out = [0u8; MAX_INNER];
    let mut seen = 0u64;
    let mut opened = 0u64;
    let budget = Instant::now() + Duration::from_secs(10);
    while seen < FRAMES && Instant::now() < budget {
        let Ok(n) = sink.recv(&mut buf) else {
            continue;
        };
        seen += 1;
        if plane.open(&buf[..n], &mut out).is_some() {
            opened += 1;
        }
    }
    for h in handles {
        h.join().unwrap();
    }

    assert!(seen >= FRAMES / 2, "收到的帧太少,测不出东西,只有 {seen}");
    assert_eq!(opened, seen, "有帧被反重放拒了");
}
