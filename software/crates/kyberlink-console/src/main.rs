use std::io::{ErrorKind, Read, Write};
use std::process::ExitCode;
use std::time::{Duration, Instant};

use kyberlink_core::cfg_msg::IDENTITY_LEN;
use kyberlink_core::console::LINE_MAX;
use kyberlink_crypto::handshake as hs;
use kyberlink_crypto::mldsa_internal::{keygen_internal, sign_precomp_new_into, SignPrecomp};

const CHUNK: usize = LINE_MAX / 2;

const READ_TIMEOUT: Duration = Duration::from_millis(20);
const QUIET: Duration = Duration::from_millis(250);

struct Console {
    port: Box<dyn serialport::SerialPort>,
}

impl Console {
    fn open(path: &str, baud: u32) -> Result<Self, String> {
        let port = serialport::new(path, baud)
            .timeout(READ_TIMEOUT)
            .open()
            .map_err(|e| format!("open {path}: {e}"))?;
        Ok(Self { port })
    }

    fn line(&mut self, text: &str) -> Result<(), String> {
        let mut bytes = Vec::with_capacity(text.len() + 2);
        bytes.extend_from_slice(text.as_bytes());
        bytes.extend_from_slice(b"\r\n");
        self.port.write_all(&bytes).map_err(|e| e.to_string())?;
        self.port.flush().map_err(|e| e.to_string())
    }

    fn drain(&mut self, limit: Duration) -> String {
        let start = Instant::now();
        let mut out = Vec::new();
        let mut buf = [0u8; 512];
        let mut last = Instant::now();
        loop {
            if start.elapsed() >= limit {
                break;
            }
            match self.port.read(&mut buf) {
                Ok(0) => {}
                Ok(n) => {
                    out.extend_from_slice(&buf[..n]);
                    last = Instant::now();
                }
                Err(e) if e.kind() == ErrorKind::TimedOut => {
                    if !out.is_empty() && last.elapsed() >= QUIET {
                        break;
                    }
                }
                Err(e) => return format!("read: {e}"),
            }
        }
        String::from_utf8_lossy(&out).into_owned()
    }

    fn command(&mut self, text: &str) -> Result<String, String> {
        let mut last = String::new();
        for _ in 0..3 {
            self.line(text)?;
            last = self.drain(Duration::from_secs(5)).trim().to_string();
            if !last.is_empty() && last != "ERR unknown" {
                break;
            }
            std::thread::sleep(Duration::from_millis(120));
        }
        Ok(last)
    }

    fn expect_ok(&mut self, text: &str) -> Result<String, String> {
        let reply = self.command(text)?;
        if reply.starts_with("OK") {
            Ok(reply)
        } else {
            Err(format!("{text}: {reply}"))
        }
    }
}

fn hex(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        s.push_str(&format!("{b:02x}"));
    }
    s
}

fn unhex(text: &str) -> Result<Vec<u8>, String> {
    let text = text.strip_prefix("0x").unwrap_or(text);
    if !text.len().is_multiple_of(2) {
        return Err("hex length must be even".into());
    }
    let mut out = Vec::with_capacity(text.len() / 2);
    let bytes = text.as_bytes();
    for pair in bytes.chunks(2) {
        let hi = (pair[0] as char)
            .to_digit(16)
            .ok_or_else(|| format!("bad hex {:?}", pair))?;
        let lo = (pair[1] as char)
            .to_digit(16)
            .ok_or_else(|| format!("bad hex {:?}", pair))?;
        out.push((hi << 4 | lo) as u8);
    }
    Ok(out)
}

fn identity_payload(seed: &[u8; 32]) -> Vec<u8> {
    let (vk, sk) = keygen_internal(seed);
    let mut precomp = SignPrecomp::default();
    sign_precomp_new_into(&mut precomp, &sk);
    let kk = hs::kk_of(&sk);
    let tr = hs::tr_of(&sk);
    let mut payload = Vec::with_capacity(IDENTITY_LEN);
    payload.extend_from_slice(&vk);
    payload.extend_from_slice(&kk);
    payload.extend_from_slice(&tr);
    payload.extend_from_slice(precomp.as_bytes());
    payload
}

struct Options {
    port: String,
    baud: u32,
    command: String,
    args: Vec<String>,
    net: Option<String>,
    peer_fp: Option<String>,
}

fn parse(usage: &str) -> Result<Options, String> {
    let mut it = std::env::args().skip(1);
    let mut port = None;
    let mut baud = 115_200;
    let mut net = None;
    let mut peer_fp = None;
    let mut rest = Vec::new();

    while let Some(arg) = it.next() {
        match arg.as_str() {
            "--port" => port = it.next(),
            "--baud" => {
                baud = it
                    .next()
                    .and_then(|v| v.parse().ok())
                    .ok_or("--baud needs a number")?
            }
            "--net" => {
                let mut parts = Vec::new();
                for _ in 0..6 {
                    parts.push(it.next().ok_or("--net needs 6 fields")?);
                }
                net = Some(parts.join(" "));
            }
            "--peer-fp" => peer_fp = it.next(),
            "-h" | "--help" => return Err(usage.to_string()),
            other => rest.push(other.to_string()),
        }
    }

    let port = port.ok_or("--port is required")?;
    let mut rest = rest.into_iter();
    let command = rest.next().ok_or_else(|| usage.to_string())?;
    Ok(Options {
        port,
        baud,
        command,
        args: rest.collect(),
        net,
        peer_fp,
    })
}

fn provision(console: &mut Console, opts: &Options) -> Result<(), String> {
    let seed_text = opts
        .args
        .first()
        .ok_or("provision needs a 32-byte seed in hex")?;
    let seed: [u8; 32] = unhex(seed_text)?
        .try_into()
        .map_err(|_| "seed must be 32 bytes")?;

    println!("identity: deriving from seed");
    let payload = identity_payload(&seed);

    let pong = console.command("PING")?;
    if !pong.contains("PONG") {
        return Err(format!("device did not answer PING: {pong}"));
    }
    if !pong.contains("cfg") {
        return Err(format!(
            "device is not in configure mode, run FACTORY CONFIRM first: {pong}"
        ));
    }

    console.line("SPK CONFIRM")?;
    let ready = console.drain(Duration::from_secs(30));
    if !ready.contains("READY") {
        return Err(format!("SPK CONFIRM: {ready}"));
    }

    let lines = payload.len() / CHUNK + usize::from(!payload.len().is_multiple_of(CHUNK));
    println!("identity: {} bytes in {} lines", payload.len(), lines);
    for (i, chunk) in payload.chunks(CHUNK).enumerate() {
        console.line(&hex(chunk))?;
        if (i + 1) % 32 == 0 || i + 1 == lines {
            print!("  {}/{}\r", i + 1, lines);
            std::io::stdout().flush().ok();
        }
        std::thread::sleep(Duration::from_millis(20));
    }

    let reply = console.drain(Duration::from_secs(60));
    println!();
    if !reply.contains("OK") {
        return Err(format!("identity write failed: {reply}"));
    }

    if let Some(net) = &opts.net {
        console.expect_ok(&format!("NET {net}"))?;
        println!("binding: {net}");
    }
    if let Some(fp) = &opts.peer_fp {
        if unhex(fp)?.len() != 32 {
            return Err("peer fingerprint must be 32 bytes".into());
        }
        console.expect_ok(&format!("FP {fp}"))?;
        println!("peer fingerprint: {fp}");
    }

    println!("device fingerprint: {}", console.command("FPM")?);
    println!("binding: {}", console.command("SHOW")?);
    Ok(())
}

const USAGE: &str = "\
usage: kyberlink-console --port <COMx> [--baud 115200] <command>

commands:
  ping | stat | show | fpm | reboot
  provision <seed-hex> [--net <smac> <sip> <sport> <dmac> <dip> <dport>] [--peer-fp <hex>]
  net <smac> <sip> <sport> <dmac> <dip> <dport>
  fp <hex>
  factory confirm
  raw <line>";

fn run(opts: &Options) -> Result<(), String> {
    let mut console = Console::open(&opts.port, opts.baud)?;
    match opts.command.as_str() {
        "provision" => provision(&mut console, opts),
        "net" => {
            if opts.args.len() != 6 {
                return Err("net needs 6 fields".into());
            }
            println!("{}", console.expect_ok(&format!("NET {}", opts.args.join(" ")))?);
            Ok(())
        }
        "fp" => {
            let fp = opts.args.first().ok_or("fp needs a fingerprint")?;
            println!("{}", console.expect_ok(&format!("FP {fp}"))?);
            Ok(())
        }
        "factory" => {
            println!("{}", console.expect_ok("FACTORY CONFIRM")?);
            Ok(())
        }
        "raw" => {
            println!("{}", console.command(&opts.args.join(" "))?);
            Ok(())
        }
        "ping" | "stat" | "show" | "fpm" | "reboot" => {
            println!("{}", console.command(&opts.command.to_uppercase())?);
            Ok(())
        }
        other => Err(format!("unknown command {other}\n\n{USAGE}")),
    }
}

fn main() -> ExitCode {
    let opts = match parse(USAGE) {
        Ok(opts) => opts,
        Err(text) => {
            eprintln!("{text}");
            return ExitCode::from(2);
        }
    };
    match run(&opts) {
        Ok(()) => ExitCode::SUCCESS,
        Err(text) => {
            eprintln!("error: {text}");
            ExitCode::FAILURE
        }
    }
}
