use ch32_hal::mode::Blocking;
use ch32_hal::peripherals::{PB6, PB7, USART1};
use ch32_hal::usart::{Config, Uart};
use ch32_hal::Peri;

use crate::clock;

const BAUDRATE: u32 = 115_200;
const REMAP_PB6_PB7: u8 = 1;

pub struct UartPins {
    pub usart: Peri<'static, USART1>,
    pub tx: Peri<'static, PB6>,
    pub rx: Peri<'static, PB7>,
}

pub enum Read {
    Bytes(usize),
    Framing,
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
        Self { uart }
    }

    pub fn read(&mut self, buf: &mut [u8]) -> Read {
        let regs = ch32_hal::pac::USART1;
        let statr = regs.statr().read();
        if statr.ore() || statr.ne() || statr.fe() || statr.pe() {
            let _ = regs.datar().read();
            return Read::Framing;
        }
        let mut n = 0;
        while n < buf.len() {
            if !regs.statr().read().rxne() {
                break;
            }
            buf[n] = regs.datar().read().dr() as u8;
            n += 1;
        }
        if n == 0 {
            Read::Idle
        } else {
            Read::Bytes(n)
        }
    }

    pub fn write(&mut self, text: &str) {
        let _ = self.uart.blocking_write(text.as_bytes());
    }
}
