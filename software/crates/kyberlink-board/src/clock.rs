const RCC_CTLR: u32 = 0x4002_1000;
const RCC_APB1PCENR: u32 = 0x4002_101C;
const RCC_BDCTLR: u32 = 0x4002_1020;
const PWR_CTLR: u32 = 0x4000_7000;
const RTC_CTLRL: u32 = 0x4000_2804;
const RTC_PSCH: u32 = 0x4000_2808;
const RTC_PSCL: u32 = 0x4000_280C;

const LSI_ON: u32 = 1 << 0;
const LSI_READY: u32 = 1 << 1;
const PWR_BKP_EN: u32 = 1 << 28;
const BKP_CLK_EN: u32 = 1 << 27;
const BKP_WRITE_EN: u32 = 1 << 8;
const BDCR_BDEN: u32 = 1 << 15;
const BDCR_RTCSEL_MASK: u32 = 3 << 8;
const BDCR_RTCSEL_LSI: u32 = 2 << 8;
const CTL_RSF: u32 = 1 << 3;
const CTL_CNF: u32 = 1 << 4;
const CTL_RTOFF: u32 = 1 << 5;

const RTC_LSI_DIV: u32 = 39;
const LSI_SPINS: u32 = 200_000;
const BDCR_SPINS: u32 = 100_000;
const PRESCALER_SPINS: u32 = 100_000;
const BDCR_SETTLE_CYCLES: u32 = 200_000;
const SYSCLK_MHZ: u32 = 120;

fn rw(addr: u32) -> *mut u32 {
    addr as *mut u32
}

fn set_bits(addr: u32, bits: u32) {
    // SAFETY: the addresses above are peripheral registers in fixed windows.
    unsafe { rw(addr).write_volatile(rw(addr).read_volatile() | bits) }
}

fn clear_bits(addr: u32, bits: u32) {
    // SAFETY: the addresses above are peripheral registers in fixed windows.
    unsafe { rw(addr).write_volatile(rw(addr).read_volatile() & !bits) }
}

fn wait_flag(addr: u32, mask: u32, spins: u32) -> bool {
    for _ in 0..spins {
        // SAFETY: the addresses above are peripheral registers in fixed windows.
        if unsafe { rw(addr).read_volatile() } & mask != 0 {
            return true;
        }
    }
    false
}

pub fn config() -> ch32_hal::Config {
    let mut rcc = ch32_hal::rcc::Config::SYSCLK_FREQ_144MHZ_HSI;
    rcc.pll = Some(ch32_hal::rcc::Pll {
        prediv: ch32_hal::rcc::PllPreDiv::DIV1,
        mul: ch32_hal::rcc::PllMul::MUL15,
    });
    ch32_hal::Config {
        rcc,
        ..Default::default()
    }
}

pub fn source() -> &'static str {
    "hsi"
}

pub fn mhz() -> u32 {
    SYSCLK_MHZ
}

pub fn start_lsi() -> bool {
    set_bits(RCC_CTLR, LSI_ON);
    wait_flag(RCC_CTLR, LSI_READY, LSI_SPINS)
}

pub fn start_rtc() -> bool {
    if !start_lsi() {
        return false;
    }
    set_bits(RCC_APB1PCENR, PWR_BKP_EN | BKP_CLK_EN);
    set_bits(PWR_CTLR, BKP_WRITE_EN);

    let base = select_rtc_source();
    // SAFETY: the addresses above are peripheral registers in fixed windows.
    unsafe {
        rw(RCC_BDCTLR).write_volatile(base);
        riscv::asm::delay(BDCR_SETTLE_CYCLES);
        rw(RCC_BDCTLR).write_volatile(base | BDCR_BDEN);
        riscv::asm::delay(BDCR_SETTLE_CYCLES);
    }

    if !wait_flag(RTC_CTLRL, CTL_RSF, BDCR_SPINS) {
        return false;
    }
    set_bits(RTC_CTLRL, CTL_CNF);
    // SAFETY: the addresses above are peripheral registers in fixed windows.
    unsafe {
        rw(RTC_PSCH).write_volatile(0);
        rw(RTC_PSCL).write_volatile(RTC_LSI_DIV);
    }
    clear_bits(RTC_CTLRL, CTL_CNF);
    wait_flag(RTC_CTLRL, CTL_RTOFF, PRESCALER_SPINS)
}

fn select_rtc_source() -> u32 {
    // SAFETY: the addresses above are peripheral registers in fixed windows.
    let current = unsafe { rw(RCC_BDCTLR).read_volatile() };
    (current & !BDCR_RTCSEL_MASK & !BDCR_BDEN) | BDCR_RTCSEL_LSI
}

pub fn resync_uart_baud() {
    const CFGR0: u32 = 0x4002_1004;
    const PLLSRC_HSE: u32 = 1 << 16;
    const USART1_BRR: u32 = 0x4001_3808;
    const BAUDRATE: u32 = 115_200;
    // SAFETY: the addresses above are peripheral registers in fixed windows.
    let pll_on_hse = unsafe { rw(CFGR0).read_volatile() } & PLLSRC_HSE != 0;
    if !pll_on_hse {
        let divisor = SYSCLK_MHZ * 1_000_000 / BAUDRATE;
        // SAFETY: as above.
        unsafe { rw(USART1_BRR).write_volatile(divisor) };
    }
}
