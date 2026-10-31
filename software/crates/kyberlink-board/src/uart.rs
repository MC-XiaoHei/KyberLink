use core::cell::UnsafeCell;
use core::sync::atomic::Ordering;

use ch32_hal::interrupt::InterruptExt;
use ch32_hal::mode::Blocking;
use ch32_hal::peripherals::{PB6, PB7, USART1};
use ch32_hal::usart::{Config, Uart};
use ch32_hal::Peri;
use portable_atomic::AtomicUsize;

use crate::clock;

const BAUDRATE: u32 = 115_200;
const REMAP_PB6_PB7: u8 = 1;
const RX_CAP: usize = 256;
const RX_MASK: usize = RX_CAP - 1;

struct RxRing {
    buf: UnsafeCell<[u8; RX_CAP]>,
    head: AtomicUsize,
    tail: AtomicUsize,
}

// SAFETY: the producer only writes the slot at `head` before publishing it, and
// the consumer only reads slots below `head`, so the two never touch the same
// byte.
unsafe impl Sync for RxRing {}

impl RxRing {
    const fn new() -> Self {
        Self {
            buf: UnsafeCell::new([0; RX_CAP]),
            head: AtomicUsize::new(0),
            tail: AtomicUsize::new(0),
        }
    }

    fn push(&self, byte: u8) {
        let head = self.head.load(Ordering::Relaxed);
        let next = (head + 1) & RX_MASK;
        if next == self.tail.load(Ordering::Acquire) {
            return;
        }
        // SAFETY: `head` is a slot the consumer has already released.
        unsafe { (*self.buf.get())[head] = byte };
        self.head.store(next, Ordering::Release);
    }

    fn drain(&self, out: &mut [u8]) -> usize {
        let mut n = 0;
        let mut tail = self.tail.load(Ordering::Relaxed);
        while n < out.len() {
            if tail == self.head.load(Ordering::Acquire) {
                break;
            }
            // SAFETY: every slot below `head` holds a published byte.
            out[n] = unsafe { (*self.buf.get())[tail] };
            tail = (tail + 1) & RX_MASK;
            n += 1;
        }
        self.tail.store(tail, Ordering::Release);
        n
    }
}

static RX: RxRing = RxRing::new();

#[ch32_hal::interrupt]
fn USART1() {
    let regs = ch32_hal::pac::USART1;
    loop {
        let statr = regs.statr().read();
        if statr.ore() || statr.fe() || statr.ne() || statr.pe() {
            let _ = regs.datar().read();
        } else if statr.rxne() {
            RX.push(regs.datar().read().dr() as u8);
        } else {
            break;
        }
    }
}

pub struct UartPins {
    pub usart: Peri<'static, USART1>,
    pub tx: Peri<'static, PB6>,
    pub rx: Peri<'static, PB7>,
}

pub enum Read {
    Bytes(usize),
    Idle,
}

pub struct Port {
    uart: Uart<'static, USART1, Blocking>,
}

impl Port {
    pub fn open(pins: UartPins) -> Self {
        let mut config = Config::default();
        config.baudrate = BAUDRATE;
        let uart = Uart::new_blocking::<REMAP_PB6_PB7>(pins.usart, pins.rx, pins.tx, config)
            .expect("usart1 init");
        clock::resync_uart_baud();
        ch32_hal::pac::USART1.ctlr1().modify(|w| w.set_rxneie(true));
        let irq = ch32_hal::interrupt::USART1;
        irq.unpend();
        // SAFETY: USART1 belongs to this port and the handler stays registered.
        unsafe { irq.enable() };
        Self { uart }
    }

    pub fn read(&mut self, buf: &mut [u8]) -> Read {
        match RX.drain(buf) {
            0 => Read::Idle,
            n => Read::Bytes(n),
        }
    }

    pub fn write(&mut self, text: &str) {
        let _ = self.uart.blocking_write(text.as_bytes());
    }
}
