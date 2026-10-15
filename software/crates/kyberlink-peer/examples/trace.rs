use kyberlink_core::handshake_fsm::FsmOutcome;
use kyberlink_crypto::entropy::KemSeeds;
use kyberlink_peer::identity::MemIdentity;
use kyberlink_peer::peer::{channel_pair, Peer};

fn seeds(tag: u8) -> KemSeeds {
    KemSeeds {
        d: [tag; 32],
        z: [tag ^ 0x5A; 32],
        nonce: [tag ^ 0xA5; 32],
    }
}

fn main() {
    let id_a = MemIdentity::from_seed(&[1u8; 32]);
    let id_b = MemIdentity::from_seed(&[2u8; 32]);
    let fp_a = id_a.fingerprint();
    let fp_b = id_b.fingerprint();
    println!("fp_a[0..4] = {:02x?}", &fp_a[..4]);
    println!("fp_b[0..4] = {:02x?}", &fp_b[..4]);
    println!(
        "initiator by rule = {}",
        if fp_a < fp_b { "A" } else { "B" }
    );

    let (link_a, link_b) = channel_pair();
    let mut a = Peer::new(fp_b, seeds(1), id_a, Box::new(link_a));
    let mut b = Peer::new(fp_a, seeds(2), id_b, Box::new(link_b));

    let mut sa_a = false;
    let mut sa_b = false;
    for i in 0..2000 {
        if !sa_a {
            if let FsmOutcome::Sa(_) = a.poll() {
                sa_a = true;
            }
        }
        if !sa_b {
            if let FsmOutcome::Sa(_) = b.poll() {
                sa_b = true;
            }
        }
        if i < 12 || i % 200 == 0 {
            println!(
                "i={i:<5} A role={:?} sa={sa_a} sent/recv={:?} rx={}/{}   B role={:?} sa={sa_b} sent/recv={:?} rx={}/{}",
                a.role(),
                a.counters(),
                a.bus().rx_pending(),
                a.bus().rx_len(),
                b.role(),
                b.counters(),
                b.bus().rx_pending(),
                b.bus().rx_len(),
            );
        }
        if sa_a && sa_b {
            println!("both done at i={i}");
            return;
        }
    }
    println!("stalled");
}
