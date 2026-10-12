use ch32_hal::gpio::{Level, Output, OutputOpenDrain, Speed};
use ch32_hal::spi::{Config as SpiConfig, Spi};
use ch32_hal::time::Hertz;
use embassy_executor::Spawner;
use embassy_time::{Duration, Timer};
use kyberlink_board::bringup;
use kyberlink_board::mdio::{BitBangMdio, MdcPin, PhysPair};
use kyberlink_board::pinmap::{Board, Pins};
use kyberlink_board::spi::SpiMaster;
use kyberlink_board::uart;
use kyberlink_core::handshake_fsm::SpiBus;
use kyberlink_mdio::dp83867::is_expected_id;

const REG_CTRL: u8 = 0x00;
const REG_STATUS: u8 = 0x04;
const LAN_BASE: u8 = 0x08;
const WAN_BASE: u8 = 0x20;

const CTRL_ENABLE: u32 = 0x1;
const CTRL_LOOPBACK: u32 = 0x2;
const CTRL_CLEAR: u32 = 0x4;

const STATUS_LOCKED: u32 = 0x4;
const STATUS_FAULT: u32 = 0x18;

const PHASE_SECS: u64 = 3;
const LINK_TIMEOUT_MS: u64 = 5000;
const LINK_POLL_MS: u64 = 100;
const STRESS_ROUNDS: u32 = 60;
const STRESS_SECS: u64 = 10;

macro_rules! say {
    ($log:expr, $($arg:tt)*) => {
        $log.line(format_args!($($arg)*))
    };
}

struct Log {
    uart: uart::BlockingUart,
}

impl Log {
    fn new(uart: uart::BlockingUart) -> Self {
        Self { uart }
    }

    fn line(&mut self, args: core::fmt::Arguments<'_>) {
        let _ = core::fmt::Write::write_fmt(&mut *self, args);
        let _ = self.uart.blocking_write(b"\r\n");
    }
}

impl core::fmt::Write for Log {
    fn write_str(&mut self, s: &str) -> core::fmt::Result {
        self.uart
            .blocking_write(s.as_bytes())
            .map_err(|_| core::fmt::Error)
    }
}

#[derive(Clone, Copy, Default)]
struct Counts {
    tx: u32,
    good: u32,
    bad: u32,
    diff: u32,
}

fn read_counts(spi: &SpiMaster, base: u8) -> Counts {
    Counts {
        tx: spi.read_reg(base),
        good: spi.read_reg(base + 4),
        bad: spi.read_reg(base + 8),
        diff: spi.read_reg(base + 12),
    }
}

struct Phase {
    lan: Counts,
    wan: Counts,
    status: u32,
}

impl Phase {
    fn clean(&self) -> bool {
        self.lan.bad == 0
            && self.wan.bad == 0
            && self.lan.diff == 0
            && self.wan.diff == 0
            && self.status & STATUS_FAULT == 0
    }

    fn flowing(&self) -> bool {
        self.lan.tx > 0 && self.lan.good > 0 && self.wan.tx > 0 && self.wan.good > 0
    }
}

async fn wait_link(phys: &PhysPair<'_>) -> (bool, bool) {
    let mut waited = 0u64;
    loop {
        let state = phys.link_status().unwrap_or((false, false));
        if state.0 && state.1 {
            return state;
        }
        if waited >= LINK_TIMEOUT_MS {
            return state;
        }
        Timer::after_millis(LINK_POLL_MS).await;
        waited += LINK_POLL_MS;
    }
}

async fn run_phase(spi: &SpiMaster, ctrl: u32, secs: u64) -> Phase {
    spi.write_reg(REG_CTRL, CTRL_CLEAR);
    spi.write_reg(REG_CTRL, ctrl);
    Timer::after(Duration::from_secs(secs)).await;
    Phase {
        lan: read_counts(spi, LAN_BASE),
        wan: read_counts(spi, WAN_BASE),
        status: spi.read_reg(REG_STATUS),
    }
}

#[embassy_executor::main(entry = "ch32_hal::entry")]
pub async fn main(_spawner: Spawner) -> ! {
    let p = ch32_hal::init(kyberlink_board::pinmap::clock_config());

    let pins = Pins {
        spi_sck: p.PA5,
        spi_mosi: p.PA7,
        spi_miso: p.PA6,
        spi_cs: p.PA4,
        fpga_rst: p.PA1,
        fpga_recfg: p.PA2,
        fpga_done: p.PA3,
        uart_tx: p.PB6,
        uart_rx: p.PB7,
        phy_rst: p.PA11,
        phy_mdc: p.PC6,
        wan_mdio: p.PC8,
        lan_mdio: p.PC9,
    };

    let mut log = Log::new(uart::open_blocking(p.USART1, pins.uart_rx, pins.uart_tx));

    let mut spi_config = SpiConfig::default();
    spi_config.frequency = Hertz::khz(2250);
    let spi = SpiMaster::new(
        Spi::new_blocking::<0>(
            p.SPI1,
            pins.spi_sck,
            pins.spi_mosi,
            pins.spi_miso,
            spi_config,
        ),
        Output::new(pins.spi_cs, Level::High, Default::default()),
    );

    let mut board = Board::new(pins.fpga_rst, pins.fpga_recfg, pins.phy_rst, pins.fpga_done);
    let mdc = MdcPin::new(Output::new(pins.phy_mdc, Level::Low, Default::default()));
    let lan_bus = BitBangMdio::new(
        &mdc,
        OutputOpenDrain::new(pins.lan_mdio, Level::High, Speed::Low),
    );
    let wan_bus = BitBangMdio::new(
        &mdc,
        OutputOpenDrain::new(pins.wan_mdio, Level::High, Speed::Low),
    );

    say!(log, "kyberlink selftest");
    say!(log, "spi 2250khz mdc 1mhz");

    let mut phy_ok = false;
    let mut fpga_ok = false;
    match bringup::bring_up(&mut board, lan_bus, wan_bus, || {
        spi.read_reg(REG_STATUS) & STATUS_LOCKED != 0
    })
    .await
    {
        Ok(out) => {
            let lan_id = out.phys.lan.identify().unwrap_or(0);
            let wan_id = out.phys.wan.identify().unwrap_or(0);
            phy_ok = is_expected_id(lan_id) && is_expected_id(wan_id);
            fpga_ok = out.ready;
            say!(
                log,
                "fpga configured {:?}ms reconfigs {} ready {} {}ms",
                out.configured_ms,
                out.reconfigs,
                out.ready,
                out.ready_ms
            );
            say!(log, "lan phyid {:08x}", lan_id);
            say!(log, "wan phyid {:08x}", wan_id);
            let (lan_link, wan_link) = wait_link(&out.phys).await;
            say!(log, "link lan {} wan {}", lan_link, wan_link);
        }
        Err(_) => say!(log, "bringup failed"),
    }

    let loopback = run_phase(&spi, CTRL_ENABLE | CTRL_LOOPBACK, PHASE_SECS).await;
    say!(
        log,
        "loopback lan tx {} good {} bad {} diff {}",
        loopback.lan.tx,
        loopback.lan.good,
        loopback.lan.bad,
        loopback.lan.diff
    );
    let loopback_ok = loopback.flowing() && loopback.clean();

    let cable = run_phase(&spi, CTRL_ENABLE, PHASE_SECS).await;
    say!(
        log,
        "cable wan tx {} good {} bad {} diff {}",
        cable.wan.tx,
        cable.wan.good,
        cable.wan.bad,
        cable.wan.diff
    );
    say!(
        log,
        "cable lan tx {} good {} bad {} diff {}",
        cable.lan.tx,
        cable.lan.good,
        cable.lan.bad,
        cable.lan.diff
    );
    let cable_ok = cable.flowing() && cable.clean();

    spi.write_reg(REG_CTRL, CTRL_CLEAR);
    spi.write_reg(REG_CTRL, CTRL_ENABLE);
    let mut lan_prev = read_counts(&spi, LAN_BASE);
    let mut wan_prev = read_counts(&spi, WAN_BASE);
    let mut frames = 0u64;
    let mut bad = 0u64;
    let mut diff = 0u64;
    for round in 1..=STRESS_ROUNDS {
        Timer::after(Duration::from_secs(STRESS_SECS)).await;
        let lan = read_counts(&spi, LAN_BASE);
        let wan = read_counts(&spi, WAN_BASE);
        let tx = u64::from(lan.tx.wrapping_sub(lan_prev.tx));
        let good = u64::from(wan.good.wrapping_sub(wan_prev.good));
        let round_bad = u64::from(lan.bad.wrapping_sub(lan_prev.bad))
            + u64::from(wan.bad.wrapping_sub(wan_prev.bad));
        let round_diff = u64::from(lan.diff.wrapping_sub(lan_prev.diff))
            + u64::from(wan.diff.wrapping_sub(wan_prev.diff));
        frames += tx;
        bad += round_bad;
        diff += round_diff;
        say!(
            log,
            "stress {}/{} tx {} good {} bad {} diff {}",
            round,
            STRESS_ROUNDS,
            tx,
            good,
            round_bad,
            round_diff
        );
        lan_prev = lan;
        wan_prev = wan;
    }

    let pass = phy_ok && fpga_ok && loopback_ok && cable_ok && bad == 0 && diff == 0;
    say!(log, "stress frames {} bad {} diff {}", frames, bad, diff);
    say!(log, "result {}", if pass { "PASS" } else { "FAIL" });

    loop {
        Timer::after_secs(5).await;
    }
}
