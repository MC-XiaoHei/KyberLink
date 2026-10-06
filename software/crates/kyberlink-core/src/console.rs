use core::fmt::Write;

use crate::cfg_msg;
use crate::cfg_store::{FrameStream, NorFlash, IDENTITY_BASE, IDENTITY_PAGES, MAGIC_IDENTITY};
use crate::dispatch::{self, Action, Ctx, LineBuf, Mode, NoPhy, PhyAccess};

pub const LINE_MAX: usize = 512;

pub struct Console {
    line: [u8; LINE_MAX],
    len: usize,
    mode: Mode,
    phase: u8,
    err: u8,
    spill: Option<FrameStream>,
    out: LineBuf,
    out_ready: bool,
}

impl Default for Console {
    fn default() -> Self {
        Self::new(Mode::Configure)
    }
}

impl Console {
    pub fn new(mode: Mode) -> Self {
        Console {
            line: [0u8; LINE_MAX],
            len: 0,
            mode,
            phase: 0,
            err: 0,
            spill: None,
            out: LineBuf::new(),
            out_ready: false,
        }
    }

    pub fn mode(&self) -> Mode {
        self.mode
    }

    pub fn set_phase(&mut self, phase: u8) {
        self.phase = phase;
    }

    pub fn set_err(&mut self, err: u8) {
        self.err = err;
    }

    pub fn take_reply(&mut self) -> Option<&str> {
        if self.out_ready {
            self.out_ready = false;
            Some(self.out.as_str())
        } else {
            None
        }
    }

    pub fn push<F: NorFlash>(&mut self, byte: u8, flash: &mut F) -> Action {
        self.push_with(byte, flash, &NoPhy)
    }

    pub fn push_with<F: NorFlash, P: PhyAccess>(
        &mut self,
        byte: u8,
        flash: &mut F,
        phy: &P,
    ) -> Action {
        if byte != b'\n' && byte != b'\r' {
            if self.len == LINE_MAX {
                self.len = 0;
                return self.note("ERR line too long");
            }
            self.line[self.len] = byte;
            self.len += 1;
            return Action::None;
        }
        if self.len == 0 {
            return Action::None;
        }
        let mut buf = [0u8; LINE_MAX];
        let n = self.len;
        buf[..n].copy_from_slice(&self.line[..n]);
        self.len = 0;
        let line = core::str::from_utf8(&buf[..n]).unwrap_or("");
        self.out = LineBuf::new();
        let action = self.handle(line, flash, phy);
        self.out_ready = !self.out.as_str().is_empty();
        action
    }

    fn handle<F: NorFlash, P: PhyAccess>(&mut self, line: &str, flash: &mut F, phy: &P) -> Action {
        match self.spill.take() {
            Some(stream) => self.feed_spill(stream, line, flash),
            None => self.run_command(line, flash, phy),
        }
    }

    fn feed_spill<F: NorFlash>(
        &mut self,
        stream: FrameStream,
        line: &str,
        flash: &mut F,
    ) -> Action {
        let mut chunk = [0u8; LINE_MAX / 2];
        match dispatch::hex_decode(line, &mut chunk) {
            Ok(n) if n > 0 => self.append_spill(stream, &chunk[..n], flash),
            _ => self.note("ERR bad hex"),
        }
    }

    fn append_spill<F: NorFlash>(
        &mut self,
        mut stream: FrameStream,
        chunk: &[u8],
        flash: &mut F,
    ) -> Action {
        match stream.write(flash, chunk) {
            Err(_) => self.note("ERR flash"),
            Ok(()) if stream.total() == cfg_msg::IDENTITY_LEN => self.finish_spill(stream, flash),
            Ok(()) => {
                self.spill = Some(stream);
                Action::None
            }
        }
    }

    fn finish_spill<F: NorFlash>(&mut self, stream: FrameStream, flash: &mut F) -> Action {
        match stream.finish(flash) {
            Ok(()) => self.note("OK"),
            Err(_) => self.note("ERR flash"),
        }
    }

    fn run_command<F: NorFlash, P: PhyAccess>(
        &mut self,
        line: &str,
        flash: &mut F,
        phy: &P,
    ) -> Action {
        let ctx = Ctx {
            mode: self.mode,
            phase: self.phase,
            err: self.err,
        };
        let action = dispatch::exec_with(line, &ctx, flash, phy, &mut self.out);
        self.track_mode(action);
        match action {
            Action::Spill => self.begin_spill(flash),
            other => other,
        }
    }

    fn track_mode(&mut self, action: Action) {
        match action {
            Action::Halt => self.mode = Mode::Configure,
            Action::Resume => self.mode = Mode::Running,
            _ => {}
        }
    }

    fn begin_spill<F: NorFlash>(&mut self, flash: &mut F) -> Action {
        match FrameStream::begin(flash, IDENTITY_BASE, IDENTITY_PAGES, MAGIC_IDENTITY) {
            Ok(stream) => {
                self.spill = Some(stream);
                self.note("READY")
            }
            Err(_) => self.note("ERR flash"),
        }
    }

    fn note(&mut self, msg: &str) -> Action {
        self.out = LineBuf::new();
        let _ = writeln!(self.out, "{msg}");
        self.out_ready = true;
        Action::None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cfg_msg::{Binding, IDENTITY_LEN};
    use crate::cfg_store::tests::MemFlash;
    use crate::cfg_store::{read_payload, verify};

    fn push_str(console: &mut Console, flash: &mut MemFlash, s: &str) -> Vec<(Action, String)> {
        let mut events = Vec::new();
        for b in s.bytes() {
            let action = console.push(b, flash);
            if let Some(r) = console.take_reply() {
                events.push((action, r.to_string()));
            } else if action != Action::None {
                events.push((action, String::new()));
            }
        }
        events
    }

    fn identity_payload() -> Vec<u8> {
        (0..IDENTITY_LEN).map(|i| (i % 251) as u8).collect()
    }

    fn hex_of(bytes: &[u8]) -> String {
        let mut s = String::new();
        for b in bytes {
            s.push_str(&format!("{b:02x}"));
        }
        s
    }

    #[test]
    fn command_over_bytes() {
        let mut f = MemFlash::new(0x4_0000);
        let mut c = Console::new(Mode::Configure);
        let events = push_str(&mut c, &mut f, "PING\n");
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].1, "PONG kyberlink 0.1 cfg\n");
    }

    #[test]
    fn empty_line_ignored() {
        let mut f = MemFlash::new(0x4_0000);
        let mut c = Console::new(Mode::Configure);
        let events = push_str(&mut c, &mut f, "\n");
        assert!(events.is_empty());
    }

    #[test]
    fn oversized_line_rejected_then_recovers() {
        let mut f = MemFlash::new(0x4_0000);
        let mut c = Console::new(Mode::Configure);
        let long = "A".repeat(LINE_MAX + 1);
        let events = push_str(&mut c, &mut f, &long);
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].1, "ERR line too long\n");
        let events = push_str(&mut c, &mut f, "PING\n");
        assert_eq!(events[0].1, "PONG kyberlink 0.1 cfg\n");
    }

    #[test]
    fn spill_writes_identity_and_confirmable() {
        let mut f = MemFlash::new(0x4_0000);
        let mut c = Console::new(Mode::Configure);
        let payload = identity_payload();
        let hex = hex_of(&payload);

        let events = push_str(&mut c, &mut f, "SPK CONFIRM\n");
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].1, "READY\n");

        let mut last = Vec::new();
        for line in hex.as_bytes().chunks(LINE_MAX) {
            let mut chunk = String::from(core::str::from_utf8(line).unwrap());
            chunk.push('\n');
            let events = push_str(&mut c, &mut f, &chunk);
            if !events.is_empty() {
                last = events;
            }
        }
        assert_eq!(last.len(), 1);
        assert_eq!(last[0].1, "OK\n");

        verify(&mut f, IDENTITY_BASE, &MAGIC_IDENTITY, IDENTITY_LEN as u16).unwrap();
        let mut out = vec![0u8; IDENTITY_LEN];
        read_payload(&mut f, IDENTITY_BASE, 0, &mut out).unwrap();
        assert_eq!(out, payload);
        assert_eq!(c.mode(), Mode::Configure);
    }

    #[test]
    fn spill_bad_hex_aborts_and_recovers() {
        let mut f = MemFlash::new(0x4_0000);
        let mut c = Console::new(Mode::Configure);
        push_str(&mut c, &mut f, "SPK CONFIRM\n");
        let events = push_str(&mut c, &mut f, "zz\n");
        assert_eq!(events[0].1, "ERR bad hex\n");
        assert!(verify(&mut f, IDENTITY_BASE, &MAGIC_IDENTITY, IDENTITY_LEN as u16).is_err());
        let events = push_str(&mut c, &mut f, "PING\n");
        assert_eq!(events[0].1, "PONG kyberlink 0.1 cfg\n");
    }

    #[test]
    fn halt_flips_mode_and_unlocks_config() {
        let mut f = MemFlash::new(0x4_0000);
        let mut c = Console::new(Mode::Running);
        let events = push_str(&mut c, &mut f, "HALT\n");
        assert_eq!(events[0].0, Action::Halt);
        assert_eq!(c.mode(), Mode::Configure);
        let events = push_str(&mut c, &mut f, &format!("FP {}\n", "ab".repeat(32)));
        assert_eq!(events[0].1, "OK\n");
        assert_eq!(Binding::load(&mut f).unwrap().peer_fp, [0xAB; 32]);
        let events = push_str(&mut c, &mut f, "RESUME\n");
        assert_eq!(events[0].0, Action::Resume);
        assert_eq!(c.mode(), Mode::Running);
    }
}
