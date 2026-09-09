import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

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


async def enc_frame(dut, data):
    out = bytearray()
    idx = 0
    dut.s_enc_tdata.value = 0
    dut.s_enc_tvalid.value = 0
    dut.s_enc_tlast.value = 0
    for _ in range(30000):
        if int(dut.s_enc_tready.value) and idx < len(data):
            dut.s_enc_tdata.value = data[idx]
            dut.s_enc_tvalid.value = 1
            dut.s_enc_tlast.value = 1 if idx == len(data) - 1 else 0
            idx += 1
        elif idx >= len(data):
            dut.s_enc_tvalid.value = 0
            dut.s_enc_tlast.value = 0
        dut.m_enc_tready.value = 1
        ae = dut.u_gcm
        if int(dut.m_enc_tvalid.value):
            out.append(int(dut.m_enc_tdata.value))
            if int(dut.m_enc_tlast.value):
                break
        await ClockCycles(dut.clk, 1)
    else:
        raise AssertionError("enc timeout")
    return bytes(out)


async def dec_frame(dut, data):
    out = bytearray()
    idx = 0
    dut.s_dec_tdata.value = 0
    dut.s_dec_tvalid.value = 0
    dut.s_dec_tlast.value = 0
    for i in range(30000):
        if int(dut.s_dec_tready.value) and idx < len(data):
            dut.s_dec_tdata.value = data[idx]
            dut.s_dec_tvalid.value = 1
            dut.s_dec_tlast.value = 1 if idx == len(data) - 1 else 0
            idx += 1
        elif idx >= len(data):
            dut.s_dec_tvalid.value = 0
            dut.s_dec_tlast.value = 0
        dut.m_dec_tready.value = 1
        if int(dut.m_dec_tvalid.value):
            out.append(int(dut.m_dec_tdata.value))
            if int(dut.m_dec_tlast.value):
                break
        await ClockCycles(dut.clk, 1)

    else:
        g = dut.u_dec_gcm
        d = dut.u_dec
        print(f"dec timeout tag gcm={int(g.tag.value):032x} tag_p0={int(d.tag_p[0].value):032x} "
              f"tag_p1={int(d.tag_p[1].value):032x} tagq={int(d.tag_q.value):032x} "
              f"tvq={int(d.tag_valid_q.value)} ds={int(d.ds.value)} ok={int(dut.tag_ok.value)}", flush=True)
        raise AssertionError("dec timeout")
    return bytes(out), int(dut.tag_ok.value)

async def setup(dut):
    dut.key_enc.value = KEY
    dut.key_dec.value = KEY
    dut.cfg_spi.value = SPI
    dut.cfg_iv.value = IV
    dut.cfg_src_ip.value = SRC_IP
    dut.cfg_dst_ip.value = DST_IP
    dut.cfg_src_port.value = SRC_PORT
    dut.cfg_dst_port.value = DST_PORT
    dut.cfg_src_mac.value = SRC_MAC
    dut.cfg_dst_mac.value = DST_MAC
    dut.seq_enc_in.value = 1
    dut.key_load.value = 0
    dut.s_enc_tdata.value = 0
    dut.s_enc_tvalid.value = 0
    dut.s_enc_tlast.value = 0
    dut.s_dec_tdata.value = 0
    dut.s_dec_tvalid.value = 0
    dut.s_dec_tlast.value = 0
    dut.m_enc_tready.value = 0
    dut.m_dec_tready.value = 0


@cocotb.test()
async def bridge_roundtrip(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    await setup(dut)
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    dut.key_load.value = 1
    await ClockCycles(dut.clk, 1)
    dut.key_load.value = 0
    await ClockCycles(dut.clk, 2)
    seen = set()
    async def pt_snoop():
        n_blk = 0
        while True:
            await ClockCycles(dut.clk, 1)
            g = dut.u_gcm
            if int(g.ct_valid.value) and int(g.ct_ready.value) and int(dut.m_enc_tready.value):
                if n_blk < 6:
                    print(f"ENC ct blk {n_blk}: {int(g.ct_data.value):032x} "
                          f"ph={int(g.phase.value)} ad={int(g.aes_done.value)}", flush=True)
                n_blk += 1
    ps = cocotb.start_soon(pt_snoop())
    for i, n in enumerate((64, 1400, 1402, 64)):
        frame = make_frame(n)
        esp = await enc_frame(dut, frame)
        print(f"roundtrip {i}: n={n} esp_len={len(esp)} esp42={esp[42:].hex()}", flush=True)
        assert esp[:14] == bytes.fromhex("66778899aabb0011223344550800"), f"eth hdr {i} len {len(esp)} got {esp[:14].hex()}"
        g = dut.u_gcm
        e = dut.u_enc
        print(f"  gcm.tag={int(g.tag.value):032x} tx_tag_p0={int(e.tx_tag_p[0].value):032x} "
              f"tx_tag_p1={int(e.tx_tag_p[1].value):032x} gtv={int(g.tag_valid.value)}", flush=True)
        assert esp[42:46] == SPI.to_bytes(4, "big"), f"spi {i}"
        plain, _ = await dec_frame(dut, esp[42:])
        print(f"plain {i}: len={len(plain)} hex={plain.hex()}", flush=True)
        assert plain == frame, f"plain {i} len {len(plain)} vs {len(frame)}"


@cocotb.test()
async def bridge_rekey(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    await setup(dut)
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    dut.key_load.value = 1
    await ClockCycles(dut.clk, 1)
    dut.key_load.value = 0
    await ClockCycles(dut.clk, 2)

    frame = make_frame(600)
    esp1 = await enc_frame(dut, frame)
    plain1, ok1 = await dec_frame(dut, esp1[42:])
    assert plain1 == frame and ok1, "baseline roundtrip"

    key2 = KEY ^ 0xA5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5
    dut.key_enc.value = key2
    dut.key_dec.value = key2
    dut.key_load.value = 1
    await ClockCycles(dut.clk, 1)
    dut.key_load.value = 0
    await ClockCycles(dut.clk, 2)

    esp2 = await enc_frame(dut, frame)
    assert esp2[42:] != esp1[42:], "ciphertext unchanged after rekey"
    plain2, ok2 = await dec_frame(dut, esp2[42:])
    assert plain2 == frame and ok2, "rekey roundtrip"


@cocotb.test()
async def bridge_seq_wrap(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    await setup(dut)
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    dut.key_load.value = 1
    await ClockCycles(dut.clk, 1)
    dut.key_load.value = 0
    await ClockCycles(dut.clk, 2)

    frame = make_frame(200)
    esp0 = await enc_frame(dut, frame)
    plain0, ok0 = await dec_frame(dut, esp0[42:])
    assert plain0 == frame and ok0, "baseline roundtrip"

    dut.seq_enc_in.value = 0xFFFFFFFE
    dut.key_load.value = 1
    await ClockCycles(dut.clk, 1)
    dut.key_load.value = 0
    await ClockCycles(dut.clk, 2)

    for expect in (0xFFFFFFFE, 0xFFFFFFFF, 0x00000000):
        esp = await enc_frame(dut, frame)
        got = int.from_bytes(esp[46:50], "big")
        assert got == expect, f"enc seq {got:08x} vs {expect:08x}"
        plain, ok = await dec_frame(dut, esp[42:])
        assert plain == frame, f"plain seq {expect:08x} len {len(plain)}"
        assert ok, f"tag fail at seq {expect:08x}"
    assert int(dut.u_dec.last_seq_r.value) == 0, f"last_seq_r {int(dut.u_dec.last_seq_r.value):08x}"

@cocotb.test()
async def ovs_boundary(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    await setup(dut)
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    dut.key_load.value = 1
    await ClockCycles(dut.clk, 1)
    dut.key_load.value = 0
    await ClockCycles(dut.clk, 2)

    esp = await enc_frame(dut, make_frame(1422))
    assert len(esp) == 42 + 20 + 1424 + 16, f"1422 esp len {len(esp)}"
    await ClockCycles(dut.clk, 20)
    hit = []

    async def ovs_watch():
        for _ in range(32000):
            await ClockCycles(dut.clk, 1)
            if int(dut.err_oversize.value):
                hit.append(1)

    w = cocotb.start_soon(ovs_watch())
    rejected = False
    try:
        await enc_frame(dut, make_frame(1423))
    except AssertionError:
        rejected = True
    await w
    assert rejected, "1423 not rejected"
    assert hit, "err_oversize pulse not seen"
    print("ovs boundary 1422 ok / 1423 rejected PASS", flush=True)
