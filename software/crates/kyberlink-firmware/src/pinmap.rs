use ch32_hal::peripherals::{PA1, PA4, PA5, PA6, PA7, PB6, PB7};
use ch32_hal::Peri;

pub struct Pins {
    pub spi_sck: Peri<'static, PA5>,
    pub spi_mosi: Peri<'static, PA7>,
    pub spi_miso: Peri<'static, PA6>,
    pub spi_cs: Peri<'static, PA4>,
    pub fpga_rst: Peri<'static, PA1>,
    pub uart_tx: Peri<'static, PB6>,
    pub uart_rx: Peri<'static, PB7>,
}
