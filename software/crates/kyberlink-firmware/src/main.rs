#![cfg_attr(target_arch = "riscv32", no_std)]
#![cfg_attr(target_arch = "riscv32", no_main)]
#![allow(static_mut_refs)]

#[cfg(target_arch = "riscv32")]
mod firmware {
    use ch32_hal::gpio::{Level, Output};
    use ch32_hal::spi::{Config as SpiConfig, Spi};
    use ch32_hal::time::Hertz;
    use embassy_executor::Spawner;
    use embassy_time::Timer;
    use kyberlink_core::handshake_fsm::{write_sa, Config, Fsm, FsmOutcome};
    use kyberlink_firmware::spi::SpiMaster;

    include!(concat!(env!("OUT_DIR"), "/spc_rom.rs"));
    include!(concat!(env!("OUT_DIR"), "/fp_rom.rs"));

    const _: () = assert!(SPC_SIZE == core::mem::size_of::<kyberlink_crypto::mldsa_internal::SignPrecomp>());

    static mut PEER_FP: [u8; 32] = [0; 32];
    static mut CFG_VALID: bool = false;
    static mut SPI: Option<SpiMaster> = None;
    static mut CONFIG: Option<Config> = None;
    static mut FSM: core::mem::MaybeUninit<Fsm<SpiMaster>> = core::mem::MaybeUninit::uninit();

    const SEED_KEM_D: [u8; 32] = [0x11; 32];
    const SEED_KEM_Z: [u8; 32] = [0x12; 32];
    const NONCE: [u8; 32] = [0x55; 32];

    const SA_SEQ_INIT: u32 = 1;

    #[embassy_executor::main(entry = "ch32_hal::entry")]
    async fn main(_spawner: Spawner) -> ! {
        let config = ch32_hal::Config {
            rcc: ch32_hal::rcc::Config::SYSCLK_FREQ_144MHZ_HSI,
            ..Default::default()
        };
        let p = ch32_hal::init(config);

        let mut spi_config = SpiConfig::default();
        spi_config.frequency = Hertz::khz(2250);
        let spi = Spi::new_blocking::<0>(p.SPI1, p.PA5, p.PA7, p.PA6, spi_config);
        let cs = Output::new(p.PA4, Level::High, Default::default());

        let own_fp: [u8; 32] = kyberlink_crypto::shake::sha3_256(&VK_ROM);
        if own_fp == FP_ROM {
            loop {
                core::hint::spin_loop();
            }
        }

        static SPC: kyberlink_crypto::mldsa_internal::SignPrecomp = unsafe {
            core::ptr::read(SPC_ROM.as_ptr() as *const kyberlink_crypto::mldsa_internal::SignPrecomp)
        };
        static IDENTITY: kyberlink_crypto::handshake::RomIdentity = kyberlink_crypto::handshake::RomIdentity {
            vk: &VK_ROM,
            sk: &SK_ROM,
            spc: &SPC,
        };
        let identity: &'static dyn kyberlink_crypto::handshake::Identity = &IDENTITY;

        unsafe {
            SPI = Some(SpiMaster::new(spi, cs));
            CONFIG = Some(Config {
                role_initiator: true,
                peer_fp: PEER_FP,
                seed_kem_d: SEED_KEM_D,
                seed_kem_z: SEED_KEM_Z,
                nonce: NONCE,
                identity,
            });
            if let (Some(spi), Some(cfg)) = (SPI.as_ref(), CONFIG.as_ref()) {
                FSM.write(Fsm::new(cfg, spi));
            }
        }

        loop {
            let valid = unsafe { core::ptr::read_volatile(core::ptr::addr_of!(CFG_VALID)) };
            let outcome = unsafe {
                if valid {
                    FSM.assume_init_mut().poll()
                } else {
                    FsmOutcome::Wait
                }
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

#[cfg(target_arch = "riscv32")]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}

#[cfg(not(target_arch = "riscv32"))]
fn main() {}
