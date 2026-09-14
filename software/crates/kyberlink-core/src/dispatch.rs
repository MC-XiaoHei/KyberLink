use core::fmt::Write;
use core::str::SplitAsciiWhitespace;

use kyberlink_crypto::handshake as hs;
use kyberlink_crypto::mldsa_internal::VK_LEN;

use crate::cfg_msg::Binding;
use crate::cfg_store::{self, CfgError, NorFlash, IDENTITY_BASE, MAGIC_IDENTITY};

pub const FW_VERSION: &str = "0.1";
pub const REPLY_MAX: usize = 192;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Mode {
    Configure,
    Running,
}

impl Mode {
    fn as_str(self) -> &'static str {
        match self {
            Mode::Configure => "cfg",
            Mode::Running => "run",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Action {
    None,
    Spill,
    Halt,
    Resume,
    Rekey,
    Reboot,
}

#[derive(Clone, Copy)]
pub struct Ctx {
    pub mode: Mode,
    pub phase: u8,
}

pub struct LineBuf {
    buf: [u8; REPLY_MAX],
    len: usize,
}

impl Default for LineBuf {
    fn default() -> Self {
        Self::new()
    }
}

impl LineBuf {
    pub const fn new() -> Self {
        LineBuf {
            buf: [0u8; REPLY_MAX],
            len: 0,
        }
    }

    pub fn as_str(&self) -> &str {
        core::str::from_utf8(&self.buf[..self.len]).unwrap_or("")
    }
}

impl Write for LineBuf {
    fn write_str(&mut self, s: &str) -> core::fmt::Result {
        let n = (REPLY_MAX - self.len).min(s.len());
        self.buf[self.len..self.len + n].copy_from_slice(&s.as_bytes()[..n]);
        self.len += n;
        Ok(())
    }
}

pub fn hex_decode(s: &str, out: &mut [u8]) -> Result<usize, CfgError> {
    let b = s.as_bytes();
    let (pairs, rest) = b.as_chunks::<2>();
    if !rest.is_empty() || pairs.len() > out.len() {
        return Err(CfgError::Value);
    }
    for (i, pair) in pairs.iter().enumerate() {
        out[i] = (hex_nibble(pair[0])? << 4) | hex_nibble(pair[1])?;
    }
    Ok(pairs.len())
}

fn hex_nibble(c: u8) -> Result<u8, CfgError> {
    match c {
        b'0'..=b'9' => Ok(c - b'0'),
        b'a'..=b'f' => Ok(c - b'a' + 10),
        b'A'..=b'F' => Ok(c - b'A' + 10),
        _ => Err(CfgError::Value),
    }
}

fn hex_arr<const N: usize>(s: &str) -> Result<[u8; N], CfgError> {
    if s.len() != N * 2 {
        return Err(CfgError::Value);
    }
    let mut out = [0u8; N];
    hex_decode(s, &mut out)?;
    Ok(out)
}

fn hex_write(out: &mut LineBuf, b: &[u8]) {
    for byte in b {
        let _ = write!(out, "{byte:02x}");
    }
}

fn ip_parse(s: &str) -> Result<[u8; 4], CfgError> {
    let mut ip = [0u8; 4];
    let mut it = s.split('.');
    for octet in ip.iter_mut() {
        *octet = it
            .next()
            .and_then(|p| p.parse::<u8>().ok())
            .ok_or(CfgError::Value)?;
    }
    if it.next().is_some() {
        return Err(CfgError::Value);
    }
    Ok(ip)
}

fn ip_write(out: &mut LineBuf, ip: &[u8; 4]) {
    let _ = write!(out, "{}.{}.{}.{}", ip[0], ip[1], ip[2], ip[3]);
}

fn err(out: &mut LineBuf, reason: &str) -> Action {
    let _ = writeln!(out, "ERR {reason}");
    Action::None
}

fn ok(out: &mut LineBuf) -> Action {
    let _ = writeln!(out, "OK");
    Action::None
}

fn flash_result(out: &mut LineBuf, result: Result<(), CfgError>) -> Action {
    match result {
        Ok(()) => ok(out),
        Err(_) => err(out, "flash"),
    }
}

fn update_binding<F: NorFlash>(
    flash: &mut F,
    edit: impl FnOnce(&mut Binding),
) -> Result<(), CfgError> {
    let mut b = Binding::load(flash).unwrap_or_default();
    edit(&mut b);
    b.store(flash)
}

fn read_self_fp<F: NorFlash>(flash: &mut F) -> Result<[u8; 32], CfgError> {
    cfg_store::verify(
        flash,
        IDENTITY_BASE,
        &MAGIC_IDENTITY,
        crate::cfg_msg::IDENTITY_LEN as u16,
    )?;
    let mut vk = [0u8; VK_LEN];
    cfg_store::read_payload(flash, IDENTITY_BASE, 0, &mut vk)?;
    Ok(hs::fingerprint(&vk))
}

fn cmd_ping(ctx: &Ctx, out: &mut LineBuf) -> Action {
    let _ = writeln!(out, "PONG kyberlink {} {}", FW_VERSION, ctx.mode.as_str());
    Action::None
}

fn cmd_fpm<F: NorFlash>(flash: &mut F, out: &mut LineBuf) -> Action {
    match read_self_fp(flash) {
        Ok(fp) => {
            let _ = write!(out, "FPM ");
            hex_write(out, &fp);
            let _ = writeln!(out);
            Action::None
        }
        Err(_) => err(out, "no identity"),
    }
}

fn cmd_show<F: NorFlash>(flash: &mut F, out: &mut LineBuf) -> Action {
    match Binding::load(flash) {
        Ok(b) => {
            write_binding(out, &b);
            Action::None
        }
        Err(_) => err(out, "no binding"),
    }
}

fn write_binding(out: &mut LineBuf, b: &Binding) {
    let _ = write!(
        out,
        "ROLE {} PEER ",
        if b.role_initiator { "I" } else { "R" }
    );
    hex_write(out, &b.peer_fp);
    let _ = write!(out, " SRC ");
    hex_write(out, &b.src_mac);
    let _ = write!(out, " ");
    ip_write(out, &b.src_ip);
    let _ = write!(out, " DST ");
    hex_write(out, &b.dst_mac);
    let _ = write!(out, " ");
    ip_write(out, &b.dst_ip);
    let _ = writeln!(out, " PORTS {}/{}", b.src_port, b.dst_port);
}

fn cmd_stat(ctx: &Ctx, out: &mut LineBuf) -> Action {
    let _ = writeln!(out, "STAT phase={}", ctx.phase);
    Action::None
}

fn cmd_fp<F: NorFlash>(arg: Option<&str>, flash: &mut F, out: &mut LineBuf) -> Action {
    match arg.and_then(|s| hex_arr::<32>(s).ok()) {
        Some(fp) => flash_result(out, update_binding(flash, |b| b.peer_fp = fp)),
        None => err(out, "bad fingerprint"),
    }
}

fn cmd_role<F: NorFlash>(arg: Option<&str>, flash: &mut F, out: &mut LineBuf) -> Action {
    match role_of(arg) {
        Some(role) => flash_result(out, update_binding(flash, |b| b.role_initiator = role)),
        None => err(out, "role I|R"),
    }
}

fn role_of(arg: Option<&str>) -> Option<bool> {
    match arg {
        Some("I") => Some(true),
        Some("R") => Some(false),
        _ => None,
    }
}

struct Net {
    src_mac: [u8; 6],
    src_ip: [u8; 4],
    src_port: u16,
    dst_mac: [u8; 6],
    dst_ip: [u8; 4],
    dst_port: u16,
}

impl Net {
    fn parse(args: &mut SplitAsciiWhitespace<'_>) -> Option<Net> {
        Some(Net {
            src_mac: hex_arr::<6>(args.next()?).ok()?,
            src_ip: ip_parse(args.next()?).ok()?,
            src_port: args.next()?.parse().ok()?,
            dst_mac: hex_arr::<6>(args.next()?).ok()?,
            dst_ip: ip_parse(args.next()?).ok()?,
            dst_port: args.next()?.parse().ok()?,
        })
    }

    fn apply(&self, b: &mut Binding) {
        b.src_mac = self.src_mac;
        b.src_ip = self.src_ip;
        b.src_port = self.src_port;
        b.dst_mac = self.dst_mac;
        b.dst_ip = self.dst_ip;
        b.dst_port = self.dst_port;
    }
}

fn cmd_net<F: NorFlash>(
    args: &mut SplitAsciiWhitespace<'_>,
    flash: &mut F,
    out: &mut LineBuf,
) -> Action {
    let Some(net) = Net::parse(args) else {
        return err(out, "NET <smac> <sip> <sport> <dmac> <dip> <dport>");
    };
    flash_result(out, update_binding(flash, |b| net.apply(b)))
}

fn cmd_factory<F: NorFlash>(arg: Option<&str>, flash: &mut F, out: &mut LineBuf) -> Action {
    if arg != Some("CONFIRM") {
        return err(out, "confirm required");
    }
    flash_result(out, cfg_store::clear_all(flash))
}

pub fn exec<F: NorFlash>(line: &str, ctx: &Ctx, flash: &mut F, out: &mut LineBuf) -> Action {
    let mut args = line.split_ascii_whitespace();
    let Some(cmd) = args.next() else {
        return err(out, "empty");
    };
    let configure = ctx.mode == Mode::Configure;
    match cmd {
        "PING" => cmd_ping(ctx, out),
        "FPM" => cmd_fpm(flash, out),
        "SHOW" => cmd_show(flash, out),
        "STAT" => cmd_stat(ctx, out),
        "HALT" if !configure => Action::Halt,
        "RESUME" if configure => Action::Resume,
        "REKEY" if !configure => Action::Rekey,
        "REBOOT" => Action::Reboot,
        "SPK" if configure => Action::Spill,
        "FP" if configure => cmd_fp(args.next(), flash, out),
        "ROLE" if configure => cmd_role(args.next(), flash, out),
        "NET" if configure => cmd_net(&mut args, flash, out),
        "FACTORY" => cmd_factory(args.next(), flash, out),
        "SPK" | "FP" | "ROLE" | "NET" | "HALT" | "RESUME" | "REKEY" => err(out, "busy"),
        _ => err(out, "unknown"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cfg_store::tests::MemFlash;
    use crate::cfg_store::{FrameStream, IDENTITY_PAGES};

    fn run(line: &str, mode: Mode, flash: &mut MemFlash) -> (String, Action) {
        let mut out = LineBuf::new();
        let action = exec(line, &Ctx { mode, phase: 0 }, flash, &mut out);
        (out.as_str().to_string(), action)
    }

    fn seeded_flash() -> MemFlash {
        let mut f = MemFlash::new(0x4_0000);
        let b = Binding {
            role_initiator: true,
            peer_fp: [0xAB; 32],
            src_mac: [0, 1, 2, 3, 4, 5],
            dst_mac: [6, 7, 8, 9, 10, 11],
            src_ip: [10, 0, 0, 1],
            dst_ip: [10, 0, 0, 2],
            src_port: 4500,
            dst_port: 4501,
        };
        b.store(&mut f).unwrap();
        f
    }

    fn write_identity(f: &mut MemFlash, vk_byte: u8) {
        let mut payload = vec![0u8; crate::cfg_msg::IDENTITY_LEN];
        payload[..VK_LEN].fill(vk_byte);
        let mut s =
            FrameStream::begin(f, IDENTITY_BASE, IDENTITY_PAGES, MAGIC_IDENTITY).unwrap();
        for chunk in payload.chunks(251) {
            s.write(f, chunk).unwrap();
        }
        s.finish(f).unwrap();
    }

    #[test]
    fn ping_reports_mode() {
        let mut f = MemFlash::new(0x4_0000);
        let (r, a) = run("PING", Mode::Configure, &mut f);
        assert_eq!(r, "PONG kyberlink 0.1 cfg\n");
        assert_eq!(a, Action::None);
    }

    #[test]
    fn configure_only_commands_rejected_when_running() {
        let mut f = seeded_flash();
        for line in ["SPK", "FP 00", "ROLE I", "NET a b c d e f", "RESUME"] {
            let (r, _) = run(line, Mode::Running, &mut f);
            assert_eq!(r, "ERR busy\n", "line {line}");
        }
        let (r, _) = run("HALT", Mode::Configure, &mut f);
        assert_eq!(r, "ERR busy\n");
        let (r, _) = run("REKEY", Mode::Configure, &mut f);
        assert_eq!(r, "ERR busy\n");
    }

    #[test]
    fn role_and_fp_persist() {
        let mut f = MemFlash::new(0x4_0000);
        let (r, _) = run("ROLE R", Mode::Configure, &mut f);
        assert_eq!(r, "OK\n");
        let (r, _) = run(&format!("FP {}", "cd".repeat(32)), Mode::Configure, &mut f);
        assert_eq!(r, "OK\n");
        let (r, _) = run("SHOW", Mode::Configure, &mut f);
        assert!(r.starts_with("ROLE R PEER cdcd"), "{r}");
        assert!(r.ends_with("PORTS 0/0\n"), "{r}");
    }

    #[test]
    fn net_updates_all_fields() {
        let mut f = MemFlash::new(0x4_0000);
        let (r, _) = run(
            "NET 001122334455 192.168.1.1 4500 66778899aabb 192.168.1.2 4501",
            Mode::Configure,
            &mut f,
        );
        assert_eq!(r, "OK\n");
        let b = Binding::load(&mut f).unwrap();
        assert_eq!(b.src_mac, [0x00, 0x11, 0x22, 0x33, 0x44, 0x55]);
        assert_eq!(b.src_ip, [192, 168, 1, 1]);
        assert_eq!(b.src_port, 4500);
        assert_eq!(b.dst_mac, [0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB]);
        assert_eq!(b.dst_ip, [192, 168, 1, 2]);
        assert_eq!(b.dst_port, 4501);
        assert!(!b.role_initiator);
    }

    #[test]
    fn net_rejects_malformed_fields() {
        let mut f = MemFlash::new(0x4_0000);
        for line in [
            "NET 00112233445 192.168.1.1 4500 66778899aabb 192.168.1.2 4501",
            "NET 001122334455 192.168.1 4500 66778899aabb 192.168.1.2 4501",
            "NET 001122334455 192.168.1.1 70000 66778899aabb 192.168.1.2 4501",
            "NET 001122334455 192.168.1.1 4500 66778899aabb 192.168.1.2",
        ] {
            let (r, _) = run(line, Mode::Configure, &mut f);
            assert!(r.starts_with("ERR"), "{line} -> {r}");
        }
    }

    #[test]
    fn fp_rejects_bad_hex() {
        let mut f = MemFlash::new(0x4_0000);
        let (r, _) = run("FP 00", Mode::Configure, &mut f);
        assert_eq!(r, "ERR bad fingerprint\n");
        let (r, _) = run(&format!("FP {}", "zz".repeat(32)), Mode::Configure, &mut f);
        assert_eq!(r, "ERR bad fingerprint\n");
    }

    #[test]
    fn mode_transitions_emit_actions() {
        let mut f = seeded_flash();
        let (_, a) = run("HALT", Mode::Running, &mut f);
        assert_eq!(a, Action::Halt);
        let (_, a) = run("RESUME", Mode::Configure, &mut f);
        assert_eq!(a, Action::Resume);
        let (_, a) = run("REKEY", Mode::Running, &mut f);
        assert_eq!(a, Action::Rekey);
        let (_, a) = run("REBOOT", Mode::Configure, &mut f);
        assert_eq!(a, Action::Reboot);
        let (_, a) = run("SPK", Mode::Configure, &mut f);
        assert_eq!(a, Action::Spill);
    }

    #[test]
    fn fpm_requires_identity_and_reports_fingerprint() {
        let mut f = MemFlash::new(0x4_0000);
        let (r, _) = run("FPM", Mode::Configure, &mut f);
        assert_eq!(r, "ERR no identity\n");
        write_identity(&mut f, 0x42);
        let (r, _) = run("FPM", Mode::Configure, &mut f);
        let expected = hs::fingerprint(&[0x42u8; VK_LEN]);
        let mut hex = String::new();
        for b in expected {
            hex.push_str(&format!("{b:02x}"));
        }
        assert_eq!(r, format!("FPM {hex}\n"));
    }

    #[test]
    fn factory_requires_confirm_and_clears() {
        let mut f = seeded_flash();
        write_identity(&mut f, 0x42);
        let (r, _) = run("FACTORY", Mode::Configure, &mut f);
        assert_eq!(r, "ERR confirm required\n");
        assert!(Binding::load(&mut f).is_ok());
        let (r, _) = run("FACTORY CONFIRM", Mode::Configure, &mut f);
        assert_eq!(r, "OK\n");
        assert!(Binding::load(&mut f).is_err());
        assert!(read_self_fp(&mut f).is_err());
    }
}
