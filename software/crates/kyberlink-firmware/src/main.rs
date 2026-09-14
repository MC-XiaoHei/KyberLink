#![cfg_attr(target_arch = "riscv32", no_std)]
#![cfg_attr(target_arch = "riscv32", no_main)]
#![allow(static_mut_refs)]

#[cfg(target_arch = "riscv32")]
mod firmware {
    use ch32_hal::adc::{Adc, AdcChannel, AnyAdcChannel, Pga, SampleTime};
    use ch32_hal::flash::{Blocking, Flash};
    use ch32_hal::gpio::{Level, Output};
    use ch32_hal::peripherals::ADC1;
    use ch32_hal::spi::{Config as SpiConfig, Spi};
    use ch32_hal::time::Hertz;
    use embassy_executor::Spawner;
    use embassy_time::Timer;
    use kyberlink_core::cfg_msg::{Binding, Identity as CfgIdentity, BINDING_LEN, IDENTITY_LEN};
    use kyberlink_core::cfg_store::{
        self, CfgError, NorFlash, BINDING_BASE, MAGIC_BINDING, MAGIC_IDENTITY, IDENTITY_BASE,
    };
    use kyberlink_core::handshake_fsm::{write_data_plane, write_sa, Config, Fsm, FsmOutcome};
    use kyberlink_crypto::handshake::{RomIdentity, KK_LEN, TR_LEN};
    use kyberlink_crypto::mldsa_internal::{SignPrecomp, VK_LEN};
    use kyberlink_crypto::shake;
    use kyberlink_firmware::spi::SpiMaster;

    const FLASH_BASE: u32 = 0x0800_0000;
    const SA_SEQ_INIT: u32 = 1;

    struct FlashPort<'d>(Flash<'d, Blocking>);

    impl NorFlash for FlashPort<'_> {
        fn read(&mut self, off: u32, buf: &mut [u8]) -> Result<(), CfgError> {
            self.0.blocking_read(off, buf).map_err(|_| CfgError::Flash)
        }

        fn write_page(&mut self, off: u32, page: &[u8]) -> Result<(), CfgError> {
            self.0
                .blocking_write(off, page)
                .map_err(|_| CfgError::Flash)
        }

        fn erase(&mut self, off: u32, len: u32) -> Result<(), CfgError> {
            self.0
                .blocking_erase(off, off + len)
                .map_err(|_| CfgError::Flash)
        }
    }

    static mut SPI: Option<SpiMaster> = None;
    static mut CONFIG: core::mem::MaybeUninit<Config> = core::mem::MaybeUninit::uninit();
    static mut FSM: core::mem::MaybeUninit<Fsm<SpiMaster>> = core::mem::MaybeUninit::uninit();
    static mut IDENTITY: core::mem::MaybeUninit<RomIdentity> = core::mem::MaybeUninit::uninit();

    unsafe fn payload_slice(base: u32, len: usize) -> &'static [u8] {
        core::slice::from_raw_parts(
            (FLASH_BASE + base + cfg_store::HEADER_LEN as u32) as *const u8,
            len,
        )
    }

    fn read_binding(flash: &mut FlashPort) -> Result<Binding, CfgError> {
        cfg_store::verify(flash, BINDING_BASE, &MAGIC_BINDING, BINDING_LEN as u16)?;
        let mut buf = [0u8; BINDING_LEN];
        cfg_store::read_payload(flash, BINDING_BASE, 0, &mut buf)?;
        Binding::decode(&buf)
    }

    fn read_identity(flash: &mut FlashPort) -> Result<&'static RomIdentity, CfgError> {
        cfg_store::verify(flash, IDENTITY_BASE, &MAGIC_IDENTITY, IDENTITY_LEN as u16)?;
        let payload = unsafe { payload_slice(IDENTITY_BASE, IDENTITY_LEN) };
        let parts = CfgIdentity::decode(payload)?;
        let vk: &'static [u8; VK_LEN] = parts.vk.try_into().map_err(|_| CfgError::Length)?;
        let kk: &'static [u8; KK_LEN] = parts.kk.try_into().map_err(|_| CfgError::Length)?;
        let tr: &'static [u8; TR_LEN] = parts.tr.try_into().map_err(|_| CfgError::Length)?;
        let spc: &'static SignPrecomp = unsafe { &*(parts.spc.as_ptr() as *const SignPrecomp) };
        let store = unsafe { &mut *core::ptr::addr_of_mut!(IDENTITY) };
        store.write(RomIdentity { vk, kk, tr, spc });
        Ok(unsafe { store.assume_init_ref() })
    }

    fn sample_entropy(adc: &mut Adc<'_, ADC1>, chans: &mut [AnyAdcChannel<ADC1>]) -> [u8; 32] {
        let mut raw = [0u8; 256];
        let mut i = 0;
        for _ in 0..64 {
            for ch in chans.iter_mut() {
                let v = adc.convert(ch, SampleTime::CYCLES239_5, Pga::X1);
                let c: u32;
                unsafe { core::arch::asm!("csrr {}, mcycle", out(reg) c) };
                raw[i] = (v as u8) ^ (c as u8);
                i += 1;
            }
        }
        shake::sha3_256(&raw)
    }

    async fn provisioning_hold() -> ! {
        loop {
            Timer::after_millis(1000).await;
        }
    }

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

        let mut flash = FlashPort(Flash::new_blocking(p.FLASH));

        let Ok(binding) = read_binding(&mut flash) else {
            provisioning_hold().await
        };
        let Ok(identity) = read_identity(&mut flash) else {
            provisioning_hold().await
        };

        let mut adc = Adc::new(p.ADC1, Default::default());
        let mut chans = [
            p.PA0.degrade_adc(),
            p.PA1.degrade_adc(),
            p.PA2.degrade_adc(),
            p.PA3.degrade_adc(),
        ];
        let entropy = sample_entropy(&mut adc, &mut chans);
        let seed_kem_d = shake::sha3_256_parts(&[&entropy, b"kyb-kem-d"]);
        let seed_kem_z = shake::sha3_256_parts(&[&entropy, b"kyb-kem-z"]);
        let nonce = shake::sha3_256_parts(&[&entropy, b"kyb-nonce"]);

        unsafe {
            SPI = Some(SpiMaster::new(spi, cs));
            let spi_ref = SPI.as_ref().unwrap();
            write_data_plane(spi_ref, &binding);
            CONFIG.write(Config {
                role_initiator: binding.role_initiator,
                peer_fp: binding.peer_fp,
                seed_kem_d,
                seed_kem_z,
                nonce,
                identity,
            });
            FSM.write(Fsm::new(CONFIG.assume_init_ref(), spi_ref));
        }

        loop {
            let outcome = unsafe { FSM.assume_init_mut().poll() };
            if let FsmOutcome::Sa(sa) = outcome {
                if let Some(spi) = unsafe { SPI.as_ref() } {
                    write_sa(spi, &sa, binding.role_initiator, SA_SEQ_INIT);
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
