import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from Crypto.Cipher import AES


def build_esp(key, iv, spi, seq, plain):
    pad = (16 - ((len(plain) + 2) & 0xF)) & 0xF
    pt = plain + b"\x00" * pad + bytes([pad]) + b"\x04"
    nonce = seq + iv[:8]
    aes = AES.new(key, AES.MODE_GCM, nonce=nonce)
    aes.update(spi + seq)
    ct_tag = aes.encrypt(pt) + aes.digest()
    return spi + seq + nonce + ct_tag


async def reset_dut(dut):
    dut.rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(5):
        await RisingEdge(dut.clk)


@cocotb.test()
async def test_bw_dec_frame(dut):
    cocotb.start_soon(Clock(dut.clk, 8, unit="ns").start())
    await reset_dut(dut)

    key = bytes.fromhex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
    spi = (0x84487D97).to_bytes(4, "big")
    seq = (0x11223344).to_bytes(4, "big")
    iv = bytes.fromhex("cafebabefacedbaddecaf880")
    dut.key.value = int.from_bytes(key, "big")
    dut.m_tready.value = 1
    await RisingEdge(dut.clk)

    payload = bytes((i * 3 + 1) % 256 for i in range(242))
    plain = bytes([0x02, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02]) + bytes(7) + payload
    esp = build_esp(key, iv, spi, seq, plain)

    dut.s_tvalid.value = 0
    dut.s_tlast.value = 0
    for i, b in enumerate(esp):
        dut.s_tdata.value = b
        dut.s_tvalid.value = 1
        dut.s_tlast.value = (i == len(esp) - 1)
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
    dut._log.info(f"dec out {len(out)}B exp {len(plain)}B tag_ok={int(dut.tag_ok.value)}")
    if out != plain:
        for i in range(min(len(out), len(plain))):
            if out[i] != plain[i]:
                dut._log.error(f"first diff @{i} got={out[i]:02x} exp={plain[i]:02x}")
                break
        assert False, f"dec mismatch len={len(out)}/{len(plain)}"
    dut._log.info("dec OK")