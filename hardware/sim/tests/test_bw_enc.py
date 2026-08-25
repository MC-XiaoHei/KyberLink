import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from Crypto.Cipher import AES

SRC_MAC = bytes.fromhex("020000000101")
DST_MAC = bytes.fromhex("020000000102")
SRC_IP = bytes.fromhex("0a000001")
DST_IP = bytes.fromhex("0a000002")
SRC_PORT = 4500
DST_PORT = 4500


def build_esp_frame(key, iv, spi, seq, plain, aad):
    pad = (16 - ((len(plain) + 2) & 0xF)) & 0xF
    pt = plain + b"\x00" * pad + bytes([pad]) + b"\x04"
    nonce = seq + iv[:8]
    aes = AES.new(key, AES.MODE_GCM, nonce=nonce)
    aes.update(aad)
    ct_tag = aes.encrypt(pt) + aes.digest()
    ct = ct_tag[:-16]
    tag = ct_tag[-16:]
    esp = spi + seq + nonce + ct + tag
    udp_len = 8 + len(esp)
    total_len = 20 + udp_len
    udp = (SRC_PORT.to_bytes(2, "big") + DST_PORT.to_bytes(2, "big") +
           udp_len.to_bytes(2, "big") + b"\x00\x00" + esp)
    ip = bytearray(bytes([0x45, 0x00]) + total_len.to_bytes(2, "big") + b"\x00\x00" +
                   bytes([0x40, 0x00, 0x40, 0x11]) + b"\x00\x00" + SRC_IP + DST_IP)
    s = 0
    for i in range(0, len(ip), 2):
        s += (ip[i] << 8) | ip[i + 1]
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    ip[10:12] = ((~s) & 0xFFFF).to_bytes(2, "big")
    udp = bytes(udp)
    return DST_MAC + SRC_MAC + bytes([0x08, 0x00]) + bytes(ip) + udp


async def reset_dut(dut):
    dut.rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(5):
        await RisingEdge(dut.clk)


@cocotb.test()
async def test_bw_enc_frame(dut):
    cocotb.start_soon(Clock(dut.clk, 8, unit="ns").start())
    await reset_dut(dut)

    key = bytes.fromhex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
    spi = (0x11223344).to_bytes(4, "big")
    seq = (0x11223344).to_bytes(4, "big")
    iv = bytes.fromhex("cafebabefacedbaddecaf880")

    dut.key.value = int.from_bytes(key, "big")
    dut.cfg_spi.value = int.from_bytes(spi, "big")
    dut.cfg_iv.value = int.from_bytes(iv, "big")
    dut.seq_in.value = int.from_bytes(seq, "big")
    dut.cfg_src_mac.value = int.from_bytes(SRC_MAC, "big")
    dut.cfg_dst_mac.value = int.from_bytes(DST_MAC, "big")
    dut.cfg_src_ip.value = int.from_bytes(SRC_IP, "big")
    dut.cfg_dst_ip.value = int.from_bytes(DST_IP, "big")
    dut.cfg_src_port.value = SRC_PORT
    dut.cfg_dst_port.value = DST_PORT
    dut.m_tready.value = 1
    await RisingEdge(dut.clk)

    payload = bytes((i * 3 + 1) % 256 for i in range(242))
    lan_frame = SRC_MAC + DST_MAC + bytes([0x08, 0x00]) + bytes(20) + bytes(8) + payload
    exp = build_esp_frame(key, iv, spi, seq, lan_frame, spi + seq)

    dut.s_tvalid.value = 0
    dut.s_tlast.value = 0
    for i, b in enumerate(lan_frame):
        dut.s_tdata.value = b
        dut.s_tvalid.value = 1
        dut.s_tlast.value = (i == len(lan_frame) - 1)
        while not dut.s_tready.value:
            await RisingEdge(dut.clk)
        await RisingEdge(dut.clk)
    dut.s_tvalid.value = 0
    dut.s_tlast.value = 0

    out = bytearray()
    for _ in range(20000):
        await RisingEdge(dut.clk)
        if int(dut.m_tvalid.value):
            out.append(int(dut.m_tdata.value))
            if int(dut.m_tlast.value):
                break
    dut._log.info(f"enc out {len(out)}B exp {len(exp)}B")
    if out != exp:
        for i in range(min(len(out), len(exp))):
            if out[i] != exp[i]:
                dut._log.error(f"first diff @{i} got={out[i]:02x} exp={exp[i]:02x}")
                break
        assert False, "enc mismatch"
    dut._log.info("enc OK")