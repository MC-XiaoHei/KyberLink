#![no_std]
#![no_main]

use core::arch::asm;
use kyberlink_crypto::handshake as hs;

const UART0_BASE: usize = 0xfff50000;
const GPIO_BASE: usize = 0xfffc0000;
const MGMT_BASE: usize = 0xf0000200;
const BC_BASE: usize = 0xf0000100;

const UART_CTRL: *mut u32 = UART0_BASE as *mut u32;
const UART_DATA: *mut u32 = (UART0_BASE + 4) as *mut u32;
const GPIO_OUT: *mut u32 = (GPIO_BASE + 4) as *mut u32;

const MGMT_STATUS: *mut u32 = MGMT_BASE as *mut u32;
const MGMT_RD: *mut u32 = (MGMT_BASE + 4) as *mut u32;
const MGMT_WR: *mut u32 = (MGMT_BASE + 8) as *mut u32;
const MGMT_CMD: *mut u32 = (MGMT_BASE + 0xc) as *mut u32;
const MGMT_RLEN: *mut u32 = (MGMT_BASE + 0x10) as *mut u32;

const CTRL_EN: u32 = 1 << 0;
const CTRL_PRSC_LSB: u32 = 3;
const CTRL_BAUD_LSB: u32 = 6;

const CLOCK_HZ: u32 = 50_000_000;
const BAUD: u32 = 19_200;

const SEED_KEM_D: [u8; 32] = [0x11; 32];
const SEED_KEM_Z: [u8; 32] = [0x12; 32];
const SEED_DSA: [u8; 32] = [0x22; 32];
const NONCE: [u8; 32] = [0x55; 32];
const ROLE_INITIATOR: bool = true;

static mut PEER_FP: [u8; 32] = [0; 32];
static mut PEER_IP: [u8; 4] = [0; 4];
static mut CFG_VALID: bool = false;

fn uart_baud_cfg() -> u32 {
    let mut div = CLOCK_HZ / (2 * BAUD);
    let mut prsc: u32 = 0;
    while div >= 0x400 {
        if prsc == 2 || prsc == 4 {
            div >>= 3;
        } else {
            div >>= 1;
        }
        prsc += 1;
    }
    CTRL_EN | (prsc << CTRL_PRSC_LSB) | ((div - 1) << CTRL_BAUD_LSB)
}

#[inline(never)]
fn uart_putc(c: u8) {
    loop {
        let ctrl = unsafe { UART_CTRL.read_volatile() };
        if ctrl & (1 << 18) != 0 {
            break;
        }
    }
    unsafe { UART_DATA.write_volatile(c as u32) };
}

#[inline(never)]
fn uart_puts(s: &str) {
    for b in s.bytes() {
        uart_putc(b);
    }
}

fn uart_getc() -> Option<u8> {
    let ctrl = unsafe { UART_CTRL.read_volatile() };
    if ctrl & (1 << 16) != 0 {
        Some((unsafe { UART_DATA.read_volatile() } & 0xFF) as u8)
    } else {
        None
    }
}

fn hexval(c: u8) -> Option<u8> {
    match c {
        b'0'..=b'9' => Some(c - b'0'),
        b'a'..=b'f' => Some(c - b'a' + 10),
        b'A'..=b'F' => Some(c - b'A' + 10),
        _ => None,
    }
}

fn parse_hex(s: &[u8], out: &mut [u8]) -> bool {
    if s.len() != out.len() * 2 {
        return false;
    }
    for i in 0..out.len() {
        let hi = match hexval(s[2 * i]) {
            Some(v) => v,
            None => return false,
        };
        let lo = match hexval(s[2 * i + 1]) {
            Some(v) => v,
            None => return false,
        };
        out[i] = (hi << 4) | lo;
    }
    true
}

fn parse_ip(s: &[u8], out: &mut [u8; 4]) -> bool {
    let mut parts = [0u8; 4];
    let mut cur: u32 = 0;
    let mut idx = 0usize;
    for &c in s {
        if c == b'.' {
            if idx >= 4 {
                return false;
            }
            parts[idx] = cur as u8;
            cur = 0;
            idx += 1;
        } else if (b'0'..=b'9').contains(&c) {
            cur = cur * 10 + (c - b'0') as u32;
            if cur > 255 {
                return false;
            }
        } else {
            return false;
        }
    }
    if idx != 3 {
        return false;
    }
    parts[3] = cur as u8;
    *out = parts;
    true
}

fn print_hex(prefix: &str, d: &[u8]) {
    uart_puts(prefix);
    const HEX: &[u8; 16] = b"0123456789abcdef";
    for &b in d {
        uart_putc(HEX[(b >> 4) as usize]);
        uart_putc(HEX[(b & 0xF) as usize]);
    }
    uart_puts("\r\n");
}

extern "C" {
    static _stack_top: u8;
}

#[no_mangle]
#[link_section = ".text._start"]
pub unsafe extern "C" fn _start() -> ! {
    asm!(
        "la gp, __global_pointer$",
        "la sp, _stack_top",
        "call main",
        options(noreturn)
    );
}

fn mgmt_status() -> u32 {
    unsafe { MGMT_STATUS.read_volatile() }
}

fn mgmt_read_word() -> u32 {
    unsafe { MGMT_RD.read_volatile() }
}

fn mgmt_write_word(w: u32) {
    unsafe { MGMT_WR.write_volatile(w) };
}

fn mgmt_cmd(v: u32) {
    unsafe { MGMT_CMD.write_volatile(v) };
}

fn mgmt_set_len(v: u32) {
    unsafe { MGMT_RLEN.write_volatile(v) };
}

fn bc_write(off: usize, val: u32) {
    unsafe { ((BC_BASE + off) as *mut u32).write_volatile(val) };
}

fn write_sa(sa: &hs::SaParams) {
    let sk_ei = &sa.sk_ei;
    let sk_er = &sa.sk_er;
    let salt = &sa.sa_salt;
    for i in 0..8 {
        bc_write(0x00 + 4 * i, u32::from_be_bytes(sk_ei[4 * i..4 * i + 4].try_into().unwrap()));
        bc_write(0x80 + 4 * i, u32::from_be_bytes(sk_er[4 * i..4 * i + 4].try_into().unwrap()));
    }
    bc_write(0x30, sa.spi_i);
    bc_write(0xa0, sa.spi_r);
    bc_write(0x34, u32::from_be_bytes(salt[0..4].try_into().unwrap()));
    bc_write(0x38, u32::from_be_bytes(salt[4..8].try_into().unwrap()));
    bc_write(0x3c, 0);
    bc_write(0xa4, u32::from_be_bytes(salt[0..4].try_into().unwrap()));
    bc_write(0xa8, u32::from_be_bytes(salt[4..8].try_into().unwrap()));
    bc_write(0xac, 0);
    bc_write(0x40, 0);
    bc_write(0xb0, 0);
    bc_write(0x20, 0x3);
    uart_puts("SAok\r\n");
}

static mut BUF: [u8; 8192] = [0; 8192];
static mut LINE: [u8; 96] = [0; 96];

fn req_len() -> usize {
    let s = mgmt_status();
    ((s >> 16) & 0x1fff) as usize
}

fn mgmt_read_bytes(buf: &mut [u8]) {
    let mut i = 0;
    while i < buf.len() {
        let w = mgmt_read_word();
        let mut j = 0;
        while j < 4 && i + j < buf.len() {
            buf[i + j] = (w >> (24 - 8 * j)) as u8;
            j += 1;
        }
        i += 4;
    }
}

fn mgmt_write_bytes(data: &[u8]) {
    let mut i = 0;
    while i < data.len() {
        let mut w: u32 = 0;
        let mut j = 0;
        while j < 4 {
            if i + j < data.len() {
                w |= (data[i + j] as u32) << (24 - 8 * j);
            }
            j += 1;
        }
        mgmt_write_word(w);
        i += 4;
    }
}

fn mgmt_send(len: usize) {
    mgmt_set_len(len as u32);
    mgmt_cmd(2);
}

fn run_handshake_auto() {
    let fp = unsafe { PEER_FP };
    let _ = fp;
    if ROLE_INITIATOR {
        let (mut st, m1) = hs::initiator_start(&SEED_KEM_D, &SEED_KEM_Z, &SEED_DSA, &NONCE);
        unsafe {
            BUF[..hs::M1_LEN].copy_from_slice(&m1);
        }
        let buf = unsafe { &BUF[..hs::M1_LEN] };
        mgmt_write_bytes(buf);
        mgmt_send(hs::M1_LEN);
        uart_puts("M1\r\n");
        loop {
            let s = mgmt_status();
            if s & (1 << 31) != 0 {
                let len = req_len();
                mgmt_cmd(1);
                if len == hs::M2_LEN {
                    let m2 = unsafe { &mut BUF[..hs::M2_LEN] };
                    mgmt_read_bytes(m2);
                    match hs::initiator_recv_m2(&mut st, m2, &unsafe { PEER_FP }) {
                        Ok((m3, spi_i)) => {
                            unsafe {
                                BUF[..hs::M3_LEN].copy_from_slice(&m3);
                            }
                            let b3 = unsafe { &BUF[..hs::M3_LEN] };
                            mgmt_write_bytes(b3);
                            mgmt_send(hs::M3_LEN);
                            uart_puts("M3\r\n");
                            loop {
                                let s2 = mgmt_status();
                                if s2 & (1 << 31) != 0 {
                                    mgmt_cmd(1);
                                    let m4 = unsafe { &mut BUF[..hs::M4_LEN] };
                                    mgmt_read_bytes(m4);
                                    match hs::initiator_recv_m4(&mut st, m4, spi_i) {
                                        Ok(sa) => {
                                            write_sa(&sa);
                                            return;
                                        }
                                        Err(_) => {
                                            uart_puts("M4fail\r\n");
                                            return;
                                        }
                                    }
                                }
                            }
                        }
                        Err(_) => {
                            uart_puts("M2fail\r\n");
                            return;
                        }
                    }
                }
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn main() -> ! {
    unsafe { UART_CTRL.write_volatile(uart_baud_cfg()) };
    unsafe { GPIO_OUT.write_volatile(0xAA) };
    uart_putc(b'X');
    uart_puts("KLink> ");
    let mut n = 0usize;
    loop {
        if let Some(c) = uart_getc() {
            if c == b'\r' || c == b'\n' {
                if n > 0 {
                    let line = unsafe { &LINE[..n] };
                    if line.starts_with(b"fp ") {
                        let mut fp = [0u8; 32];
                        if parse_hex(&line[3..], &mut fp) {
                            unsafe {
                                PEER_FP = fp;
                            }
                            uart_puts("fp ok\r\n");
                        } else {
                            uart_puts("fp bad\r\n");
                        }
                    } else if line.starts_with(b"ip ") {
                        let mut ip = [0u8; 4];
                        if parse_ip(&line[3..], &mut ip) {
                            unsafe {
                                PEER_IP = ip;
                            }
                            print_hex("ip ", &ip);
                        } else {
                            uart_puts("ip bad\r\n");
                        }
                    } else if line == b"show" {
                        print_hex("fp ", &unsafe { PEER_FP });
                        print_hex("ip ", &unsafe { PEER_IP });
                    } else if line == b"start" {
                        uart_puts("start\r\n");
                        run_handshake_auto();
                    } else {
                        uart_puts("?\r\n");
                    }
                }
                uart_puts("KLink> ");
                n = 0;
            } else if n < 96 {
                unsafe {
                    LINE[n] = c;
                }
                n += 1;
            }
        }
    }
}

#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {
        unsafe { asm!("nop") };
    }
}
