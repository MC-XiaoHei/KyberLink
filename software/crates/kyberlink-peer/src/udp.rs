use std::io::{Error, ErrorKind};
use std::net::{SocketAddr, ToSocketAddrs, UdpSocket};
use std::time::Duration;
use std::vec::Vec;

use crate::peer::Link;

const READ_TIMEOUT: Duration = Duration::from_millis(1);

pub struct UdpLink {
    sock: UdpSocket,
    peer: SocketAddr,
}

impl UdpLink {
    pub fn bind<A: ToSocketAddrs, B: ToSocketAddrs>(local: A, peer: B) -> std::io::Result<Self> {
        Ok(Self::from_socket(UdpSocket::bind(local)?, resolve(peer)?))
    }

    pub fn from_socket(sock: UdpSocket, peer: SocketAddr) -> Self {
        let _ = sock.set_read_timeout(Some(READ_TIMEOUT));
        UdpLink { sock, peer }
    }

    pub fn local_addr(&self) -> std::io::Result<SocketAddr> {
        self.sock.local_addr()
    }
}

fn resolve<B: ToSocketAddrs>(peer: B) -> std::io::Result<SocketAddr> {
    peer.to_socket_addrs()?
        .next()
        .ok_or_else(|| Error::new(ErrorKind::InvalidInput, "no peer address"))
}

impl Link for UdpLink {
    fn send(&self, payload: &[u8]) {
        let _ = self.sock.send_to(payload, self.peer);
    }

    fn recv(&self) -> Option<Vec<u8>> {
        let mut buf = [0u8; 2048];
        match self.sock.recv_from(&mut buf) {
            Ok((n, _)) => Some(buf[..n].to_vec()),
            Err(_) => None,
        }
    }
}
