use std::process::ExitCode;

#[cfg(target_os = "linux")]
fn main() -> ExitCode {
    use std::env;

    use kyberlink_peer::tunnel::{run, TunnelConfig, MAX_MTU};

    let mut cfg = TunnelConfig {
        bind: "0.0.0.0:4501".to_string(),
        peer: "10.2.0.10:4501".to_string(),
        peer_fp: [0u8; 32],
        seed: [0x42u8; 32],
        tun: "kyb0".to_string(),
        mtu: 1400,
        src_mac: [0x02, 0x00, 0x00, 0x00, 0x00, 0x07],
        dst_mac: [0xff; 6],
        queues: 2,
    };
    let mut args = env::args().skip(1);
    while let Some(flag) = args.next() {
        let mut value = || args.next().expect("missing value");
        match flag.as_str() {
            "--bind" => cfg.bind = value(),
            "--peer" => cfg.peer = value(),
            "--peer-fp" => cfg.peer_fp = hex32(&value()),
            "--seed" => cfg.seed = hex32(&value()),
            "--tun" => cfg.tun = value(),
            "--mtu" => cfg.mtu = value().parse().expect("mtu"),
            "--src-mac" => cfg.src_mac = mac6(&value()),
            "--dst-mac" => cfg.dst_mac = mac6(&value()),
            "--queues" => cfg.queues = value().parse().expect("queues"),
            other => panic!("unknown flag {other}"),
        }
    }
    if cfg.mtu > MAX_MTU {
        eprintln!("mtu above {MAX_MTU} does not fit the inner frame");
        return ExitCode::FAILURE;
    }
    match run(&cfg) {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("tunnel failed: {err}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(target_os = "linux")]
fn hex32(text: &str) -> [u8; 32] {
    let raw = unhex(text);
    assert_eq!(raw.len(), 32, "expected 32 bytes");
    let mut out = [0u8; 32];
    out.copy_from_slice(&raw);
    out
}

#[cfg(target_os = "linux")]
fn mac6(text: &str) -> [u8; 6] {
    let raw = unhex(text);
    assert_eq!(raw.len(), 6, "expected 6 bytes");
    let mut out = [0u8; 6];
    out.copy_from_slice(&raw);
    out
}

#[cfg(target_os = "linux")]
fn unhex(text: &str) -> Vec<u8> {
    let bytes = text.as_bytes();
    assert!(bytes.len() % 2 == 0, "hex length must be even");
    bytes
        .chunks(2)
        .map(|pair| {
            let hi = (pair[0] as char).to_digit(16).expect("hex") as u8;
            let lo = (pair[1] as char).to_digit(16).expect("hex") as u8;
            (hi << 4) | lo
        })
        .collect()
}

#[cfg(not(target_os = "linux"))]
fn main() -> ExitCode {
    eprintln!("the tun tunnel is Linux only");
    ExitCode::FAILURE
}
