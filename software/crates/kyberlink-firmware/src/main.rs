#![cfg_attr(not(test), no_std)]
#![cfg_attr(not(test), no_main)]
#![allow(static_mut_refs)]

#[cfg(not(test))]
mod firmware {
    use ch32_hal::gpio::{Level, Output};
    use ch32_hal::spi::{Config as SpiConfig, Spi};
    use ch32_hal::time::Hertz;
    use embassy_executor::Spawner;
    use embassy_time::Timer;
    use kyberlink_firmware::handshake_fsm::{write_sa, Config, Fsm, FsmOutcome};
    use kyberlink_firmware::spi::SpiMaster;

    static mut PEER_FP: [u8; 32] = [0; 32];
    static mut CFG_VALID: bool = false;
    static mut SPI: Option<SpiMaster> = None;
    static mut CONFIG: Option<Config> = None;
    static mut FSM: Option<Fsm<SpiMaster>> = None;

    const SEED_KEM_D: [u8; 32] = [0x11; 32];
    const SEED_KEM_Z: [u8; 32] = [0x12; 32];
    const SEED_DSA: [u8; 32] = [0x22; 32];
    const NONCE: [u8; 32] = [0x55; 32];

    const SA_SEQ_INIT: u32 = 1;

    #[embassy_executor::main(entry = "ch32_hal::entry")]
    async fn main(_spawner: Spawner) -> ! {
        let mut config = ch32_hal::Config::default();
        config.rcc = ch32_hal::rcc::Config::SYSCLK_FREQ_144MHZ_HSI;
        let p = ch32_hal::init(config);

        let mut spi_config = SpiConfig::default();
        spi_config.frequency = Hertz::khz(2250);
        let spi = Spi::new_blocking::<0>(p.SPI1, p.PA5, p.PA7, p.PA6, spi_config);
        let cs = Output::new(p.PA4, Level::High, Default::default());

        unsafe {
            SPI = Some(SpiMaster::new(spi, cs));
            CONFIG = Some(Config {
                role_initiator: true,
                peer_fp: PEER_FP,
                seed_kem_d: SEED_KEM_D,
                seed_kem_z: SEED_KEM_Z,
                seed_dsa: SEED_DSA,
                nonce: NONCE,
            });
            if let (Some(spi), Some(cfg)) = (SPI.as_ref(), CONFIG.as_ref()) {
                FSM = Some(Fsm::new(cfg, spi));
            }
        }

        loop {
            let valid = unsafe { core::ptr::read_volatile(core::ptr::addr_of!(CFG_VALID)) };
            let outcome = unsafe {
                FSM.as_mut()
                    .and_then(|f| {
                        if valid {
                            Some(f.poll())
                        } else {
                            None
                        }
                    })
                    .unwrap_or(FsmOutcome::Wait)
            };
            if let FsmOutcome::Sa(sa) = outcome {
                if let Some(spi) = unsafe { SPI.as_ref() } {
                    write_sa(spi, &sa, true, SA_SEQ_INIT);
                }
            }
            Timer::after_millis(1).await;
        }
    }
}

#[cfg(not(test))]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}
