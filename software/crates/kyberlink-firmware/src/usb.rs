use ch32_hal::peripherals::{PA11, PA12, USBD};
use ch32_hal::usbd::{Driver, InterruptHandler};
use ch32_hal::Peri;
use embassy_futures::join::join;
use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::signal::Signal;
use embassy_usb::class::cdc_acm::{CdcAcmClass, State};
use embassy_usb::driver::EndpointError;
use embassy_usb::{Builder, Config};
use kyberlink_core::cfg_store::NorFlash;
use kyberlink_core::console::Console;
use kyberlink_core::dispatch::Action;

pub type ActionSignal = Signal<CriticalSectionRawMutex, Action>;

ch32_hal::bind_interrupts!(pub struct Irqs {
    USB_LP_CAN1_RX0 => InterruptHandler<USBD>;
});

const VID: u16 = 0xc0de;
const PID: u16 = 0xcafe;
const PACKET: u8 = 64;

pub async fn serve<F: NorFlash>(
    usbd: Peri<'static, USBD>,
    dp: Peri<'static, PA12>,
    dm: Peri<'static, PA11>,
    console: &mut Console,
    flash: &mut F,
    signal: &ActionSignal,
) -> ! {
    let driver = Driver::new(usbd, Irqs, dp, dm);

    let mut config = Config::new(VID, PID);
    config.manufacturer = Some("KyberLink");
    config.product = Some("KyberLink Console");
    config.max_power = 100;
    config.max_packet_size_0 = PACKET;
    config.device_class = 0x02;
    config.device_sub_class = 0x02;
    config.device_protocol = 0x00;
    config.composite_with_iads = false;

    let mut config_descriptor = [0u8; 256];
    let mut bos_descriptor = [0u8; 256];
    let mut control_buf = [0u8; 64];
    let mut state = State::new();

    let mut builder = Builder::new(
        driver,
        config,
        &mut config_descriptor,
        &mut bos_descriptor,
        &mut [],
        &mut control_buf,
    );
    let mut class = CdcAcmClass::new(&mut builder, &mut state, PACKET.into());
    let mut usb = builder.build();

    join(usb.run(), pump(&mut class, console, flash, signal)).await;
    unreachable!()
}

async fn pump<'d, F: NorFlash>(
    class: &mut CdcAcmClass<'d, Driver<'d, USBD>>,
    console: &mut Console,
    flash: &mut F,
    signal: &ActionSignal,
) -> ! {
    loop {
        class.wait_connection().await;
        while session(class, console, flash, signal).await.is_ok() {}
    }
}

async fn session<'d, F: NorFlash>(
    class: &mut CdcAcmClass<'d, Driver<'d, USBD>>,
    console: &mut Console,
    flash: &mut F,
    signal: &ActionSignal,
) -> Result<(), EndpointError> {
    let mut buf = [0u8; PACKET as usize];
    loop {
        let n = class.read_packet(&mut buf).await?;
        console.set_err(crate::firmware::err_flags());
        for &byte in &buf[..n] {
            let action = console.push(byte, flash);
            if let Some(reply) = console.take_reply() {
                class.write_packet(reply.as_bytes()).await?;
            }
            match action {
                Action::Rekey | Action::Reboot => signal.signal(action),
                _ => {}
            }
        }
    }
}
