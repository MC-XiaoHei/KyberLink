pub const PAGE: u32 = 256;
pub const IDENTITY_BASE: u32 = 0x0002_0000;
pub const IDENTITY_PAGES: u32 = 160;
pub const BINDING_BASE: u32 = 0x0002_A000;
pub const BINDING_PAGES: u32 = 1;

pub const HEADER_LEN: usize = 16;
pub const MAGIC_IDENTITY: [u8; 8] = *b"KYBLIDNT";
pub const MAGIC_BINDING: [u8; 8] = *b"KYBLCFGN";
pub const VERSION: u8 = 1;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CfgError {
    Flash,
    Magic,
    Version,
    Length,
    Crc,
    Value,
    Unmapped,
}

pub trait NorFlash {
    fn read(&mut self, off: u32, buf: &mut [u8]) -> Result<(), CfgError>;
    fn write_page(&mut self, off: u32, page: &[u8]) -> Result<(), CfgError>;
    fn erase(&mut self, off: u32, len: u32) -> Result<(), CfgError>;
    fn map(&mut self, off: u32, len: usize) -> Option<&'static [u8]>;
}

const fn crc_table() -> [u32; 256] {
    let mut table = [0u32; 256];
    let mut i = 0;
    while i < 256 {
        let mut c = i as u32;
        let mut k = 0;
        while k < 8 {
            c = if c & 1 != 0 {
                0xEDB8_8320 ^ (c >> 1)
            } else {
                c >> 1
            };
            k += 1;
        }
        table[i] = c;
        i += 1;
    }
    table
}

static CRC_TABLE: [u32; 256] = crc_table();

pub struct Crc32 {
    state: u32,
}

impl Default for Crc32 {
    fn default() -> Self {
        Self::new()
    }
}

impl Crc32 {
    pub const fn new() -> Self {
        Crc32 { state: 0xFFFF_FFFF }
    }

    pub fn update(&mut self, data: &[u8]) {
        for &b in data {
            self.state = (self.state >> 8) ^ CRC_TABLE[((self.state ^ b as u32) & 0xFF) as usize];
        }
    }

    pub fn finish(&self) -> u32 {
        !self.state
    }
}

pub fn encode_header(magic: &[u8; 8], len: u16, crc: u32, out: &mut [u8; HEADER_LEN]) {
    out[..8].copy_from_slice(magic);
    out[8] = VERSION;
    out[9..11].copy_from_slice(&len.to_be_bytes());
    out[11] = 0xFF;
    out[12..16].copy_from_slice(&crc.to_be_bytes());
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FrameHeader {
    pub len: u16,
    pub crc: u32,
}

pub fn decode_header(
    hdr: &[u8],
    magic: &[u8; 8],
    max_payload: u16,
) -> Result<FrameHeader, CfgError> {
    if hdr.len() < HEADER_LEN || &hdr[..8] != magic {
        return Err(CfgError::Magic);
    }
    if hdr[8] != VERSION {
        return Err(CfgError::Version);
    }
    let len = u16::from_be_bytes([hdr[9], hdr[10]]);
    if len == 0 || len > max_payload {
        return Err(CfgError::Length);
    }
    Ok(FrameHeader {
        len,
        crc: u32::from_be_bytes([hdr[12], hdr[13], hdr[14], hdr[15]]),
    })
}

pub const HEAD_PAYLOAD: usize = PAGE as usize - HEADER_LEN;

pub struct FrameStream {
    base: u32,
    magic: [u8; 8],
    pages: u32,
    head: [u8; PAGE as usize],
    head_fill: usize,
    page: [u8; PAGE as usize],
    page_fill: usize,
    written: u32,
    crc: Crc32,
    total: usize,
}

impl FrameStream {
    pub fn begin<F: NorFlash>(
        flash: &mut F,
        base: u32,
        pages: u32,
        magic: [u8; 8],
    ) -> Result<Self, CfgError> {
        for i in 0..pages {
            flash.erase(base + i * PAGE, PAGE)?;
        }
        Ok(FrameStream {
            base,
            magic,
            pages,
            head: [0xFF; PAGE as usize],
            head_fill: 0,
            page: [0xFF; PAGE as usize],
            page_fill: 0,
            written: 0,
            crc: Crc32::new(),
            total: 0,
        })
    }

    pub fn total(&self) -> usize {
        self.total
    }

    pub fn write<F: NorFlash>(&mut self, flash: &mut F, data: &[u8]) -> Result<(), CfgError> {
        let cap = self.pages as usize * PAGE as usize - HEADER_LEN;
        if self.total + data.len() > cap {
            return Err(CfgError::Length);
        }
        self.total += data.len();
        self.crc.update(data);
        let mut rest = data;
        if self.head_fill < HEAD_PAYLOAD {
            let n = (HEAD_PAYLOAD - self.head_fill).min(rest.len());
            self.head[HEADER_LEN + self.head_fill..HEADER_LEN + self.head_fill + n]
                .copy_from_slice(&rest[..n]);
            self.head_fill += n;
            rest = &rest[n..];
        }
        while !rest.is_empty() {
            let n = (PAGE as usize - self.page_fill).min(rest.len());
            self.page[self.page_fill..self.page_fill + n].copy_from_slice(&rest[..n]);
            self.page_fill += n;
            rest = &rest[n..];
            if self.page_fill == PAGE as usize {
                self.flush_page(flash)?;
            }
        }
        Ok(())
    }

    fn flush_page<F: NorFlash>(&mut self, flash: &mut F) -> Result<(), CfgError> {
        if 1 + self.written >= self.pages {
            return Err(CfgError::Length);
        }
        flash.write_page(self.base + (1 + self.written) * PAGE, &self.page)?;
        self.written += 1;
        self.page = [0xFF; PAGE as usize];
        self.page_fill = 0;
        Ok(())
    }

    pub fn finish<F: NorFlash>(mut self, flash: &mut F) -> Result<(), CfgError> {
        if self.page_fill > 0 {
            self.flush_page(flash)?;
        }
        let len: u16 = self.total.try_into().map_err(|_| CfgError::Length)?;
        let hdr: &mut [u8; HEADER_LEN] = (&mut self.head[..HEADER_LEN]).try_into().unwrap();
        encode_header(&self.magic, len, self.crc.finish(), hdr);
        flash.write_page(self.base, &self.head)?;
        Ok(())
    }
}

pub fn write_frame<F: NorFlash>(
    flash: &mut F,
    base: u32,
    pages: u32,
    magic: [u8; 8],
    payload: &[u8],
) -> Result<(), CfgError> {
    let mut s = FrameStream::begin(flash, base, pages, magic)?;
    s.write(flash, payload)?;
    s.finish(flash)
}

pub fn verify<F: NorFlash>(
    flash: &mut F,
    base: u32,
    magic: &[u8; 8],
    max_payload: u16,
) -> Result<FrameHeader, CfgError> {
    let mut hdr = [0u8; HEADER_LEN];
    flash.read(base, &mut hdr)?;
    let h = decode_header(&hdr, magic, max_payload)?;
    let mut crc = Crc32::new();
    let mut buf = [0u8; PAGE as usize];
    let mut left = h.len as u32;
    let mut off = base + HEADER_LEN as u32;
    while left > 0 {
        let n = left.min(PAGE) as usize;
        flash.read(off, &mut buf[..n])?;
        crc.update(&buf[..n]);
        off += n as u32;
        left -= n as u32;
    }
    if crc.finish() != h.crc {
        return Err(CfgError::Crc);
    }
    Ok(h)
}

pub fn clear_all<F: NorFlash>(flash: &mut F) -> Result<(), CfgError> {
    for (base, pages) in [
        (IDENTITY_BASE, IDENTITY_PAGES),
        (BINDING_BASE, BINDING_PAGES),
    ] {
        for i in 0..pages {
            flash.erase(base + i * PAGE, PAGE)?;
        }
    }
    Ok(())
}

pub fn read_payload<F: NorFlash>(
    flash: &mut F,
    base: u32,
    off: u32,
    out: &mut [u8],
) -> Result<(), CfgError> {
    flash.read(base + HEADER_LEN as u32 + off, out)
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    pub struct MemFlash {
        mem: Vec<u8>,
    }

    impl MemFlash {
        pub fn new(size: usize) -> Self {
            MemFlash {
                mem: vec![0xFF; size],
            }
        }
    }

    impl NorFlash for MemFlash {
        fn read(&mut self, off: u32, buf: &mut [u8]) -> Result<(), CfgError> {
            let off = off as usize;
            buf.copy_from_slice(&self.mem[off..off + buf.len()]);
            Ok(())
        }

        fn write_page(&mut self, off: u32, page: &[u8]) -> Result<(), CfgError> {
            let off = off as usize;
            for (i, &b) in page.iter().enumerate() {
                if b & self.mem[off + i] != b {
                    return Err(CfgError::Flash);
                }
                self.mem[off + i] &= b;
            }
            Ok(())
        }

        fn erase(&mut self, off: u32, len: u32) -> Result<(), CfgError> {
            let off = off as usize;
            self.mem[off..off + len as usize].fill(0xFF);
            Ok(())
        }

        fn map(&mut self, off: u32, len: usize) -> Option<&'static [u8]> {
            let off = off as usize;
            if off.checked_add(len)? > self.mem.len() {
                return None;
            }
            Some(unsafe { core::slice::from_raw_parts(self.mem.as_ptr().add(off), len) })
        }
    }

    fn payload(n: usize) -> Vec<u8> {
        (0..n).map(|i| (i * 7 + 3) as u8).collect()
    }

    #[test]
    fn crc32_matches_standard_check_value() {
        let mut c = Crc32::new();
        c.update(b"123456789");
        assert_eq!(c.finish(), 0xCBF4_3926);
    }

    #[test]
    fn frame_roundtrip() {
        let mut f = MemFlash::new(0x4_0000);
        let data = payload(600);
        write_frame(&mut f, IDENTITY_BASE, 4, MAGIC_IDENTITY, &data).unwrap();
        let h = verify(&mut f, IDENTITY_BASE, &MAGIC_IDENTITY, 4096).unwrap();
        assert_eq!(h.len as usize, data.len());
        let mut out = vec![0u8; data.len()];
        read_payload(&mut f, IDENTITY_BASE, 0, &mut out).unwrap();
        assert_eq!(out, data);
    }

    #[test]
    fn identity_sized_frame_roundtrip() {
        let mut f = MemFlash::new(0x4_0000);
        let data = payload(crate::cfg_msg::IDENTITY_LEN);
        write_frame(&mut f, IDENTITY_BASE, IDENTITY_PAGES, MAGIC_IDENTITY, &data).unwrap();
        let h = verify(
            &mut f,
            IDENTITY_BASE,
            &MAGIC_IDENTITY,
            crate::cfg_msg::IDENTITY_LEN as u16,
        )
        .unwrap();
        assert_eq!(h.len as usize, crate::cfg_msg::IDENTITY_LEN);
        let mut tail = [0u8; 64];
        read_payload(&mut f, IDENTITY_BASE, 36096, &mut tail).unwrap();
        assert_eq!(&tail, &data[36096..36160]);
    }

    #[test]
    fn streamed_frame_roundtrip() {
        let mut f = MemFlash::new(0x4_0000);
        let data = payload(crate::cfg_msg::IDENTITY_LEN);
        let mut s =
            FrameStream::begin(&mut f, IDENTITY_BASE, IDENTITY_PAGES, MAGIC_IDENTITY).unwrap();
        for chunk in data.chunks(251) {
            s.write(&mut f, chunk).unwrap();
        }
        s.finish(&mut f).unwrap();
        let h = verify(
            &mut f,
            IDENTITY_BASE,
            &MAGIC_IDENTITY,
            crate::cfg_msg::IDENTITY_LEN as u16,
        )
        .unwrap();
        assert_eq!(h.len as usize, crate::cfg_msg::IDENTITY_LEN);
        let mut out = vec![0u8; crate::cfg_msg::IDENTITY_LEN];
        read_payload(&mut f, IDENTITY_BASE, 0, &mut out).unwrap();
        assert_eq!(out, data);
    }

    #[test]
    fn frame_rewrite_ok() {
        let mut f = MemFlash::new(0x4_0000);
        let a = payload(600);
        let b = payload(700);
        write_frame(&mut f, IDENTITY_BASE, 4, MAGIC_IDENTITY, &a).unwrap();
        write_frame(&mut f, IDENTITY_BASE, 4, MAGIC_IDENTITY, &b).unwrap();
        let mut out = vec![0u8; b.len()];
        read_payload(&mut f, IDENTITY_BASE, 0, &mut out).unwrap();
        assert_eq!(out, b);
    }

    #[test]
    fn crc_mismatch_rejected() {
        let mut f = MemFlash::new(0x4_0000);
        let data = payload(600);
        write_frame(&mut f, IDENTITY_BASE, 4, MAGIC_IDENTITY, &data).unwrap();
        let bit = (IDENTITY_BASE + HEADER_LEN as u32 + 300) as usize;
        f.mem[bit] ^= 0x01;
        assert_eq!(
            verify(&mut f, IDENTITY_BASE, &MAGIC_IDENTITY, 4096),
            Err(CfgError::Crc)
        );
    }

    #[test]
    fn power_loss_mid_write_rejected() {
        let mut f = MemFlash::new(0x4_0000);
        let data = payload(600);
        {
            let mut s = FrameStream::begin(&mut f, IDENTITY_BASE, 4, MAGIC_IDENTITY).unwrap();
            s.write(&mut f, &data[..300]).unwrap();
        }
        assert_eq!(
            verify(&mut f, IDENTITY_BASE, &MAGIC_IDENTITY, 4096),
            Err(CfgError::Magic)
        );
    }

    #[test]
    fn blank_region_rejected() {
        let mut f = MemFlash::new(0x4_0000);
        assert_eq!(
            verify(&mut f, IDENTITY_BASE, &MAGIC_IDENTITY, 4096),
            Err(CfgError::Magic)
        );
    }

    #[test]
    fn cross_magic_rejected() {
        let mut f = MemFlash::new(0x4_0000);
        write_frame(&mut f, IDENTITY_BASE, 4, MAGIC_IDENTITY, &payload(64)).unwrap();
        assert_eq!(
            verify(&mut f, IDENTITY_BASE, &MAGIC_BINDING, 4096),
            Err(CfgError::Magic)
        );
    }

    #[test]
    fn oversized_len_rejected() {
        let mut f = MemFlash::new(0x4_0000);
        write_frame(&mut f, IDENTITY_BASE, 4, MAGIC_IDENTITY, &payload(600)).unwrap();
        assert_eq!(
            verify(&mut f, IDENTITY_BASE, &MAGIC_IDENTITY, 256),
            Err(CfgError::Length)
        );
    }

    #[test]
    fn page_spill_rejected() {
        let mut f = MemFlash::new(0x4_0000);
        let mut s = FrameStream::begin(&mut f, IDENTITY_BASE, 1, MAGIC_IDENTITY).unwrap();
        match s.write(&mut f, &payload(300)) {
            Err(CfgError::Length) => {}
            other => panic!("expected Length error, got {other:?}"),
        }
    }
}
