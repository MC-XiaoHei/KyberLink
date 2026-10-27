use core::cell::RefCell;
use std::rc::Rc;
use std::time::Instant;
use std::vec::Vec;

use embassy_sync::blocking_mutex::CriticalSectionMutex;
use kyberlink_core::handshake_fsm::{write_sa, Config, Fsm, FsmOutcome, Role};
use kyberlink_crypto::entropy::KemSeeds;
use kyberlink_crypto::mldsa_internal::VerifyPrecomp;

use crate::bus::PeerBus;
use crate::identity::MemIdentity;

const SA_SEQ_INIT: u32 = 1;

pub trait Link {
    fn send(&self, payload: &[u8]);
    fn recv(&self) -> Option<Vec<u8>>;
}

#[derive(Clone)]
pub struct Channel {
    inbox: Rc<RefCell<Vec<Vec<u8>>>>,
    outbox: Rc<RefCell<Vec<Vec<u8>>>>,
}

impl Link for Channel {
    fn send(&self, payload: &[u8]) {
        self.outbox.borrow_mut().push(payload.to_vec());
    }

    fn recv(&self) -> Option<Vec<u8>> {
        let mut q = self.inbox.borrow_mut();
        if q.is_empty() {
            None
        } else {
            Some(q.remove(0))
        }
    }
}

pub fn channel_pair() -> (Channel, Channel) {
    let a: Rc<RefCell<Vec<Vec<u8>>>> = Rc::new(RefCell::new(Vec::new()));
    let b: Rc<RefCell<Vec<Vec<u8>>>> = Rc::new(RefCell::new(Vec::new()));
    (
        Channel {
            inbox: a.clone(),
            outbox: b.clone(),
        },
        Channel {
            inbox: b,
            outbox: a,
        },
    )
}

pub struct Peer {
    fsm: Fsm<PeerBus, MemIdentity>,
    pc: Box<VerifyPrecomp>,
    bus: PeerBus,
    link: Box<dyn Link>,
    sent: u32,
    recv: u32,
    sa_written: bool,
    last: Instant,
}

impl Peer {
    pub fn new(
        peer_fp: [u8; 32],
        seeds: KemSeeds,
        identity: MemIdentity,
        link: Box<dyn Link>,
    ) -> Self {
        let bus = PeerBus::new();
        let cfg = Config {
            peer_fp,
            seeds: CriticalSectionMutex::new(RefCell::new(seeds)),
            identity,
        };
        Peer {
            fsm: Fsm::new(cfg, bus.clone()),
            pc: Box::new(VerifyPrecomp::const_zeroed()),
            bus,
            link,
            sent: 0,
            recv: 0,
            sa_written: false,
            last: Instant::now(),
        }
    }

    pub fn bus(&self) -> PeerBus {
        self.bus.clone()
    }

    pub fn role(&self) -> Role {
        self.fsm.role
    }

    pub fn counters(&self) -> (u32, u32) {
        (self.sent, self.recv)
    }

    pub fn poll(&mut self) -> FsmOutcome {
        let now = Instant::now();
        let elapsed = now.duration_since(self.last).as_millis() as u32;
        self.last = now;
        self.pump();
        let outcome = self.fsm.poll_ms(elapsed, Some(&mut self.pc));
        if let FsmOutcome::Sa(sa) = &outcome {
            if !self.sa_written {
                let initiator = self.fsm.role == Role::Initiator;
                write_sa(&self.bus, sa, initiator, SA_SEQ_INIT);
                self.sa_written = true;
            }
        }
        outcome
    }

    fn pump(&mut self) {
        while let Some(d) = self.bus.take_datagram() {
            self.link.send(&d);
            self.sent += 1;
        }
        while let Some(d) = self.link.recv() {
            self.bus.push_datagram(&d);
            self.recv += 1;
        }
    }
}
