
use std::env;
use std::sync::Mutex;
use std::process::ExitCode;
use std::thread::sleep;
use std::time::{Duration, Instant};

use kyberlink_core::handshake_fsm::FsmOutcome;
use kyberlink_crypto::entropy::KemSeeds;
use kyberlink_peer::identity::MemIdentity;
use kyberlink_peer::peer::{Link, Peer};
use kyberlink_peer::udp::UdpLink;

static RX_FRAMES: Mutex<Vec<Vec<u8>>> = Mutex::new(Vec::new());

struct Traced {
    inner: UdpLink,
    quiet: bool,
}

impl kyberlink_peer::peer::Link for Traced {
    fn send(&self, payload: &[u8]) {
        if !self.quiet {
            println!("tx {} {:02x?}", payload.len(), &payload[..payload.len().min(8)]);
        }
        self.inner.send(payload);
    }

    fn recv(&self) -> Option<Vec<u8>> {
        let d = self.inner.recv()?;
        if !self.quiet {
            println!("rx {} {:02x?}", d.len(), &d[..d.len().min(8)]);
            if d.len() > 8 && d[..4] != [0xff, 0xff, 0xff, 0xff] {
                println!("raw {}", hex(&d));
            }
        }
        if d.len() > 8 && d[..4] != [0xff, 0xff, 0xff, 0xff] {
            RX_FRAMES.lock().unwrap().push(d.clone());
        }
        Some(d)
    }
}

const TICK: Duration = Duration::from_micros(500);

struct Options {
    bind: String,
    peer: String,
    peer_fp: [u8; 32],
    seed: [u8; 32],
    seconds: u64,
    flood: u32,
    body: usize,
    pace: u64,
    quiet: bool,
}

fn hex32(text: &str) -> [u8; 32] {
    let mut out = [0u8; 32];
    let bytes = text.as_bytes();
    assert_eq!(bytes.len(), 64, "expected 64 hex characters");
    for (i, slot) in out.iter_mut().enumerate() {
        let hi = (bytes[2 * i] as char).to_digit(16).expect("hex") as u8;
        let lo = (bytes[2 * i + 1] as char).to_digit(16).expect("hex") as u8;
        *slot = (hi << 4) | lo;
    }
    out
}

fn parse() -> Options {
    let mut opts = Options {
        bind: "0.0.0.0:4000".to_string(),
        peer: "10.88.0.1:4000".to_string(),
        peer_fp: [0u8; 32],
        seed: [0x42u8; 32],
        seconds: 30,
        flood: 0,
        body: 300,
        pace: 0,
        quiet: false,
    };
    let mut args = env::args().skip(1);
    while let Some(flag) = args.next() {
        let mut value = || args.next().expect("missing value");
        match flag.as_str() {
            "--bind" => opts.bind = value(),
            "--peer" => opts.peer = value(),
            "--peer-fp" => opts.peer_fp = hex32(&value()),
            "--seed" => opts.seed = hex32(&value()),
            "--seconds" => opts.seconds = value().parse().expect("seconds"),
            "--flood" => opts.flood = value().parse().expect("flood"),
            "--body" => opts.body = value().parse().expect("body"),
            "--pace" => opts.pace = value().parse().expect("pace"),
            "--quiet" => opts.quiet = true,
            other => panic!("unknown flag {other}"),
        }
    }
    opts
}

fn flood(
    count: u32,
    body_len: usize,
    pace_us: u64,
    peer_addr: &str,
    sa: &kyberlink_crypto::handshake::SaParams,
    initiator: bool,
) {
    let mut plane = kyberlink_peer::esp::DataPlane::from_sa(sa, initiator);
    let mut inner = [0u8; 1600];
    let body = [0x5au8; 1400];
    let n = inner_frame(&mut inner, &body[..body_len.min(1400)]);
    let mut pkt = [0u8; 1600];
    let data_addr = match peer_addr.rsplit_once(':') {
        Some((host, port)) => format!("{host}:{}", port.parse::<u16>().unwrap_or(4501) - 1),
        None => peer_addr.to_string(),
    };
    let link = UdpLink::bind("0.0.0.0:0", data_addr.as_str());
    let link = match link {
        Ok(l) => l,
        Err(e) => {
            eprintln!("flood bind failed: {e}");
            return;
        }
    };
    let started = Instant::now();
    for _ in 0..count {
        if let Some(len) = plane.seal(&inner[..n], &mut pkt) {
            link.send(&pkt[..len]);
        }
        if pace_us > 0 {
            sleep(Duration::from_micros(pace_us));
        }
    }
    let elapsed = started.elapsed().as_secs_f64();
    println!(
        "flooded {count} frames in {elapsed:.2}s ({:.0} frames/s)",
        count as f64 / elapsed.max(1e-6)
    );
}

fn inner_frame(out: &mut [u8], payload: &[u8]) -> usize {
    let mut p = 0;
    out[..6].copy_from_slice(&[0xb0, 0x25, 0xaa, 0x82, 0xcc, 0xee]);
    out[6..12].copy_from_slice(&[0x02, 0x00, 0x00, 0x00, 0x00, 0x07]);
    out[12..14].copy_from_slice(&[0x08, 0x00]);
    p += 14;
    let total = 20 + 8 + payload.len();
    out[p] = 0x45;
    out[p + 2..p + 4].copy_from_slice(&(total as u16).to_be_bytes());
    out[p + 8] = 64;
    out[p + 9] = 17;
    out[p + 12..p + 16].copy_from_slice(&[10, 88, 0, 1]);
    out[p + 16..p + 20].copy_from_slice(&[10, 88, 0, 2]);
    let mut sum = 0u32;
    for i in (p..p + 20).step_by(2) {
        sum += u16::from_be_bytes([out[i], out[i + 1]]) as u32;
    }
    while sum > 0xffff {
        sum = (sum & 0xffff) + (sum >> 16);
    }
    out[p + 10..p + 12].copy_from_slice(&(!(sum as u16)).to_be_bytes());
    p += 20;
    out[p..p + 2].copy_from_slice(&9999u16.to_be_bytes());
    out[p + 2..p + 4].copy_from_slice(&9999u16.to_be_bytes());
    out[p + 4..p + 6].copy_from_slice(&((8 + payload.len()) as u16).to_be_bytes());
    p += 8;
    out[p..p + payload.len()].copy_from_slice(payload);
    p + payload.len()
}

fn seeds(seed: &[u8; 32]) -> KemSeeds {
    let mut d = *seed;
    let mut z = *seed;
    let mut nonce = *seed;
    for (i, slot) in d.iter_mut().enumerate() {
        *slot ^= i as u8;
    }
    for (i, slot) in z.iter_mut().enumerate() {
        *slot ^= (i as u8).wrapping_mul(3);
    }
    for (i, slot) in nonce.iter_mut().enumerate() {
        *slot ^= (i as u8).wrapping_mul(7);
    }
    KemSeeds { d, z, nonce }
}

fn main() -> ExitCode {
    let opts = parse();
    let identity = MemIdentity::from_seed(&opts.seed);
    let local_fp = identity.fingerprint();
    println!("peer fingerprint: {}", hex(&local_fp));
    {
        let vk = kyberlink_crypto::handshake::Identity::vk(&identity);
        println!("peer vk[0..4]   = {:02x?}", &vk[..4]);
        println!("peer vk[1948..] = {:02x?}", &vk[1948..1952]);
    }
    println!("binding {} -> {}", opts.bind, opts.peer);

    let link = match UdpLink::bind(opts.bind.as_str(), opts.peer.as_str()) {
        Ok(link) => link,
        Err(err) => {
            eprintln!("bind failed: {err}");
            return ExitCode::FAILURE;
        }
    };
    let mut peer = Peer::new(
        opts.peer_fp,
        seeds(&opts.seed),
        identity,
        Box::new(Traced { inner: link, quiet: opts.quiet }),
    );

    let deadline = Instant::now() + Duration::from_secs(opts.seconds);
    let mut last_role = peer.role();
    let mut last_counters = peer.counters();
    let mut sa_seen: Option<[u8; 32]> = None;
    let mut plane: Option<kyberlink_peer::esp::DataPlane> = None;
    let mut opened = 0u32;
    let mut refused = 0u32;
    let mut spi: Option<[u8; 4]> = None;

    while Instant::now() < deadline {
        match peer.poll() {
            FsmOutcome::Sa(sa) => {
                let fresh = sa_seen != Some(sa.sa_salt);
                if fresh {
                    sa_seen = Some(sa.sa_salt);
                    spi = Some(sa.spi_i.to_be_bytes());
                    plane = Some(kyberlink_peer::esp::DataPlane::from_sa(
                        &sa,
                        peer.role() == kyberlink_core::handshake_fsm::Role::Initiator,
                    ));
                    println!(
                        "secure association: spi_i={:08x} spi_r={:08x} salt={}",
                        sa.spi_i,
                        sa.spi_r,
                        hex(&sa.sa_salt)
                    );
                    if opts.flood > 0 && fresh {
                        flood(
                            opts.flood,
                            opts.body,
                            opts.pace,
                            &opts.peer,
                            &sa,
                            peer.role() == kyberlink_core::handshake_fsm::Role::Initiator,
                        );
                    }
                }
            }
            FsmOutcome::Wait => {}
        }
        if let Some(state) = plane.as_mut() {
            let frames: Vec<Vec<u8>> = {
                let mut held = RX_FRAMES.lock().unwrap();
                core::mem::take(&mut *held)
            };
            for frame in frames {
                if let Some(want) = spi {
                    if frame.len() < 20 || frame[..4] != want {
                        continue;
                    }
                }
                let mut out = [0u8; 2048];
                match state.open(&frame, &mut out) {
                    Some(n) => {
                        opened += 1;
                        if opened <= 3 {
                            println!("open ok len={n} payload={:02x?}", &out[..n.min(24)]);
                        }
                    }
                    None => refused += 1,
                }
            }
        }
        let role = peer.role();
        let counters = peer.counters();
        if role != last_role || counters != last_counters {
            println!("role={role:?} sent={} recv={}", counters.0, counters.1);
            last_role = role;
            last_counters = counters;
        }
        sleep(TICK);
    }

    println!("data plane: opened={opened} refused={refused}");
    println!(
        "done: role={:?} sent={} recv={} established={}",
        peer.role(),
        peer.counters().0,
        peer.counters().1,
        sa_seen.is_some()
    );
    if sa_seen.is_some() {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}

fn hex(bytes: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for &byte in bytes {
        out.push(DIGITS[(byte >> 4) as usize] as char);
        out.push(DIGITS[(byte & 0x0f) as usize] as char);
    }
    out
}
