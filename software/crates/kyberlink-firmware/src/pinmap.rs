use ch32_hal::peripherals::{PA1, PA11, PA4, PA5, PA6, PA7, PB6, PB7, PC6, PC8, PC9};
use ch32_hal::Peri;

pub struct Pins {
    pub spi_sck: Peri<'static, PA5>,
    pub spi_mosi: Peri<'static, PA7>,
    pub spi_miso: Peri<'static, PA6>,
    pub spi_cs: Peri<'static, PA4>,
    pub fpga_rst: Peri<'static, PA1>,
    pub uart_tx: Peri<'static, PB6>,
    pub uart_rx: Peri<'static, PB7>,
    pub phy_rst: Peri<'static, PA11>,
    pub phy_mdc: Peri<'static, PC6>,
    pub wan_mdio: Peri<'static, PC8>,
    pub lan_mdio: Peri<'static, PC9>,
}
