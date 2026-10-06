pub const DEVAD: u16 = 0x1F;

pub const PHY_ID: u32 = 0x2000_A231;
pub const PHY_ID_MASK: u32 = 0xFFFF_FFF0;

pub const BMCR: u16 = 0x0000;
pub const BMSR: u16 = 0x0001;
pub const PHYIDR1: u16 = 0x0002;
pub const PHYIDR2: u16 = 0x0003;
pub const ANAR: u16 = 0x0004;
pub const ANLPAR: u16 = 0x0005;
pub const ANER: u16 = 0x0006;
pub const ANNPTR: u16 = 0x0007;
pub const ANNPRR: u16 = 0x0008;
pub const CFG1: u16 = 0x0009;
pub const REGCR: u16 = 0x000D;
pub const ADDAR: u16 = 0x000E;
pub const PHYCR: u16 = 0x0010;
pub const PHYSTS: u16 = 0x0011;
pub const MICR: u16 = 0x0012;
pub const ISR: u16 = 0x0013;
pub const CFG2: u16 = 0x0014;
pub const RECR: u16 = 0x0015;
pub const BISCR: u16 = 0x0016;
pub const STS2: u16 = 0x0017;
pub const LEDCR1: u16 = 0x0018;
pub const LEDCR2: u16 = 0x0019;
pub const LEDCR3: u16 = 0x001A;
pub const CFG3: u16 = 0x001E;
pub const CTRL: u16 = 0x001F;
pub const FLD_CFG: u16 = 0x002D;
pub const FLD_THR_CFG: u16 = 0x002E;
pub const CFG4: u16 = 0x0031;
pub const RGMIICTL: u16 = 0x0032;
pub const RGMIICTL2: u16 = 0x0033;
pub const STRAP_STS1: u16 = 0x006E;
pub const STRAP_STS2: u16 = 0x006F;
pub const BICSR1: u16 = 0x0071;
pub const BICSR2: u16 = 0x0072;
pub const RGMIIDCTL: u16 = 0x0086;
pub const LOOPCR: u16 = 0x00FE;
pub const IO_MUX_CFG: u16 = 0x0170;
pub const GPIO_MUX_CTRL1: u16 = 0x0171;

pub const DIRECT_MAX: u16 = 0x001F;

pub mod bmcr {
    pub const RESET: u16 = 1 << 15;
    pub const LOOPBACK: u16 = 1 << 14;
    pub const SPEED_LSB: u16 = 1 << 13;
    pub const AUTONEG_EN: u16 = 1 << 12;
    pub const POWER_DOWN: u16 = 1 << 11;
    pub const RESTART_AUTONEG: u16 = 1 << 9;
    pub const DUPLEX: u16 = 1 << 8;
    pub const SPEED_MSB: u16 = 1 << 6;
}

pub mod bmsr {
    pub const AUTONEG_DONE: u16 = 1 << 5;
    pub const LINK_UP: u16 = 1 << 2;
}

pub mod physts {
    pub const SPEED_MASK: u16 = 0b11 << 14;
    pub const SPEED_10: u16 = 0b00 << 14;
    pub const SPEED_100: u16 = 0b01 << 14;
    pub const SPEED_1000: u16 = 0b10 << 14;
    pub const DUPLEX: u16 = 1 << 13;
}

pub mod rgmiictl {
    pub const ENABLE: u16 = 1 << 7;
    pub const TX_CLK_DELAY: u16 = 1 << 1;
    pub const RX_CLK_DELAY: u16 = 1 << 0;
    pub const CLK_DELAY_MASK: u16 = TX_CLK_DELAY | RX_CLK_DELAY;
}

pub mod rgmiidctl {
    pub const TX_SHIFT: u16 = 4;
    pub const TX_MASK: u16 = 0xF << TX_SHIFT;
    pub const RX_SHIFT: u16 = 0;
    pub const RX_MASK: u16 = 0xF << RX_SHIFT;
}

pub mod ledcr1 {
    pub const GPIO_SHIFT: u16 = 12;
    pub const LED2_SHIFT: u16 = 8;
    pub const LED1_SHIFT: u16 = 4;
    pub const LED0_SHIFT: u16 = 0;
    pub const SEL_MASK: u16 = 0xF;
}

pub mod ledcr2 {
    pub const GPIO_SHIFT: u16 = 12;
    pub const LED2_SHIFT: u16 = 8;
    pub const LED1_SHIFT: u16 = 4;
    pub const LED0_SHIFT: u16 = 0;
    pub const POLARITY: u16 = 1 << 2;
    pub const DRV_VAL: u16 = 1 << 1;
    pub const DRV_EN: u16 = 1 << 0;
    pub const FIELD_MASK: u16 = 0b111;
}

pub mod ledcr3 {
    pub const BYPASS_STRETCHING: u16 = 1 << 2;
    pub const BLINK_RATE: u16 = 0b11;
}

pub mod strap_sts1 {
    pub const PHY_ADD: u16 = 0xF;
    pub const RGMII_DIS: u16 = 1 << 12;
}

pub mod strap_sts2 {
    pub const TX_SKEW: u16 = 0b111 << 4;
    pub const RX_SKEW: u16 = 0b111;
    pub const INT_TST_MODE: u16 = 1 << 8;
}
