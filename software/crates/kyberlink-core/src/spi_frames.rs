pub fn write_frame(addr: u8, data: u32) -> [u8; 5] {
    [
        addr & 0x7F,
        (data >> 24) as u8,
        (data >> 16) as u8,
        (data >> 8) as u8,
        data as u8,
    ]
}

pub fn read_frame(addr: u8) -> [u8; 5] {
    [0x80 | (addr & 0x7F), 0, 0, 0, 0]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn write_frame_matches_master_sequence() {
        let f = write_frame(0x14, 0xDEADBEEF);
        let word = (0x14u64 << 32) | 0xDEADBEEFu64;
        let expect: [u8; 5] = [
            (word >> 32) as u8,
            (word >> 24) as u8,
            (word >> 16) as u8,
            (word >> 8) as u8,
            word as u8,
        ];
        assert_eq!(f, expect);
        assert_eq!(f[0] & 0x80, 0, "write flag must be 0");
    }

    #[test]
    fn read_frame_sets_flag_and_7bit_addr() {
        let f = read_frame(0x34);
        assert_eq!(f[0], 0x80 | 0x34);
        let f2 = read_frame(0x00);
        assert_eq!(f2[0], 0x80);
        assert_eq!(f2[1..], [0, 0, 0, 0]);
    }

    #[test]
    fn frames_roundtrip_through_slave_bit_positions() {
        for (addr, data) in [(0x00u8, 0u32), (0x3C, 0x1234ABCD), (0x64, 0xFFFFFFFF)] {
            let f = write_frame(addr, data);
            assert_eq!(f[0] << 1 >> 1 & 0x7F, addr & 0x7F);
            assert_eq!(
                u32::from_be_bytes([f[1], f[2], f[3], f[4]]),
                data,
                "data must be big-endian after address"
            );
        }
    }
}
