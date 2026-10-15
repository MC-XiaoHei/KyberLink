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

#[test]
fn two_peers_agree_on_keys() {
    let id_a = MemIdentity::from_seed(&[1u8; 32]);
    let id_b = MemIdentity::from_seed(&[2u8; 32]);
    let fp_a = id_a.fingerprint();
    let fp_b = id_b.fingerprint();

    let (link_a, link_b) = channel_pair();
    let mut a = Peer::new(fp_b, seeds(1), id_a, Box::new(link_a));
    let mut b = Peer::new(fp_a, seeds(2), id_b, Box::new(link_b));

    let mut sa_a = None;
    let mut sa_b = None;
    for _ in 0..200_000 {
        if let FsmOutcome::Sa(sa) = a.poll() {
            if sa_a.is_none() {
                sa_a = Some(sa);
            }
        }
        if let FsmOutcome::Sa(sa) = b.poll() {
            if sa_b.is_none() {
                sa_b = Some(sa);
            }
        }
        if sa_a.is_some() && sa_b.is_some() {
            break;
        }
    }

    let sa_a = sa_a.expect("first peer did not complete the handshake");
    let sa_b = sa_b.expect("second peer did not complete the handshake");
    assert_eq!(sa_a.sk_ei, sa_b.sk_ei, "direction keys differ");
    assert_eq!(sa_a.sk_er, sa_b.sk_er, "direction keys differ");
    assert!(
        a.bus().key_loads() > 0,
        "no SA was written to the data plane"
    );
    assert_ne!(a.bus().reg(0x44), 0, "encryption key register is empty");
    assert_ne!(b.bus().reg(0x44), 0, "encryption key register is empty");
}
