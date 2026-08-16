import json
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "vectors", "generated")
VECTORS_SHAKE = os.path.join(VECDIR, "shake.json")
VECTORS_LONG = os.path.join(VECDIR, "shakelong.json")


async def run_one(dut, msg_hex, out_hex):
    rate = len(dut.out.value) // 8
    msg = bytes.fromhex(msg_hex)
    blk = msg + b"\x00" * (rate - len(msg))
    expect = bytes.fromhex(out_hex)
    blocks = (len(expect) + rate - 1) // rate
    dut.len.value = len(msg)
    dut.msg.value = int.from_bytes(blk, "big")
    dut.out_blocks.value = blocks
    await Timer(2, units="ns")
    dut.start.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    dut.start.value = 0
    got = b""
    for _ in range(blocks):
        while not dut.done.value:
            await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        take = min(rate, len(expect) - len(got))
        got += int(dut.out.value).to_bytes(rate, "big")[:take]
    assert got == expect, f"msg_len={len(msg)} got={got.hex()} expect={expect.hex()}"


async def init(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.out_blocks.value = 1
    dut.len.value = 0
    dut.msg.value = 0
    await Timer(25, units="ns")
    dut.rst_n.value = 1
    await Timer(27, units="ns")


@cocotb.test
async def test_shake256_vectors(dut):
    await init(dut)
    with open(VECTORS_SHAKE) as f:
        for v in json.load(f):
            await run_one(dut, v["msg"], v["digest"])
    with open(VECTORS_LONG) as f:
        for v in json.load(f):
            await run_one(dut, v["msg"], v["shake256_272"])
