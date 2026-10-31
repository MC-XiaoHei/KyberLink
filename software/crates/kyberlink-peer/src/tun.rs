#![cfg(target_os = "linux")]

use std::fs::{File, OpenOptions};
use std::io;
use std::os::fd::{AsRawFd, RawFd};

use libc::{c_char, c_int, c_ulong, ifreq};

const TUNSETIFF: c_ulong = 0x4004_54ca;
const SIOCSIFMTU: c_ulong = 0x8922;
const SIOCGIFFLAGS: c_ulong = 0x8913;
const SIOCSIFFLAGS: c_ulong = 0x8914;
const IFF_UP: i16 = 0x0001;
const IFF_MULTI_QUEUE: i16 = 0x0100;
const IFF_TUN: i16 = 0x0001;
const IFF_NO_PI: i16 = 0x1000;
const IFNAMSIZ: usize = 16;

pub struct TunDevice {
    file: File,
}

impl TunDevice {
    pub fn open(name: &str, mtu: usize) -> io::Result<Self> {
        Self::attach(name, mtu, false, true)
    }

    pub fn open_multi(name: &str, mtu: usize, queues: usize) -> io::Result<Vec<Self>> {
        let mut devices = Vec::with_capacity(queues);
        for queue in 0..queues.max(1) {
            devices.push(Self::attach(name, mtu, queue > 0, queue == 0)?);
        }
        Ok(devices)
    }

    fn attach(name: &str, mtu: usize, reuse: bool, configure: bool) -> io::Result<Self> {
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .open("/dev/net/tun")?;
        let mut req = zeroed_ifreq(name)?;
        req.ifr_ifru.ifru_flags = IFF_TUN | IFF_NO_PI | IFF_MULTI_QUEUE;
        ctl(file.as_raw_fd(), TUNSETIFF, &mut req)?;
        if reuse {
            set_nonblocking(file.as_raw_fd())?;
            return Ok(Self { file });
        }
        if !configure {
            return Ok(Self { file });
        }

        let ctl_sock = unsafe { libc::socket(libc::AF_INET, libc::SOCK_DGRAM, 0) };
        if ctl_sock < 0 {
            return Err(io::Error::last_os_error());
        }
        let result = {
            let mut mtu_req = zeroed_ifreq(name)?;
            mtu_req.ifr_ifru.ifru_mtu = mtu as c_int;
            let mut code = ctl(ctl_sock, SIOCSIFMTU, &mut mtu_req);
            if code.is_ok() {
                let mut flags_req = zeroed_ifreq(name)?;
                code = ctl(ctl_sock, SIOCGIFFLAGS, &mut flags_req).and_then(|()| {
                    unsafe { flags_req.ifr_ifru.ifru_flags |= IFF_UP };
                    ctl(ctl_sock, SIOCSIFFLAGS, &mut flags_req)
                });
            }
            unsafe { libc::close(ctl_sock) };
            code
        };
        result?;

        set_nonblocking(file.as_raw_fd())?;
        Ok(Self { file })
    }

    pub fn try_clone(&self) -> io::Result<Self> {
        Ok(Self {
            file: self.file.try_clone()?,
        })
    }

    pub fn read(&self, buf: &mut [u8]) -> io::Result<usize> {
        let fd = self.file.as_raw_fd();
        let n = unsafe { libc::read(fd, buf.as_mut_ptr().cast(), buf.len()) };
        if n < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(n as usize)
    }

    pub fn write(&self, buf: &[u8]) -> io::Result<usize> {
        let fd = self.file.as_raw_fd();
        let n = unsafe { libc::write(fd, buf.as_ptr().cast(), buf.len()) };
        if n < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(n as usize)
    }
}

impl AsRawFd for TunDevice {
    fn as_raw_fd(&self) -> RawFd {
        self.file.as_raw_fd()
    }
}

fn zeroed_ifreq(name: &str) -> io::Result<ifreq> {
    if name.len() >= IFNAMSIZ {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "tun name too long",
        ));
    }
    let mut req: ifreq = unsafe { std::mem::zeroed() };
    for (slot, byte) in req.ifr_name.iter_mut().zip(name.bytes()) {
        *slot = byte as c_char;
    }
    Ok(req)
}

fn ctl(fd: RawFd, request: c_ulong, req: &mut ifreq) -> io::Result<()> {
    let code = unsafe { libc::ioctl(fd, request, req as *mut ifreq) };
    if code < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}

fn set_nonblocking(fd: RawFd) -> io::Result<()> {
    let flags = unsafe { libc::fcntl(fd, libc::F_GETFL) };
    if flags < 0 {
        return Err(io::Error::last_os_error());
    }
    let code = unsafe { libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK) };
    if code < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}
