import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

KEY = int.from_bytes(bytes(range(32)), "big")
SPI = 0x11223344
IV = 0x0102030405060708090a0b0c
DST_MAC = 0x66778899aabb


def make_frame(n):
    return bytes((i * 7 + 3) & 0xFF for i in range(n))


@cocotb.test()
async def enc_oversize_3168(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    dut.s_enc_tvalid.value = 0
    dut.s_enc_tlast.value = 0
    dut.m_enc_tready.value = 1
    dut.key_load.value = 0
    dut.soft_rst.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    dut.key_load.value = 1
    dut.key_enc.value = KEY
    dut.key_dec.value = KEY
    dut.cfg_spi.value = SPI
    dut.cfg_iv.value = IV
    await ClockCycles(dut.clk, 1)
    dut.key_load.value = 0
    await ClockCycles(dut.clk, 2)

    big = bytes([0x55] * 3168)
    out = bytearray()
    idx = 0
    oversize_seen = False
    for cyc in range(60000):
        if int(dut.s_enc_tready.value) and idx < len(big):
            dut.s_enc_tdata.value = big[idx]
            dut.s_enc_tvalid.value = 1
            dut.s_enc_tlast.value = 1 if idx == len(big) - 1 else 0
            idx += 1
        elif idx >= len(big):
            dut.s_enc_tvalid.value = 0
            dut.s_enc_tlast.value = 0
        if int(dut.m_enc_tvalid.value):
            out.append(int(dut.m_enc_tdata.value))
        if int(dut.u_enc.err_oversize.value):
            oversize_seen = True
        await ClockCycles(dut.clk, 1)
        if idx >= len(big) and cyc > 100 and oversize_seen:
            break
    dut.s_enc_tvalid.value = 0
    dut.s_enc_tlast.value = 0
    assert oversize_seen, "oversize flag"
    assert len(out) == 0, f"oversize out {len(out)}"

    from Crypto.Cipher import AES
    KEY_B = bytes(range(32))
    frm2 = 1400
    pad2 = (16 - ((frm2 + 2) & 0xF)) & 0xF
    pt2_len = frm2 + 2 + pad2
    seq = 0
    nonce = seq.to_bytes(4, "big") + IV.to_bytes(12, "big")[:8]
    e = AES.new(KEY_B, AES.MODE_GCM, nonce=nonce)
    e.update(SPI.to_bytes(4, "big") + seq.to_bytes(4, "big"))
    pt2 = make_frame(frm2) + bytes(pad2) + bytes([pad2, 4])
    ct_exp = e.encrypt(pt2)
    tag_exp = e.digest()

    out2 = bytearray()
    idx = 0
    for cyc in range(60000):
        if int(dut.s_enc_tready.value) and idx < frm2:
            dut.s_enc_tdata.value = make_frame(frm2)[idx]
            dut.s_enc_tvalid.value = 1
            dut.s_enc_tlast.value = 1 if idx == frm2 - 1 else 0
            idx += 1
        elif idx >= frm2:
            dut.s_enc_tvalid.value = 0
            dut.s_enc_tlast.value = 0
        if int(dut.m_enc_tvalid.value):
            out2.append(int(dut.m_enc_tdata.value))
            if int(dut.m_enc_tlast.value):
                break
        await ClockCycles(dut.clk, 1)
    else:
        raise AssertionError(f"enc timeout outlen={len(out2)} idx={idx}")
    esp = bytes(out2)
    assert len(esp) == 62 + pt2_len + 16, f"esp len {len(esp)}"
    assert esp[42:46] == SPI.to_bytes(4, "big"), f"spi {esp[42:46].hex()}"
    assert esp[46:50] == seq.to_bytes(4, "big"), f"seq {esp[46:50].hex()}"
    assert esp[50:62] == nonce, f"esp nonce {esp[50:62].hex()}"
    ct_hw = esp[62:62 + pt2_len]
    assert ct_hw == ct_exp, f"ct blk0 {ct_hw[:16].hex()} exp {ct_exp[:16].hex()}"
    assert esp[62 + pt2_len:] == tag_exp, f"tag {esp[62 + pt2_len:].hex()} exp {tag_exp.hex()}"
    print(f"oversize rejected, 1400 ok esp={len(esp)}", flush=True)
