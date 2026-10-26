use ch32_hal::gpio::{Input, Level, Output, Pull, Speed};
use ch32_hal::peripherals::{PA1, PA2, PA3, PA4, PA5, PA6, PA7, PB6, PB7, PC6, PC7, PC8, PC9};
use ch32_hal::Peri;

pub struct Pins {
    pub spi_sck: Peri<'static, PA5>,
    pub spi_mosi: Peri<'static, PA7>,
    pub spi_miso: Peri<'static, PA6>,
    pub spi_cs: Peri<'static, PA4>,
    pub fpga_rst: Peri<'static, PA1>,
    pub fpga_recfg: Peri<'static, PA2>,
    pub fpga_done: Peri<'static, PA3>,
    pub uart_tx: Peri<'static, PB6>,
    pub uart_rx: Peri<'static, PB7>,
    pub phy_rst: Peri<'static, PC9>,
    pub phy_mdc: Peri<'static, PC6>,
    pub wan_mdio: Peri<'static, PC7>,
    pub lan_mdio: Peri<'static, PC8>,
}

pub struct ActiveLow<'d> {
    pin: Output<'d>,
}

impl<'d> ActiveLow<'d> {
    pub fn new(pin: Output<'d>) -> Self {
        Self { pin }
    }

    pub fn enable(&mut self) {
        self.pin.set_low();
    }

    pub fn disable(&mut self) {
        self.pin.set_high();
    }
}

pub struct Sense<'d> {
    pin: Input<'d>,
}

impl<'d> Sense<'d> {
    pub fn new(pin: Input<'d>) -> Self {
        Self { pin }
    }

    pub fn value(&self) -> bool {
        self.pin.is_high()
    }
}

pub struct Board<'d> {
    pub fpga_reset: ActiveLow<'d>,
    pub fpga_reconfig: ActiveLow<'d>,
    pub phy_reset: ActiveLow<'d>,
    pub fpga_done: Sense<'d>,
}

impl<'d> Board<'d> {
    pub fn new(
        fpga_reset: Peri<'d, PA1>,
        fpga_reconfig: Peri<'d, PA2>,
        phy_reset: Peri<'d, PC9>,
        fpga_done: Peri<'d, PA3>,
    ) -> Self {
        Self {
            fpga_reset: ActiveLow::new(Output::new(fpga_reset, Level::Low, Speed::Low)),
            fpga_reconfig: ActiveLow::new(Output::new(fpga_reconfig, Level::High, Speed::Low)),
            phy_reset: ActiveLow::new(Output::new(phy_reset, Level::High, Speed::Low)),
            fpga_done: Sense::new(Input::new(fpga_done, Pull::None)),
        }
    }
}

pub fn clock_config() -> ch32_hal::Config {
    ch32_hal::Config {
        rcc: ch32_hal::rcc::Config::SYSCLK_FREQ_144MHZ_HSI,
        ..Default::default()
    }
}
