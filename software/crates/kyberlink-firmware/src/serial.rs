use ch32_hal::peripherals::{DMA1_CH4, DMA1_CH5, PB6, PB7, USART1};
use ch32_hal::usart::{Config, InterruptHandler, Uart};
use ch32_hal::Peri;
use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::signal::Signal;
use kyberlink_core::cfg_store::NorFlash;
use kyberlink_core::console::Console;
use kyberlink_core::dispatch::Action;

pub type ActionSignal = Signal<CriticalSectionRawMutex, Action>;

ch32_hal::bind_interrupts!(pub struct Irqs {
    USART1 => InterruptHandler<USART1>;
});

const BAUDRATE: u32 = 115_200;
const REMAP_PB6_PB7: u8 = 1;

pub struct UartPins {
    pub usart: Peri<'static, USART1>,
    pub tx: Peri<'static, PB6>,
    pub rx: Peri<'static, PB7>,
    pub tx_dma: Peri<'static, DMA1_CH4>,
    pub rx_dma: Peri<'static, DMA1_CH5>,
}

pub async fn serve<F: NorFlash>(
    pins: UartPins,
    console: &mut Console,
    flash: &mut F,
    signal: &ActionSignal,
) -> ! {
    let UartPins {
        usart,
        tx,
        rx,
        tx_dma,
        rx_dma,
    } = pins;
    let mut config = Config::default();
    config.baudrate = BAUDRATE;
    let uart = Uart::new::<REMAP_PB6_PB7>(usart, rx, tx, Irqs, tx_dma, rx_dma, config)
        .expect("usart1 init");
    let (mut tx, mut rx) = uart.split();
    let mut buf = [0u8; 64];
    loop {
        let n = match rx.read_until_idle(&mut buf).await {
            Ok(n) => n,
            Err(_) => continue,
        };
        console.set_err(crate::firmware::err_flags());
        for &byte in &buf[..n] {
            let action = console.push(byte, flash);
            if let Some(reply) = console.take_reply() {
                let _ = tx.write(reply.as_bytes()).await;
            }
            match action {
                Action::Rekey | Action::Reboot => signal.signal(action),
                _ => {}
            }
        }
    }
}
