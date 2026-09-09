import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer

KEY = int.from_bytes(bytes(range(32)), "big")
SPI = 0x11223344
IV = 0x0102030405060708090a0b0c
SRC_IP = 0xc0a80101
DST_IP = 0xc0a80102
SRC_PORT = 4500
DST_PORT = 4500
SRC_MAC = 0x001122334455
DST_MAC = 0x66778899aabb


def make_frame(n):
    return bytes((i * 7 + 3) & 0xFF for i in range(n))


@cocotb.test()
async def enc_3168(dut):
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

    frame = bytes([0x55] * 3168)
    idx = 0
    out = bytearray()
    done = False
    mu = dut.u_enc
    for cyc in range(3000):
        if int(dut.s_enc_tready.value) and idx < len(frame):
            dut.s_enc_tdata.value = frame[idx]
            dut.s_enc_tvalid.value = 1
            dut.s_enc_tlast.value = 1 if idx == len(frame) - 1 else 0
            idx += 1
        elif idx >= len(frame):
            dut.s_enc_tvalid.value = 0
            dut.s_enc_tlast.value = 0
        if int(dut.m_enc_tvalid.value):
            out.append(int(dut.m_enc_tdata.value))
        if idx >= len(frame) and out and cyc % 200 == 0:
            print(f"cyc={cyc} idx={idx} outlen={len(out)} pend={int(mu.enc_pend.value)} "
                  f"es={int(mu.es.value)} frm_len={int(mu.frm_len_p[0].value)} "
                  f"pt_len={int(mu.pt_len_e.value)} enc_nct={int(mu.enc_nct.value)} "
                  f"ct_idx={int(mu.ct_idx.value)} gtagv={int(dut.u_gcm.tag_valid.value)} "
                  f"mvalid={int(dut.m_enc_tvalid.value)}", flush=True)
        await ClockCycles(dut.clk, 1)
    print(f"RESULT outlen={len(out)} idx={idx} last={out[-8:].hex() if out else ''}", flush=True)
