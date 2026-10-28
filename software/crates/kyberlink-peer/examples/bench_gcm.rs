use std::time::Instant;

use kyberlink_crypto::gcm::GcmCipher;

const ESP_OVERHEAD: usize = 78;

fn bench(label: &str, payload: usize, iters: u32) {
    let cipher = GcmCipher::new(&[0x11u8; 32]);
    let salt = [0x22u8; 8];
    let mut frame = vec![0u8; payload + ESP_OVERHEAD];
    let mut nonce = [0u8; 12];
    let mut tag = [0u8; 16];

    let start = Instant::now();
    for seq in 0..iters {
        nonce[..4].copy_from_slice(&seq.to_be_bytes());
        nonce[4..].copy_from_slice(&salt);
        let (head, body) = frame.split_at_mut(ESP_OVERHEAD);
        body[0] = seq as u8;
        cipher
            .encrypt_in_place(&nonce, head, body, &mut tag)
            .unwrap();
    }
    let elapsed = start.elapsed().as_secs_f64();
    let bytes = (payload + ESP_OVERHEAD) as f64 * iters as f64;
    let gbps = bytes * 8.0 / elapsed / 1e9;
    let pps = iters as f64 / elapsed;
    println!(
        "{label:<10} payload {payload:>5}B  {pps:>12.0} pps  {gbps:>7.3} Gbps  {:.0} MB/s",
        bytes / elapsed / 1e6
    );
}

fn main() {
    let iters = 200_000;
    for payload in [64usize, 256, 1024, 1422] {
        bench("esp", payload, iters);
    }
}
