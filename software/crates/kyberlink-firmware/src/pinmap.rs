use ch32_hal::peripherals::{PA11, PA12, PA4, PA5, PA6, PA7, PA8};
use ch32_hal::Peri;

pub struct Pins {
    pub spi_sck: Peri<'static, PA5>,
    pub spi_mosi: Peri<'static, PA7>,
    pub spi_miso: Peri<'static, PA6>,
    pub spi_cs: Peri<'static, PA4>,
    pub fpga_rst: Peri<'static, PA8>,
    pub usb_dm: Peri<'static, PA11>,
    pub usb_dp: Peri<'static, PA12>,
}
