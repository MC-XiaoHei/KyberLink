#![no_std]
#![no_main]

use core::arch::asm;
use core::panic::PanicInfo;

const UART0_BASE: usize = 0xfff50000;
const GPIO_BASE: usize = 0xfffc0000;

const UART_CTRL: *mut u32 = UART0_BASE as *mut u32;
const UART_DATA: *mut u32 = (UART0_BASE + 4) as *mut u32;
const GPIO_OUT: *mut u32 = (GPIO_BASE + 4) as *mut u32;

const CTRL_EN: u32 = 1 << 0;
const CTRL_PRSC_LSB: u32 = 3;
const CTRL_BAUD_LSB: u32 = 6;

const CLOCK_HZ: u32 = 50_000_000;
const BAUD: u32 = 19_200;

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
    let baud = div - 1;
    CTRL_EN | (prsc << CTRL_PRSC_LSB) | (baud << CTRL_BAUD_LSB)
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
        if b == b'\n' {
            uart_putc(b'\r');
        }
        uart_putc(b);
    }
}

extern "C" {
    static _stack_top: u8;
}

#[no_mangle]
#[link_section = ".text._start"]
pub unsafe extern "C" fn _start() -> ! {
    asm!("
        la gp, __global_pointer$
        la sp, _stack_top
        call main
    ", options(noreturn));
}

#[no_mangle]
pub extern "C" fn main() -> ! {
    unsafe { UART_CTRL.write_volatile(uart_baud_cfg()) };
    unsafe { GPIO_OUT.write_volatile(0xAA) };
    uart_puts("XIP firmware OK\r\n");
    let mut n: u32 = 0;
    loop {
        unsafe { GPIO_OUT.write_volatile(0xAA | ((n & 1) << 1)) };
        for _ in 0..200_000 {
            unsafe { asm!("nop") };
        }
        n = n.wrapping_add(1);
    }
}

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    loop {
        unsafe { asm!("nop") };
    }
}
