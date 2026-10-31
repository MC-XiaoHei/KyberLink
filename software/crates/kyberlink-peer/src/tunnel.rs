#![cfg(target_os = "linux")]

use std::io;
use std::net::{SocketAddr, ToSocketAddrs, UdpSocket};
use std::os::fd::{AsRawFd, RawFd};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::thread::{self, sleep};
use std::time::{Duration, Instant};

use kyberlink_core::handshake_fsm::{FsmOutcome, Role};
use kyberlink_crypto::entropy::KemSeeds;

use crate::esp::{DataPlane, Opener, Sealer, Shards, HEADER};
use crate::identity::MemIdentity;
use crate::peer::Peer;
use crate::tun::TunDevice;
use crate::udp::{widen_recv_buffer, UdpLink};

pub const MAX_MTU: usize = 1408;

const ETH_HEADER: usize = 14;
const ETHERTYPE_IPV4: [u8; 2] = [0x08, 0x00];
const REPORT: Duration = Duration::from_secs(1);
const BATCH: usize = 32;
const RX_SLOT: usize = 2048;
const TX_SLOT: usize = MAX_MTU + 256;
const POLL_MS: i32 = 50;
const SEND_BUFFER: usize = 4 * 1024 * 1024;

#[derive(Clone)]
pub struct TunnelConfig {
    pub bind: String,
    pub peer: String,
    pub peer_fp: [u8; 32],
    pub seed: [u8; 32],
    pub tun: String,
    pub mtu: usize,
    pub src_mac: [u8; 6],
    pub dst_mac: [u8; 6],
    pub queues: usize,
}

#[derive(Default)]
struct Counters {
    tx_frames: AtomicU64,
    tx_bytes: AtomicU64,
    rx_frames: AtomicU64,
    rx_bytes: AtomicU64,
    bad: AtomicU64,
}

impl Counters {
    fn bump(counter: &AtomicU64, by: u64) {
        counter.fetch_add(by, Ordering::Relaxed);
    }

    fn drain(counter: &AtomicU64) -> u64 {
        counter.swap(0, Ordering::Relaxed)
    }
}

pub fn run(cfg: &TunnelConfig) -> io::Result<()> {
    if cfg.mtu > MAX_MTU {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("mtu above {MAX_MTU} does not fit the inner frame"),
        ));
    }
    let queues = TunDevice::open_multi(&cfg.tun, cfg.mtu, cfg.queues.max(1))?;
    let sock = UdpSocket::bind(cfg.bind.as_str())?;
    let handshake_addr = resolve(&cfg.peer)?;
    let recv = sock.try_clone()?;

    let identity = MemIdentity::from_seed(&cfg.seed);
    println!("peer fingerprint: {}", hex(&identity.fingerprint()));
    println!("tunnel {} mtu={} handshake={}", cfg.tun, cfg.mtu, cfg.peer);

    let mut peer = Peer::new(
        cfg.peer_fp,
        seeds(&cfg.seed),
        identity,
        Box::new(UdpLink::from_socket(sock, handshake_addr)),
    );
    peer.set_passive(true);

    let mut watch = Instant::now();
    let (sa, initiator) = loop {
        match peer.poll() {
            FsmOutcome::Sa(sa) => {
                let initiator = peer.established_role() == Role::Initiator;
                println!(
                    "secure association: spi_i={:08x} spi_r={:08x} salt={}",
                    sa.spi_i,
                    sa.spi_r,
                    hex(&sa.sa_salt)
                );
                break (sa, initiator);
            }
            _ => {
                if watch.elapsed() >= REPORT {
                    println!(
                        "waiting: role={:?} sent={} recv={}",
                        peer.role(),
                        peer.counters().0,
                        peer.counters().1
                    );
                    watch = Instant::now();
                }
                sleep(Duration::from_millis(1))
            }
        }
    };
    drop(peer);

    let (_, _) = DataPlane::from_sa(&sa, initiator).split();
    let wire = UdpSocket::bind("0.0.0.0:0")?;
    wire.connect(data_addr(&cfg.peer).as_str())?;
    wire.set_nonblocking(true)?;
    let _ = socket2::SockRef::from(&wire).set_send_buffer_size(SEND_BUFFER);
    widen_recv_buffer(&recv);
    recv.set_nonblocking(true)?;

    let wire = Arc::new(wire);
    let recv = Arc::new(recv);
    let shards = Arc::new(Shards::new(DataPlane::from_sa(&sa, initiator).tx_seq()));
    let counters = Arc::new(Counters::default());
    let mut threads = Vec::with_capacity(queues.len() * 2);
    for queue in queues {
        let queue = Arc::new(queue);
        let cfg = cfg.clone();
        threads.push({
            let counters = Arc::clone(&counters);
            let wire = Arc::clone(&wire);
            let tun = Arc::clone(&queue);
            let shards = Arc::clone(&shards);
            let sealer = DataPlane::from_sa(&sa, initiator).split().0;
            thread::spawn(move || uplink(tun, sealer, shards, wire, cfg, counters))
        });
        threads.push({
            let counters = Arc::clone(&counters);
            let recv = Arc::clone(&recv);
            let tun = Arc::clone(&queue);
            let opener = DataPlane::from_sa(&sa, initiator).split().1;
            thread::spawn(move || downlink(tun, opener, recv, counters))
        });
    }

    println!("second,tx_frames,tx_bytes,rx_frames,rx_bytes,bad");
    let mut second = 0u64;
    let mut mark = Instant::now();
    loop {
        sleep(Duration::from_millis(50));
        if mark.elapsed() < REPORT {
            continue;
        }
        second += 1;
        println!(
            "{},{},{},{},{},{}",
            second,
            Counters::drain(&counters.tx_frames),
            Counters::drain(&counters.tx_bytes),
            Counters::drain(&counters.rx_frames),
            Counters::drain(&counters.rx_bytes),
            Counters::drain(&counters.bad)
        );
        mark = Instant::now();
        if threads.iter().any(|t| t.is_finished()) {
            return Err(io::Error::other("data thread stopped"));
        }
    }
}

fn uplink(
    tun: Arc<TunDevice>,
    mut sealer: Sealer,
    shards: Arc<Shards>,
    wire: Arc<UdpSocket>,
    cfg: TunnelConfig,
    counters: Arc<Counters>,
) {
    let tun_fd = tun.as_raw_fd();
    let wire_fd = wire.as_raw_fd();
    let mut packet = vec![0u8; cfg.mtu + 128];
    let mut frame = vec![0u8; cfg.mtu + ETH_HEADER];
    let mut batch = vec![0u8; BATCH * TX_SLOT];
    let mut iov: Vec<libc::iovec> = vec![unsafe { std::mem::zeroed() }; BATCH];
    let mut mmsg: Vec<libc::mmsghdr> = vec![unsafe { std::mem::zeroed() }; BATCH];

    loop {
        if !readable(tun_fd) {
            continue;
        }
        let mut n = 0usize;
        let mut bytes = 0u64;
        while n < BATCH {
            let len = match tun.read(&mut packet) {
                Ok(0) | Err(_) => break,
                Ok(len) => len,
            };
            let slot = &mut batch[n * TX_SLOT..(n + 1) * TX_SLOT];
            let Some(sealed) = seal_ip(&shards, &mut sealer, &mut frame, slot, &packet[..len], &cfg)
            else {
                continue;
            };
            iov[n] = libc::iovec {
                iov_base: slot.as_mut_ptr().cast(),
                iov_len: sealed,
            };
            mmsg[n].msg_hdr.msg_iov = &mut iov[n];
            mmsg[n].msg_hdr.msg_iovlen = 1;
            bytes += sealed as u64;
            n += 1;
        }
        if n == 0 {
            continue;
        }
        let sent = unsafe { libc::sendmmsg(wire_fd, mmsg.as_mut_ptr(), n as u32, 0) };
        if sent > 0 {
            Counters::bump(&counters.tx_frames, sent as u64);
            Counters::bump(&counters.tx_bytes, bytes);
        }
    }
}

fn downlink(tun: Arc<TunDevice>, mut opener: Opener, recv: Arc<UdpSocket>, counters: Arc<Counters>) {
    let recv_fd = recv.as_raw_fd();
    let mut batch = vec![0u8; BATCH * RX_SLOT];
    let mut iov: Vec<libc::iovec> = vec![unsafe { std::mem::zeroed() }; BATCH];
    let mut mmsg: Vec<libc::mmsghdr> = vec![unsafe { std::mem::zeroed() }; BATCH];

    loop {
        if !readable(recv_fd) {
            continue;
        }
        for slot in 0..BATCH {
            iov[slot] = libc::iovec {
                iov_base: batch[slot * RX_SLOT..].as_mut_ptr().cast(),
                iov_len: RX_SLOT,
            };
            mmsg[slot].msg_hdr.msg_iov = &mut iov[slot];
            mmsg[slot].msg_hdr.msg_iovlen = 1;
            mmsg[slot].msg_hdr.msg_name = std::ptr::null_mut();
            mmsg[slot].msg_hdr.msg_namelen = 0;
        }
        let count = unsafe {
            libc::recvmmsg(
                recv_fd,
                mmsg.as_mut_ptr(),
                BATCH as u32,
                0,
                std::ptr::null_mut(),
            )
        };
        if count <= 0 {
            continue;
        }
        let mut frames = 0u64;
        let mut bytes = 0u64;
        for slot in 0..count as usize {
            let len = mmsg[slot].msg_len as usize;
            let packet = &mut batch[slot * RX_SLOT..slot * RX_SLOT + len];
            match opener.open_in_place(packet) {
                Some(size) if size > ETH_HEADER => {
                    let inner = &packet[HEADER..HEADER + size];
                    if inner[12..14] != ETHERTYPE_IPV4 {
                        Counters::bump(&counters.bad, 1);
                        continue;
                    }
                    if tun.write(&inner[ETH_HEADER..]).is_err() {
                        return;
                    }
                    frames += 1;
                    bytes += (size - ETH_HEADER) as u64;
                }
                _ => Counters::bump(&counters.bad, 1),
            }
        }
        Counters::bump(&counters.rx_frames, frames);
        Counters::bump(&counters.rx_bytes, bytes);
    }
}

fn readable(fd: RawFd) -> bool {
    let mut poll = libc::pollfd {
        fd,
        events: libc::POLLIN,
        revents: 0,
    };
    let ready = unsafe { libc::poll(&mut poll, 1, POLL_MS) };
    ready > 0 && poll.revents & libc::POLLIN != 0
}

fn seal_ip(
    shards: &Shards,
    sealer: &mut Sealer,
    frame: &mut [u8],
    sealed: &mut [u8],
    ip: &[u8],
    cfg: &TunnelConfig,
) -> Option<usize> {
    if ip.len() + ETH_HEADER > frame.len() {
        return None;
    }
    frame[..6].copy_from_slice(&cfg.dst_mac);
    frame[6..12].copy_from_slice(&cfg.src_mac);
    frame[12..ETH_HEADER].copy_from_slice(&ETHERTYPE_IPV4);
    frame[ETH_HEADER..ETH_HEADER + ip.len()].copy_from_slice(ip);
    let total = ETH_HEADER + ip.len();
    shards.seal_with(sealer, &frame[..total], sealed)
}

fn resolve(address: &str) -> io::Result<SocketAddr> {
    address
        .to_socket_addrs()?
        .next()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "no peer address"))
}

fn data_addr(peer: &str) -> String {
    match peer.rsplit_once(':') {
        Some((host, port)) => format!(
            "{host}:{}",
            port.parse::<u16>().unwrap_or(4501).saturating_sub(1)
        ),
        None => peer.to_string(),
    }
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

pub fn hex(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        out.push_str(&format!("{byte:02x}"));
    }
    out
}
