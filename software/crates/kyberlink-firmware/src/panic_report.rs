
const USART1: usize = 0x4001_3800;
const TXE: u32 = 1 << 7;

fn put(byte: u8) {
    unsafe {
        let mut spins = 0u32;
        while (USART1 as *const u32).read_volatile() & TXE == 0 {
            spins += 1;
            if spins > 2_000_000 {
                return;
            }
        }
        core::ptr::write_volatile((USART1 + 4) as *mut u32, byte as u32);
    }
}

fn hex(value: usize) {
    for shift in (0..32).step_by(4).rev() {
        let nibble = (value >> shift) & 0xf;
        put(if nibble < 10 { b'0' + nibble as u8 } else { b'a' + (nibble - 10) as u8 });
    }
}

pub fn report(info: &core::panic::PanicInfo<'_>) {
    let sp: usize;
    unsafe { core::arch::asm!("mv {}, sp", out(reg) sp) };

    put(b'\n');
    put(b'P');
    put(b' ');
    hex(sp);
    put(b' ');

    match info.location() {
        Some(location) => {
            for byte in location.file().bytes() {
                put(byte);
            }
            put(b':');
            hex(location.line() as usize);
        }
        None => {
            for byte in b"unknown".iter() {
                put(*byte);
            }
        }
    }

    put(b'\n');
}
