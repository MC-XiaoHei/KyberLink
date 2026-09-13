use std::time::Instant;

fn unpack20_bits(bytes: &[u8], out: &mut [u32]) {
    for (i, o) in out.iter_mut().enumerate() {
        let mut v = 0u32;
        for j in 0..20 {
            let idx = i * 20 + j;
            v |= (((bytes[idx / 8] >> (idx % 8)) & 1) as u32) << j;
        }
        *o = v;
    }
}

fn unpack20_fast(bytes: &[u8], out: &mut [u32]) {
    let mut bitpos = 0usize;
    for o in out.iter_mut() {
        let byte = bitpos / 8;
        let sh = bitpos % 8;
        let mut v: u32 = (bytes[byte] as u32) >> sh;
        // may span 2-3 bytes
        let need = 20 - (8 - sh);
        if need > 0 {
            v |= (bytes[byte + 1] as u32) << (8 - sh);
        }
        if need > 8 {
            v |= (bytes[byte + 2] as u32) << (16 - sh);
        }
        *o = v & 0xFFFFF; // 20-bit mask
        bitpos += 20;
    }
}

fn main() {
    let bytes: Vec<u8> = (0..4000).map(|i| (i * 7 + 13) as u8).collect();
    let mut out1 = vec![0u32; 1536];
    let mut out2 = vec![0u32; 1536];
    unpack20_bits(&bytes, &mut out1);
    unpack20_fast(&bytes, &mut out2);
    assert_eq!(out1, out2, "两种 unpack 结果不一致");

    let t = Instant::now();
    for _ in 0..1000 {
        unpack20_bits(&bytes, &mut out1);
    }
    println!("unpack bit  x1000: {:?}", t.elapsed());

    let t = Instant::now();
    for _ in 0..1000 {
        unpack20_fast(&bytes, &mut out2);
    }
    println!("unpack fast x1000: {:?}", t.elapsed());
}
