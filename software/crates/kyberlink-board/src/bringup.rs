use embassy_time::Timer;
use kyberlink_mdio::bus::MdioError;
use kyberlink_mdio::dp83867::PhyPair;

use crate::mdio::{self, BitBangMdio};
use crate::pinmap::Board;

const FPGA_CONFIG_TIMEOUT_MS: u64 = 5000;
const FPGA_POLL_MS: u64 = 1;
const FPGA_READY_TIMEOUT_MS: u64 = 500;
const FPGA_READY_STREAK: u32 = 2;
const RECONFIG_ATTEMPTS: u32 = 3;
const RECONFIG_HOLD_MS: u64 = 1;

pub struct Outcome<'d> {
    pub phys: PhyPair<BitBangMdio<'d>, BitBangMdio<'d>>,
    pub configured_ms: Option<u64>,
    pub reconfigs: u32,
    pub ready: bool,
    pub ready_ms: u64,
}

pub async fn bring_up<'d, F: Fn() -> bool>(
    board: &mut Board<'d>,
    lan: BitBangMdio<'d>,
    wan: BitBangMdio<'d>,
    probe: F,
) -> Result<Outcome<'d>, MdioError> {
    board.fpga_reset.enable();
    Timer::after_millis(2).await;
    board.fpga_reset.disable();
    let phys = mdio::init_pair(lan, wan, &mut board.phy_reset).await;

    let mut configured_ms = wait_configured(board).await;
    let mut reconfigs = 0;
    while configured_ms.is_none() && reconfigs < RECONFIG_ATTEMPTS {
        board.fpga_reconfig.enable();
        Timer::after_millis(RECONFIG_HOLD_MS).await;
        board.fpga_reconfig.disable();
        reconfigs += 1;
        configured_ms = wait_configured(board).await;
    }

    let (ready, ready_ms) = wait_ready(&probe).await;
    Ok(Outcome {
        phys: phys?,
        configured_ms,
        reconfigs,
        ready,
        ready_ms,
    })
}

async fn wait_configured(board: &Board<'_>) -> Option<u64> {
    let mut waited = 0u64;
    loop {
        if board.fpga_done.value() {
            return Some(waited);
        }
        if waited >= FPGA_CONFIG_TIMEOUT_MS {
            return None;
        }
        Timer::after_millis(FPGA_POLL_MS).await;
        waited += FPGA_POLL_MS;
    }
}

async fn wait_ready<F: Fn() -> bool>(probe: &F) -> (bool, u64) {
    let mut waited = 0u64;
    let mut streak = 0u32;
    loop {
        if probe() {
            streak += 1;
            if streak >= FPGA_READY_STREAK {
                return (true, waited);
            }
        } else {
            streak = 0;
        }
        if waited >= FPGA_READY_TIMEOUT_MS {
            return (false, waited);
        }
        Timer::after_millis(FPGA_POLL_MS).await;
        waited += FPGA_POLL_MS;
    }
}
