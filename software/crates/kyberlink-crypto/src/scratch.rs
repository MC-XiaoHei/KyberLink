
use core::mem::ManuallyDrop;

pub struct KemScratch {
    pub a: [[u16; 256]; 3],
    pub th: [[u16; 256]; 3],
    pub y: [[u16; 256]; 3],
    pub e1: [[u16; 256]; 3],
    pub u: [[u16; 256]; 3],
    pub e2: [u16; 256],
    pub mu: [u16; 256],
    pub v: [u16; 256],
    pub w: [u16; 256],
    pub cv: [u16; 256],
}

impl KemScratch {
    pub const fn new() -> Self {
        Self {
            a: [[0; 256]; 3],
            th: [[0; 256]; 3],
            y: [[0; 256]; 3],
            e1: [[0; 256]; 3],
            u: [[0; 256]; 3],
            e2: [0; 256],
            mu: [0; 256],
            v: [0; 256],
            w: [0; 256],
            cv: [0; 256],
        }
    }
}

impl Default for KemScratch {
    fn default() -> Self {
        Self::new()
    }
}

pub struct MldsaScratch {
    pub z: [[u32; 256]; 5],
    pub pool: [[u32; 256]; 6],
    pub a_row: [[u32; 256]; 1],
    pub t1: [u32; 256],
    pub c_hat: [u32; 256],
    pub h: [[bool; 256]; 6],
    pub w1: [u8; 6 * 128],
    pub packed: [u8; 5 * 256 * 3],
}

impl MldsaScratch {
    pub const fn new() -> Self {
        Self {
            z: [[0; 256]; 5],
            pool: [[0; 256]; 6],
            a_row: [[0; 256]; 1],
            t1: [0; 256],
            c_hat: [0; 256],
            h: [[false; 256]; 6],
            w1: [0; 6 * 128],
            packed: [0; 5 * 256 * 3],
        }
    }
}

impl Default for MldsaScratch {
    fn default() -> Self {
        Self::new()
    }
}

pub struct Scratch {
    area: ScratchArea,
}

impl Scratch {
    pub fn hs_buf(&mut self) -> &mut [u8] {
        // SAFETY: see `kem`.
        unsafe { &mut self.area.hs }
    }
}

impl Default for Scratch {
    fn default() -> Self {
        Self::new()
    }
}

union ScratchArea {
    kem: ManuallyDrop<KemScratch>,
    mldsa: ManuallyDrop<MldsaScratch>,
    hs: [u8; 64 + 32 + 1184 + 1952],
}

impl Scratch {
    pub const fn new() -> Self {
        Scratch {
            area: ScratchArea {
                kem: ManuallyDrop::new(KemScratch::new()),
            },
        }
    }

    pub fn kem(&mut self) -> &mut KemScratch {
        // SAFETY: `area` is initialised, and `kem`/`mldsa` have identical layout
        // requirements (both are plain arrays of integers).
        unsafe { &mut self.area.kem }
    }

    pub fn mldsa(&mut self) -> &mut MldsaScratch {
        // SAFETY: see `kem`.
        unsafe { &mut self.area.mldsa }
    }
}
