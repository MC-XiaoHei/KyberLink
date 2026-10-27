use ch32_hal::flash::{Blocking as FlashBlocking, Flash};
use ch32_hal::gpio::{Input, Level, Output, Pull, Speed};
use ch32_hal::peripherals::{
    PA1, PA2, PA3, PA4, PA5, PA6, PA7, PC6, PC7, PC8, PC9, SPI1,
};
use ch32_hal::{Peri, Peripherals};

use crate::uart::UartPins;

pub struct SpiPins {
    pub spi: Peri<'static, SPI1>,
    pub sck: Peri<'static, PA5>,
    pub mosi: Peri<'static, PA7>,
    pub miso: Peri<'static, PA6>,
    pub cs: Peri<'static, PA4>,
}

pub struct MdioPins {
    pub mdc: Peri<'static, PC6>,
    pub wan: Peri<'static, PC7>,
    pub lan: Peri<'static, PC8>,
}

pub struct Parts {
    pub board: Board<'static>,
    pub spi: SpiPins,
    pub uart: UartPins,
    pub mdio: MdioPins,
    pub flash: Flash<'static, FlashBlocking>,
}

pub fn take(p: Peripherals) -> Parts {
    Parts {
        board: Board::new(p.PA1, p.PA2, p.PC9, p.PA3),
        spi: SpiPins {
            spi: p.SPI1,
            sck: p.PA5,
            mosi: p.PA7,
            miso: p.PA6,
            cs: p.PA4,
        },
        uart: UartPins {
            usart: p.USART1,
            tx: p.PB6,
            rx: p.PB7,
        },
        mdio: MdioPins {
            mdc: p.PC6,
            wan: p.PC7,
            lan: p.PC8,
        },
        flash: Flash::new_blocking(p.FLASH),
    }
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
            fpga_reset: ActiveLow::new(Output::new(fpga_reset, Level::High, Speed::Low)),
            fpga_reconfig: ActiveLow::new(Output::new(fpga_reconfig, Level::High, Speed::Low)),
            phy_reset: ActiveLow::new(Output::new(phy_reset, Level::High, Speed::Low)),
            fpga_done: Sense::new(Input::new(fpga_done, Pull::None)),
        }
    }
}
