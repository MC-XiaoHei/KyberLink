pub fn system_reset() -> ! {
    ch32_hal::pac::PFIC.sctlr().modify(|w| w.set_sysreset(true));
    loop {
        core::hint::spin_loop();
    }
}
