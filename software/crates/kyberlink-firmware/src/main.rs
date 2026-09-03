#![cfg_attr(not(test), no_std)]
#![cfg_attr(not(test), no_main)]

#[cfg(not(test))]
mod firmware {
    use core::arch::asm;
    use kyberlink_firmware::handshake_fsm::{write_sa, Config, Fsm, FsmOutcome};
    use kyberlink_firmware::spi::SpiMaster;

    static mut PEER_FP: [u8; 32] = [0; 32];
    static mut CFG_VALID: bool = false;

    const SEED_KEM_D: [u8; 32] = [0x11; 32];
    const SEED_KEM_Z: [u8; 32] = [0x12; 32];
    const SEED_DSA: [u8; 32] = [0x22; 32];
    const NONCE: [u8; 32] = [0x55; 32];

    extern "C" {
        static _stack_top: u8;
    }

    #[no_mangle]
    #[link_section = ".text._start"]
    pub unsafe extern "C" fn _start() -> ! {
        unsafe {
            asm!("la sp, _stack_top", options(nostack));
        }
        main()
    }

    fn main() -> ! {
        let spi = SpiMaster::new();
        let cfg = Config {
            role_initiator: true,
            peer_fp: unsafe { PEER_FP },
            seed_kem_d: SEED_KEM_D,
            seed_kem_z: SEED_KEM_Z,
            seed_dsa: SEED_DSA,
            nonce: NONCE,
        };
        let mut fsm = Fsm::new(&cfg, &spi);
        loop {
            if unsafe { CFG_VALID } {
                match fsm.poll() {
                    FsmOutcome::Sa(sa) => {
                        write_sa(&spi, &sa, cfg.role_initiator);
                    }
                    FsmOutcome::Wait => {}
                }
            }
            unsafe {
                for _ in 0..1000 {
                    asm!("nop");
                }
            }
        }
    }
}

#[cfg(not(test))]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}
