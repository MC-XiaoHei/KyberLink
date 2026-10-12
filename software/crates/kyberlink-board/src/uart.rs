use ch32_hal::mode::Blocking;
use ch32_hal::peripherals::{DMA1_CH4, DMA1_CH5, PB6, PB7, USART1};
use ch32_hal::usart::{Config, InterruptHandler, Uart};
use ch32_hal::Peri;

ch32_hal::bind_interrupts!(pub struct Irqs {
    USART1 => InterruptHandler<USART1>;
});

const BAUDRATE: u32 = 115_200;
const REMAP_PB6_PB7: u8 = 1;

pub type BlockingUart = Uart<'static, USART1, Blocking>;

pub struct UartPins {
    pub usart: Peri<'static, USART1>,
    pub tx: Peri<'static, PB6>,
    pub rx: Peri<'static, PB7>,
    pub tx_dma: Peri<'static, DMA1_CH4>,
    pub rx_dma: Peri<'static, DMA1_CH5>,
}

fn config() -> Config {
    let mut cfg = Config::default();
    cfg.baudrate = BAUDRATE;
    cfg
}

pub fn open(pins: UartPins) -> Uart<'static, USART1, ch32_hal::mode::Async> {
    let UartPins {
        usart,
        tx,
        rx,
        tx_dma,
        rx_dma,
    } = pins;
    Uart::new::<REMAP_PB6_PB7>(usart, rx, tx, Irqs, tx_dma, rx_dma, config()).expect("usart1 init")
}

pub fn open_blocking(
    usart: Peri<'static, USART1>,
    rx: Peri<'static, PB7>,
    tx: Peri<'static, PB6>,
) -> BlockingUart {
    Uart::new_blocking::<REMAP_PB6_PB7>(usart, rx, tx, config()).expect("usart1 init")
}
