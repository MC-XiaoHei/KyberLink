use std::sync::Arc;
use std::thread;
use std::vec::Vec;

use crate::bus::PeerBus;
use crate::esp::{DataPlane, Shards, ESP_OVERHEAD};
use crate::peer::Link;

pub fn fanout<L>(
    bus: &PeerBus,
    links: Vec<L>,
    payload: &[u8],
    per_link: u64,
) -> Vec<thread::JoinHandle<()>>
where
    L: Link + Send + 'static,
{
    let shards = Arc::new(Shards::new(DataPlane::from_bus(bus).tx_seq()));
    let payload = Arc::new(payload.to_vec());
    let frame_len = payload.len() + ESP_OVERHEAD;
    links
        .into_iter()
        .map(|link| {
            let shards = Arc::clone(&shards);
            let payload = Arc::clone(&payload);
            let mut plane = DataPlane::from_bus(bus);
            thread::spawn(move || {
                let mut frame = vec![0u8; frame_len];
                for _ in 0..per_link {
                    let Some(n) = shards.seal(&mut plane, &payload, &mut frame) else {
                        return;
                    };
                    link.send(&frame[..n]);
                }
            })
        })
        .collect()
}
