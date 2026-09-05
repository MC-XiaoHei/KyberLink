import zlib

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

SRC_MAC = 0x001122334455
DST_MAC = 0x66778899AABB
ETH_TYPE = 0x0800


def build_gmii_frame(payload, bad_fcs=False):
    eth = DST_MAC.to_bytes(6, "big") + SRC_MAC.to_bytes(6, "big") + ETH_TYPE.to_bytes(2, "big")
    body = eth + payload
    fcs = zlib.crc32(body) & 0xFFFFFFFF
    if bad_fcs:
        fcs ^= 0xDEADBEEF
    return body + fcs.to_bytes(4, "little")


async def drive(dut, frame):
    for j, b in enumerate(frame):
        dut.gmii_rxd.value = b
        dut.gmii_rx_dv.value = 1
        dut.gmii_rx_er.value = 0
        await ClockCycles(dut.clk, 1)
    dut.gmii_rxd.value = 0
    dut.gmii_rx_dv.value = 0
    await ClockCycles(dut.clk, 1)


async def boot(dut):
    dut.rst.value = 1
    dut.gmii_rxd.value = 0
    dut.gmii_rx_dv.value = 0
    dut.gmii_rx_er.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 3)


async def run_frame(dut, frm):
    got = bytearray()
    last_tuser = [None]

    async def collect():
        for _ in range(3000):
            if int(dut.m_axis_tvalid.value):
                got.append(int(dut.m_axis_tdata.value))
                if int(dut.m_axis_tlast.value):
                    last_tuser[0] = int(dut.m_axis_tuser.value)
                    break
            await ClockCycles(dut.clk, 1)
        else:
            raise AssertionError("collect timeout")

    c = cocotb.start_soon(collect())
    await drive(dut, b"\x55" * 7 + b"\xD5" + frm)
    await c
    await ClockCycles(dut.clk, 3)
    return bytes(got), last_tuser[0]


@cocotb.test()
async def good_frame(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    await boot(dut)
    payload = bytes((j * 7 + 3) & 0xFF for j in range(60))
    frm = build_gmii_frame(payload)
    got, tuser = await run_frame(dut, b"\x55" * 7 + b"\xD5" + frm)
    body = got[got.index(b"\xD5") + 1:] if b"\xD5" in got else got
    assert body == frm[:-4], f"frame mismatch body={body.hex()}"
    assert int(dut.error_bad_frame.value) == 0, "good frame raised bad_frame"
    print(f"gmii good_frame PASS out_len={len(got)} body_ok tuser={tuser}", flush=True)


@cocotb.test()
async def bad_fcs_frame(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    await boot(dut)
    payload = bytes((j * 7 + 3) & 0xFF for j in range(60))
    frm = build_gmii_frame(payload, bad_fcs=True)
    hit = [0]

    async def watch():
        for _ in range(3000):
            if int(dut.error_bad_fcs.value):
                hit[0] += 1
            await ClockCycles(dut.clk, 1)

    w = cocotb.start_soon(watch())
    got, tuser = await run_frame(dut, b"\x55" * 7 + b"\xD5" + frm)
    await w
    assert hit[0] > 0, "bad_fcs pulse not seen"
    assert tuser == 1, f"bad frame tuser={tuser}"
    print(f"gmii bad_fcs_frame PASS hits={hit[0]} tuser={tuser}", flush=True)


@cocotb.test()
async def bad_then_good(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    await boot(dut)
    payload = bytes((j * 7 + 3) & 0xFF for j in range(60))
    frm = build_gmii_frame(payload)
    bad_frm = build_gmii_frame(payload, bad_fcs=True)
    bad_out, bad_tuser = await run_frame(dut, b"\x55" * 7 + b"\xD5" + bad_frm)
    assert bad_tuser == 1, "bad frame not flagged"
    good_out, good_tuser = await run_frame(dut, b"\x55" * 7 + b"\xD5" + frm)
    gbody = good_out[good_out.index(b"\xD5") + 1:] if b"\xD5" in good_out else good_out
    assert gbody == frm[:-4], "recovered frame mismatch"
    print(f"gmii bad_then_good PASS bad_tuser={bad_tuser} good_tuser={good_tuser}", flush=True)


@cocotb.test()
async def er_abort_frame(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    await boot(dut)
    payload = bytes((j * 7 + 3) & 0xFF for j in range(60))
    frm = build_gmii_frame(payload)
    hit = [0]
    out_len = [0]

    async def watch():
        for _ in range(3000):
            if int(dut.error_bad_frame.value):
                hit[0] += 1
            if int(dut.m_axis_tvalid.value):
                out_len[0] += 1
            await ClockCycles(dut.clk, 1)

    w = cocotb.start_soon(watch())
    data = b"\x55" * 7 + b"\xD5" + frm
    for k in range(len(data)):
        abl = k >= len(data) // 2
        dut.gmii_rxd.value = 0 if abl else data[k]
        dut.gmii_rx_dv.value = 1
        dut.gmii_rx_er.value = 1 if abl else 0
        await ClockCycles(dut.clk, 1)
    dut.gmii_rxd.value = 0
    dut.gmii_rx_dv.value = 0
    dut.gmii_rx_er.value = 1
    await ClockCycles(dut.clk, 1)
    dut.gmii_rx_er.value = 0
    await ClockCycles(dut.clk, 3)
    await w
    assert hit[0] > 0, "er_abort bad_frame pulse not seen"
    assert out_len[0] < len(data), f"aborted frame partially leaked len={out_len[0]}"
    print(f"gmii er_abort_frame PASS hits={hit[0]} out_len={out_len[0]}", flush=True)


@cocotb.test()
async def er_tail_frame(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    await boot(dut)
    payload = bytes((j * 7 + 3) & 0xFF for j in range(60))
    frm = build_gmii_frame(payload)
    hit = [0]
    tuser = [None]

    async def watch():
        got = bytearray()
        for _ in range(3000):
            if int(dut.error_bad_frame.value):
                hit[0] += 1
            if int(dut.m_axis_tvalid.value):
                got.append(int(dut.m_axis_tdata.value))
                if int(dut.m_axis_tlast.value):
                    tuser[0] = int(dut.m_axis_tuser.value)
                    break
            await ClockCycles(dut.clk, 1)

    w = cocotb.start_soon(watch())
    data = b"\x55" * 7 + b"\xD5" + frm
    for j, b in enumerate(data):
        dut.gmii_rxd.value = b
        dut.gmii_rx_dv.value = 1
        dut.gmii_rx_er.value = 1 if j >= len(data) - 5 else 0
        await ClockCycles(dut.clk, 1)
    dut.gmii_rxd.value = 0
    dut.gmii_rx_dv.value = 0
    await ClockCycles(dut.clk, 1)
    await w
    assert hit[0] > 0, "er_tail bad_frame pulse not seen"
    assert tuser[0] == 1, f"er_tail frame not flagged tuser={tuser[0]}"
    print(f"gmii er_tail_frame PASS hits={hit[0]} tuser={tuser[0]}", flush=True)
