use std::env;
use std::io::{Read, Write};
use std::net::{TcpListener, UdpSocket};
use std::process::ExitCode;
use std::thread::sleep;
use std::time::{Duration, Instant};

use parking_lot::Mutex;

use kyberlink_core::handshake_fsm::FsmOutcome;
use kyberlink_crypto::entropy::KemSeeds;
use kyberlink_peer::identity::MemIdentity;
use kyberlink_peer::peer::{Link, Peer};
use kyberlink_peer::udp::{widen_recv_buffer, UdpLink};

static RX_FRAMES: Mutex<Vec<Vec<u8>>> = Mutex::new(Vec::new());
static CAPTURE: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
const CAPTURE_LIMIT: usize = 32768;
static SKIPPED: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
static DIR_TX: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
static DIR_RX: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
static PPS: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

const TICK: Duration = Duration::from_micros(500);
const MAX_PAYLOAD: usize = 1380;

struct Traced {
    inner: UdpLink,
    quiet: bool,
}

impl Link for Traced {
    fn send(&self, payload: &[u8]) {
        if !self.quiet {
            println!(
                "tx {} {:02x?}",
                payload.len(),
                &payload[..payload.len().min(8)]
            );
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
        if d.len() > 8
            && d[..4] != [0xff, 0xff, 0xff, 0xff]
            && CAPTURE.load(std::sync::atomic::Ordering::Relaxed)
        {
            let mut held = RX_FRAMES.lock();
            if held.len() < CAPTURE_LIMIT {
                held.push(d.clone());
            } else {
                SKIPPED.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            }
        }
        Some(d)
    }
}

#[derive(Clone, Copy, PartialEq)]
enum Mode {
    Live,
    Source,
    Sink,
    Peer,
}

struct Options {
    bind: String,
    peer: String,
    peer_fp: [u8; 32],
    seed: [u8; 32],
    seconds: u64,
    mode: Mode,
    plain: bool,
    pps: u64,
    size: usize,
    wait_ms: u64,
    quiet: bool,
    http: u16,
}

struct Stats {
    frames: u64,
    bytes: u64,
    bad: u64,
}

impl Stats {
    fn new() -> Self {
        Stats {
            frames: 0,
            bytes: 0,
            bad: 0,
        }
    }

    fn report(&mut self, second: u64) {
        let skipped = SKIPPED.swap(0, std::sync::atomic::Ordering::Relaxed);
        println!("{second},{},{},{},{}", self.frames, self.bytes, self.bad, skipped);
        self.frames = 0;
        self.bytes = 0;
        self.bad = 0;
    }
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
        mode: Mode::Live,
        plain: false,
        pps: 0,
        size: 1200,
        wait_ms: 2500,
        quiet: false,
        http: 8771,
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
            "--mode" => {
                opts.mode = match value().as_str() {
                    "live" => Mode::Live,
                    "source" => Mode::Source,
                    "sink" => Mode::Sink,
                    "peer" => Mode::Peer,
                    other => panic!("unknown mode {other}"),
                }
            }
            "--plain" => opts.plain = true,
            "--pps" => opts.pps = value().parse().expect("pps"),
            "--wait" => opts.wait_ms = value().parse().expect("wait"),
            "--size" => opts.size = value().parse().expect("size"),
            "--quiet" => opts.quiet = true,
            "--http" => opts.http = value().parse().expect("http port"),
            other => panic!("unknown flag {other}"),
        }
    }
    opts.size = opts.size.min(MAX_PAYLOAD);
    opts
}

fn wait_until(deadline: Instant) {
    while Instant::now() < deadline {
        core::hint::spin_loop();
    }
}

fn next_deadline(deadline: Instant, pps: u64) -> Instant {
    let Some(period) = 1_000_000_000u64.checked_div(pps) else {
        return Instant::now();
    };
    deadline + Duration::from_nanos(period)
}


fn running(started: Instant, seconds: u64) -> bool {
    seconds == 0 || started.elapsed() < Duration::from_secs(seconds)
}

fn dirs() -> (bool, bool) {
    (
        DIR_TX.load(std::sync::atomic::Ordering::Relaxed),
        DIR_RX.load(std::sync::atomic::Ordering::Relaxed),
    )
}

fn serve_control(port: u16) -> std::io::Result<()> {
    let sock = socket2::Socket::new(
        socket2::Domain::IPV4,
        socket2::Type::STREAM,
        Some(socket2::Protocol::TCP),
    )?;
    sock.set_reuse_address(true)?;
    sock.bind(&socket2::SockAddr::from(std::net::SocketAddr::from((
        [0, 0, 0, 0],
        port,
    ))))?;
    sock.listen(128)?;
    let listener: TcpListener = sock.into();
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { continue };
            let mut buf = [0u8; 512];
            let n = stream.read(&mut buf).unwrap_or(0);
            let request = String::from_utf8_lossy(&buf[..n]).to_string();
            let target = request.split(' ').nth(1).unwrap_or("/");
            if let Some((_, query)) = target.split_once('?') {
                for pair in query.split('&') {
                    match pair.split_once('=') {
                        Some(("tx", v)) => {
                            DIR_TX.store(v == "1", std::sync::atomic::Ordering::Relaxed)
                        }
                        Some(("rx", v)) => {
                            DIR_RX.store(v == "1", std::sync::atomic::Ordering::Relaxed)
                        }
                        Some(("pps", v)) => {
                            if let Ok(rate) = v.parse::<u64>() {
                                PPS.store(rate, std::sync::atomic::Ordering::Relaxed);
                            }
                        }
                        _ => {}
                    }
                }
            }
            let (tx, rx) = dirs();
            let pps = PPS.load(std::sync::atomic::Ordering::Relaxed);
            let body = format!("{{\"tx\":{},\"rx\":{},\"pps\":{}}}", tx as u8, rx as u8, pps);
            let _ = stream.write_all(
                format!(
                    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                    body.len(),
                    body
                )
                .as_bytes(),
            );
            let _ = stream.flush();
        }
    });
    Ok(())
}

struct PeerTotals {
    tx_frames: u64,
    tx_bytes: u64,
    rx_frames: u64,
    rx_bytes: u64,
    bad: u64,
    raw: u64,
    skip: u64,
    second: u64,
    printed: u64,
}

impl PeerTotals {
    fn new() -> Self {
        PeerTotals {
            tx_frames: 0,
            tx_bytes: 0,
            rx_frames: 0,
            rx_bytes: 0,
            bad: 0,
            raw: 0,
            skip: 0,
            second: 0,
            printed: 0,
        }
    }

    fn tick(&mut self, started: Instant) {
        let second = started.elapsed().as_secs();
        if second > self.second {
            self.second = second;
            self.report(second);
        }
    }

    fn report(&mut self, second: u64) {
        if second <= self.printed {
            return;
        }
        self.printed = second;
        println!(
            "{second},{},{},{},{},{},{},{}",
            self.tx_frames, self.tx_bytes, self.rx_frames, self.rx_bytes, self.bad, self.raw,
            self.skip
        );
        self.tx_frames = 0;
        self.tx_bytes = 0;
        self.rx_frames = 0;
        self.rx_bytes = 0;
        self.bad = 0;
        self.raw = 0;
        self.skip = 0;
    }
}

fn send_loop<F>(opts: &Options, mut build: F) -> Stats
where
    F: FnMut(&mut [u8]) -> Option<usize>,
{
    let mut stats = Stats::new();
    let mut pkt = vec![0u8; MAX_PAYLOAD + 256];
    let started = Instant::now();
    let mut deadline = started;
    let mut second = 0u64;
    while running(started, opts.seconds) {
        wait_until(deadline);
        match build(&mut pkt) {
            Some(len) => {
                stats.frames += 1;
                stats.bytes += len as u64;
            }
            None => stats.bad += 1,
        }
        if started.elapsed() >= Duration::from_secs(second + 1) {
            second += 1;
            stats.report(second);
        }
        deadline = next_deadline(deadline, opts.pps);
    }
    stats
}

fn esp_sink_loop(
    sock: &UdpSocket,
    plane: &mut kyberlink_peer::esp::DataPlane,
    spi: Option<[u8; 4]>,
    opts: &Options,
) {
    let _ = sock.set_read_timeout(Some(Duration::from_millis(20)));
    let mut stats = Stats::new();
    let mut buf = [0u8; 2048];
    let mut out = [0u8; 2048];
    let started = Instant::now();
    let mut second = 0u64;
    println!("second,frames,bytes,bad,skipped");
    while running(started, opts.seconds) {
        if let Ok((n, _)) = sock.recv_from(&mut buf) {
            if spi.is_some_and(|want| n < 20 || buf[..4] != want) {
                continue;
            }
            match plane.open(&buf[..n], &mut out) {
                Some(len) => {
                    stats.frames += 1;
                    stats.bytes += len as u64;
                }
                None => stats.bad += 1,
            }
        }
        if started.elapsed() >= Duration::from_secs(second + 1) {
            second += 1;
            stats.report(second);
        }
    }
}

fn esp_source(
    sa: &kyberlink_crypto::handshake::SaParams,
    initiator: bool,
    opts: &Options,
) -> Stats {
    let mut plane = kyberlink_peer::esp::DataPlane::from_sa(sa, initiator);
    let mut inner = vec![0u8; MAX_PAYLOAD + 64];
    let body = vec![0x5au8; opts.size];
    let n = inner_frame(&mut inner, &body);
    let data_addr = match opts.peer.rsplit_once(':') {
        Some((host, port)) => format!("{host}:{}", port.parse::<u16>().unwrap_or(4501) - 1),
        None => opts.peer.clone(),
    };
    let link = match UdpLink::bind("0.0.0.0:0", data_addr.as_str()) {
        Ok(link) => link,
        Err(err) => {
            eprintln!("bind failed: {err}");
            return Stats::new();
        }
    };
    println!("second,frames,bytes,bad");
    send_loop(opts, |pkt| {
        let len = plane.seal(&inner[..n], pkt)?;
        link.send(&pkt[..len]);
        Some(len)
    })
}

fn plain_source(opts: &Options) -> Stats {
    let sock = match UdpSocket::bind("0.0.0.0:0") {
        Ok(sock) => sock,
        Err(err) => {
            eprintln!("bind failed: {err}");
            return Stats::new();
        }
    };
    if let Err(err) = sock.set_broadcast(true) {
        eprintln!("broadcast unavailable: {err}");
    }
    let body = vec![0x5au8; opts.size];
    println!("second,frames,bytes,bad");
    send_loop(opts, |pkt| {
        pkt[..body.len()].copy_from_slice(&body);
        sock.send_to(&pkt[..body.len()], opts.peer.as_str()).ok()
    })
}

fn plain_sink(opts: &Options) -> ExitCode {
    let sock = match UdpSocket::bind(opts.bind.as_str()) {
        Ok(sock) => sock,
        Err(err) => {
            eprintln!("bind failed: {err}");
            return ExitCode::FAILURE;
        }
    };
    widen_recv_buffer(&sock);
    let _ = sock.set_read_timeout(Some(Duration::from_millis(50)));
    println!("second,frames,bytes,bad");
    let mut stats = Stats::new();
    let started = Instant::now();
    let mut second = 0u64;
    let mut buf = vec![0u8; 2048];
    while running(started, opts.seconds) {
        if let Ok((n, _)) = sock.recv_from(&mut buf) {
            stats.frames += 1;
            stats.bytes += n as u64;
        }
        if started.elapsed() >= Duration::from_secs(second + 1) {
            second += 1;
            stats.report(second);
        }
    }
    ExitCode::SUCCESS
}

fn drain_esp(plane: &mut kyberlink_peer::esp::DataPlane, spi: Option<[u8; 4]>, stats: &mut Stats) {
    let frames: Vec<Vec<u8>> = {
        let mut held = RX_FRAMES.lock();
        core::mem::take(&mut *held)
    };
    for frame in frames {
        if let Some(want) = spi {
            if frame.len() < 20 || frame[..4] != want {
                continue;
            }
        }
        let mut out = [0u8; 2048];
        match plane.open(&frame, &mut out) {
            Some(n) => {
                stats.frames += 1;
                stats.bytes += n as u64;
            }
            None => stats.bad += 1,
        }
    }
}

fn inner_frame(out: &mut [u8], payload: &[u8]) -> usize {
    out[..6].copy_from_slice(&[0xb0, 0x25, 0xaa, 0x82, 0xcc, 0xee]);
    out[6..12].copy_from_slice(&[0x02, 0x00, 0x00, 0x00, 0x00, 0x07]);
    out[12..14].copy_from_slice(&[0x08, 0x00]);
    let p = 14;
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
    let q = p + 20;
    out[q..q + 2].copy_from_slice(&9999u16.to_be_bytes());
    out[q + 2..q + 4].copy_from_slice(&9999u16.to_be_bytes());
    out[q + 4..q + 6].copy_from_slice(&((8 + payload.len()) as u16).to_be_bytes());
    out[q + 8..q + 8 + payload.len()].copy_from_slice(payload);
    q + 8 + payload.len()
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


fn data_addr_of(peer: &str) -> String {
    match peer.rsplit_once(':') {
        Some((host, port)) => format!("{host}:{}", port.parse::<u16>().unwrap_or(4501) - 1),
        None => peer.to_string(),
    }
}

fn esp_peer_loop(
    plane: &mut kyberlink_peer::esp::DataPlane,
    spi: [u8; 4],
    recv_sock: &UdpSocket,
    opts: &Options,
) -> ExitCode {
    let link = match UdpLink::bind("0.0.0.0:0", data_addr_of(&opts.peer).as_str()) {
        Ok(link) => link,
        Err(err) => {
            eprintln!("bind failed: {err}");
            return ExitCode::FAILURE;
        }
    };
    let mut inner = vec![0u8; MAX_PAYLOAD + 64];
    let body = vec![0x5au8; opts.size];
    let n = inner_frame(&mut inner, &body);
    let mut pkt = vec![0u8; MAX_PAYLOAD + 256];
    let mut buf = vec![0u8; 2048];
    let mut out = [0u8; 2048];
    let _ = recv_sock.set_nonblocking(true);
    let started = Instant::now();
    let mut deadline = started;
    let mut totals = PeerTotals::new();
    println!("second,tx_frames,tx_bytes,rx_frames,rx_bytes,bad,raw,skip");
    while running(started, opts.seconds) {
        let (tx_on, rx_on) = dirs();
        if tx_on {
            wait_until(deadline);
            if let Some(len) = plane.seal(&inner[..n], &mut pkt) {
                link.send(&pkt[..len]);
                totals.tx_frames += 1;
                totals.tx_bytes += len as u64;
            } else {
                totals.bad += 1;
            }
            let pps = PPS.load(std::sync::atomic::Ordering::Relaxed);
            deadline = if pps == 0 {
                Instant::now()
            } else {
                next_deadline(deadline, pps)
            };
            if deadline < Instant::now() {
                deadline = Instant::now();
            }
        } else {
            deadline = Instant::now();
        }
        if rx_on {
            for _ in 0..1024 {
                match recv_sock.recv_from(&mut buf) {
                    Ok((len, _)) => {
                        totals.raw += 1;
                        if len < 20 || buf[..4] != spi {
                            totals.skip += 1;
                            continue;
                        }
                        match plane.open(&buf[..len], &mut out) {
                            Some(m) => {
                                totals.rx_frames += 1;
                                totals.rx_bytes += m as u64;
                            }
                            None => totals.bad += 1,
                        }
                    }
                    Err(_) => break,
                }
            }
        } else if !tx_on {
            sleep(Duration::from_micros(500));
        }
        totals.tick(started);
    }
    ExitCode::SUCCESS
}

fn plain_peer(opts: &Options) -> ExitCode {
    let rx = match UdpSocket::bind(opts.bind.as_str()) {
        Ok(sock) => sock,
        Err(err) => {
            eprintln!("bind failed: {err}");
            return ExitCode::FAILURE;
        }
    };
    widen_recv_buffer(&rx);
    let _ = rx.set_nonblocking(true);
    let tx = match UdpSocket::bind("0.0.0.0:0") {
        Ok(sock) => sock,
        Err(err) => {
            eprintln!("bind failed: {err}");
            return ExitCode::FAILURE;
        }
    };
    if let Err(err) = tx.set_broadcast(true) {
        eprintln!("broadcast unavailable: {err}");
    }
    let body = vec![0x5au8; opts.size];
    let mut buf = vec![0u8; 2048];
    let started = Instant::now();
    let mut deadline = started;
    let mut totals = PeerTotals::new();
    println!("second,tx_frames,tx_bytes,rx_frames,rx_bytes,bad,raw,skip");
    while running(started, opts.seconds) {
        let (tx_on, rx_on) = dirs();
        if tx_on {
            wait_until(deadline);
            match tx.send_to(&body, opts.peer.as_str()) {
                Ok(len) => {
                    totals.tx_frames += 1;
                    totals.tx_bytes += len as u64;
                }
                Err(_) => totals.bad += 1,
            }
            let pps = PPS.load(std::sync::atomic::Ordering::Relaxed);
            deadline = if pps == 0 {
                Instant::now()
            } else {
                next_deadline(deadline, pps)
            };
            if deadline < Instant::now() {
                deadline = Instant::now();
            }
        } else {
            deadline = Instant::now();
        }
        if rx_on {
            for _ in 0..1024 {
                match rx.recv_from(&mut buf) {
                    Ok((len, _)) => {
                        totals.rx_frames += 1;
                        totals.rx_bytes += len as u64;
                    }
                    Err(_) => break,
                }
            }
        } else if !tx_on {
            sleep(Duration::from_micros(500));
        }
        totals.tick(started);
    }
    ExitCode::SUCCESS
}

fn run_esp(opts: &Options) -> ExitCode {
    let identity = MemIdentity::from_seed(&opts.seed);
    let local_fp = identity.fingerprint();
    println!("peer fingerprint: {}", hex(&local_fp));
    println!("binding {} -> {}", opts.bind, opts.peer);

    use std::net::ToSocketAddrs;

    let sock = match UdpSocket::bind(opts.bind.as_str()) {
        Ok(sock) => sock,
        Err(err) => {
            eprintln!("bind failed: {err}");
            return ExitCode::FAILURE;
        }
    };
    let peer_addr = match opts.peer.to_socket_addrs().ok().and_then(|mut it| it.next()) {
        Some(addr) => addr,
        None => {
            eprintln!("bad peer address: {}", opts.peer);
            return ExitCode::FAILURE;
        }
    };
    let recv_sock = match sock.try_clone() {
        Ok(sock) => sock,
        Err(err) => {
            eprintln!("clone failed: {err}");
            return ExitCode::FAILURE;
        }
    };
    let link = UdpLink::from_socket(sock, peer_addr);
    let mut peer = Peer::new(
        opts.peer_fp,
        seeds(&opts.seed),
        identity,
        Box::new(Traced {
            inner: link,
            quiet: opts.quiet,
        }),
    );
    peer.set_passive(true);

    if opts.wait_ms > 0 {
        sleep(Duration::from_millis(opts.wait_ms));
    }
    let started = Instant::now();
    let mut sa_seen: Option<[u8; 32]> = None;
    let mut plane: Option<kyberlink_peer::esp::DataPlane> = None;
    let mut spi: Option<[u8; 4]> = None;
    let mut stats = Stats::new();
    let mut second = 0u64;
    let mut header_sent = false;
    let mut last_role = peer.role();
    let mut last_counters = peer.counters();

    while running(started, opts.seconds) {
        match peer.poll() {
            FsmOutcome::Sa(sa) => {
                if sa_seen != Some(sa.sa_salt) {
                    sa_seen = Some(sa.sa_salt);
                    spi = Some(sa.spi_i.to_be_bytes());
                    let initiator = peer.established_role()
                        == kyberlink_core::handshake_fsm::Role::Initiator;
                    println!(
                        "keys: sk_ei_tail={:08x} sk_er_tail={:08x}",
                        u32::from_be_bytes(sa.sk_ei[28..32].try_into().unwrap()),
                        u32::from_be_bytes(sa.sk_er[28..32].try_into().unwrap())
                    );
                    println!(
                        "secure association: spi_i={:08x} spi_r={:08x} salt={}",
                        sa.spi_i,
                        sa.spi_r,
                        hex(&sa.sa_salt)
                    );
                    if opts.mode == Mode::Source {
                        let mut sent = esp_source(&sa, initiator, opts);
                        sent.report(opts.seconds);
                        println!(
                            "done: frames={} bytes={} bad={}",
                            sent.frames, sent.bytes, sent.bad
                        );
                        return ExitCode::SUCCESS;
                    }
                    plane = Some(kyberlink_peer::esp::DataPlane::from_sa(&sa, initiator));
                    if opts.mode == Mode::Peer {
                        return esp_peer_loop(
                            plane.as_mut().unwrap(),
                            spi.unwrap(),
                            &recv_sock,
                            opts,
                        );
                    }
                    if opts.mode == Mode::Sink {
                        esp_sink_loop(&recv_sock, plane.as_mut().unwrap(), spi, opts);
                        return ExitCode::SUCCESS;
                    }
                    CAPTURE.store(
                        opts.mode == Mode::Sink,
                        std::sync::atomic::Ordering::Relaxed,
                    );
                }
            }
            FsmOutcome::Wait => {}
        }
        if let Some(state) = plane.as_mut() {
            if !header_sent && opts.mode == Mode::Sink {
                println!("second,frames,bytes,bad");
                header_sent = true;
            }
            drain_esp(state, spi, &mut stats);
        }
        let role = peer.role();
        let counters = peer.counters();
        if role != last_role || counters != last_counters {
            let d = peer.diag();
            println!(
                "role={role:?} sent={} recv={} diag={}/{}/{}/{}/{}/{}/{}/{}",
                counters.0, counters.1, d[0], d[1], d[2], d[3], d[4], d[5], d[6], d[7]
            );
            last_role = role;
            last_counters = counters;
        }
        if opts.mode == Mode::Sink && Instant::now() >= started + Duration::from_secs(second + 1) {
            second += 1;
            stats.report(second);
        }
        if opts.mode != Mode::Sink || plane.is_none() {
            sleep(TICK);
        }
    }

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

fn main() -> ExitCode {
    let opts = parse();
    PPS.store(opts.pps, std::sync::atomic::Ordering::Relaxed);
    if let Err(err) = serve_control(opts.http) {
        eprintln!("control server unavailable: {err}");
        return ExitCode::FAILURE;
    }
    if opts.plain {
        return match opts.mode {
            Mode::Source => {
                plain_source(&opts);
                ExitCode::SUCCESS
            }
            Mode::Sink => plain_sink(&opts),
            Mode::Peer => plain_peer(&opts),
            Mode::Live => {
                eprintln!("--plain needs --mode source or sink");
                ExitCode::FAILURE
            }
        };
    }
    run_esp(&opts)
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
