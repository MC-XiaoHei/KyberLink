use std::net::UdpSocket;
use std::time::{Duration, Instant};

use kyberlink_core::handshake_fsm::write_sa;
use kyberlink_crypto::handshake::SaParams;
use kyberlink_peer::bus::PeerBus;
use kyberlink_peer::esp::{DataPlane, Shards, ESP_OVERHEAD};

const BATCH: usize = 16;
const ROUNDS: usize = 2000;
const PAYLOADS: [usize; 3] = [64, 512, 1422];
const MODES: [&str; 3] = ["socket", "seal", "full"];
const DRAIN: Duration = Duration::from_millis(50);
const TARGET_PPS: f64 = 83_333.0;
const SEND_TOTAL: u64 = 200_000;

fn sa() -> SaParams {
    SaParams {
        spi_i: 0x1122_3344,
        spi_r: 0x5566_7788,
        sk_ei: std::array::from_fn(|i| i as u8 + 1),
        sk_er: std::array::from_fn(|i| i as u8 + 0x40),
        sa_salt: std::array::from_fn(|i| i as u8 + 0x80),
    }
}

fn planes() -> (DataPlane, DataPlane) {
    let bus_a = PeerBus::new();
    let bus_b = PeerBus::new();
    write_sa(&bus_a, &sa(), true, 1);
    write_sa(&bus_b, &sa(), false, 1);
    (DataPlane::from_bus(&bus_a), DataPlane::from_bus(&bus_b))
}

fn row(label: &str, payload: usize, pps: f64, fail: f64) {
    let wire = payload + ESP_OVERHEAD;
    println!(
        "{label:<8} {payload:>7} {wire:>6} {pps:>12.0} pps {:>11.2} Gbps {fail:>6.3}%  {:.2} µs/frame",
        pps * wire as f64 * 8.0 / 1e9,
        1e6 / pps
    );
}

fn loopback(payload: usize) {
    let sock_a = UdpSocket::bind("127.0.0.1:0").unwrap();
    let sock_b = UdpSocket::bind("127.0.0.1:0").unwrap();
    sock_b.set_nonblocking(true).unwrap();
    let addr_b = sock_b.local_addr().unwrap();
    let (mut a, mut b) = planes();

    let inner = vec![0x5Au8; payload];
    let mut pkt = vec![0u8; 2048];
    let mut out = vec![0u8; 2048];
    for mode in MODES {
        let mut sent = 0u64;
        let mut got = 0u64;
        let start = Instant::now();
        for _ in 0..ROUNDS {
            let want = sent + BATCH as u64;
            for _ in 0..BATCH {
                let n = if mode == "socket" {
                    pkt[..payload + ESP_OVERHEAD].fill(0x5A);
                    payload + ESP_OVERHEAD
                } else {
                    a.seal(&inner, &mut pkt).unwrap()
                };
                sock_a.send_to(&pkt[..n], addr_b).unwrap();
                sent += 1;
            }
            let deadline = Instant::now() + DRAIN;
            while got < want {
                let n = match sock_b.recv(&mut pkt) {
                    Ok(n) => n,
                    Err(_) if Instant::now() > deadline => break,
                    Err(_) => continue,
                };
                if mode != "full" || b.open(&pkt[..n], &mut out).is_some() {
                    got += 1;
                }
            }
        }
        let el = start.elapsed().as_secs_f64();
        let fail = sent.saturating_sub(got) as f64 * 100.0 / sent as f64;
        row(mode, payload, got as f64 / el, fail);
    }
}

fn split(payload: usize) {
    let sock_a = UdpSocket::bind("127.0.0.1:0").unwrap();
    let sock_b = UdpSocket::bind("127.0.0.1:0").unwrap();
    sock_b.set_nonblocking(true).unwrap();
    let addr_b = sock_b.local_addr().unwrap();
    let (mut a, mut b) = planes();

    let inner = vec![0x5Au8; payload];
    let mut pkt = vec![0u8; 2048];
    let mut out = vec![0u8; 2048];
    let mut send_ns = 0u128;
    let mut recv_ns = 0u128;
    let mut got = 0u64;
    for _ in 0..ROUNDS {
        let t0 = Instant::now();
        for _ in 0..BATCH {
            let n = a.seal(&inner, &mut pkt).unwrap();
            sock_a.send_to(&pkt[..n], addr_b).unwrap();
        }
        let t1 = Instant::now();
        let want = got + BATCH as u64;
        let deadline = Instant::now() + DRAIN;
        while got < want {
            match sock_b.recv(&mut pkt) {
                Ok(n) => {
                    if b.open(&pkt[..n], &mut out).is_some() {
                        got += 1;
                    }
                }
                Err(_) if Instant::now() > deadline => break,
                Err(_) => continue,
            }
        }
        let t2 = Instant::now();
        send_ns += t1.duration_since(t0).as_nanos();
        recv_ns += t2.duration_since(t1).as_nanos();
    }
    let sent = (ROUNDS * BATCH) as f64;
    let fail = (sent - got as f64) * 100.0 / sent;
    row("send", payload, sent * 1e9 / send_ns as f64, fail);
    row("recv", payload, got as f64 * 1e9 / recv_ns as f64, fail);
}

fn fan(payload: usize, threads: u32, sealed: bool) {
    use std::sync::Arc;
    let per = SEND_TOTAL / threads as u64;
    let target: std::net::SocketAddr = ([127, 0, 0, 1], 9).into();
    let base = {
        let bus = PeerBus::new();
        write_sa(&bus, &sa(), true, 1);
        DataPlane::from_bus(&bus).tx_seq()
    };
    let shards = Arc::new(Shards::new(base));
    let start = Instant::now();
    let mut handles = Vec::with_capacity(threads as usize);
    for _ in 0..threads {
        let shards = Arc::clone(&shards);
        handles.push(std::thread::spawn(move || {
            let bus = PeerBus::new();
            write_sa(&bus, &sa(), true, 1);
            let mut plane = DataPlane::from_bus(&bus);
            let sock = UdpSocket::bind("0.0.0.0:0").unwrap();
            let inner = vec![0x5Au8; payload];
            let mut frame = vec![0u8; 2048];
            for _ in 0..per {
                let n = if sealed {
                    shards.seal(&mut plane, &inner, &mut frame).unwrap()
                } else {
                    frame[..payload + ESP_OVERHEAD].fill(0x5A);
                    payload + ESP_OVERHEAD
                };
                sock.send_to(&frame[..n], target).unwrap();
            }
        }));
    }
    for h in handles {
        h.join().unwrap();
    }
    let el = start.elapsed().as_secs_f64();
    row(
        &format!("fan{threads}{}", if sealed { "s" } else { "" }),
        payload,
        (per * threads as u64) as f64 / el,
        0.0,
    );
}

fn main() {
    println!("mode     payload   wire    frame rate    throughput   loss");
    for payload in PAYLOADS {
        loopback(payload);
    }
    println!("mode     payload   wire    frame rate    throughput   loss");
    for payload in PAYLOADS {
        split(payload);
    }
    println!(
        "mode     payload   wire    frame rate    throughput   loss    (单向 1 Gbps = {TARGET_PPS:.0} pps @1500B)"
    );
    for threads in [1u32, 2, 4] {
        fan(1422, threads, false);
        fan(1422, threads, true);
    }
}
