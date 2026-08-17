import json
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "..", "vectors", "generated")
VECTORS = os.path.join(VECDIR, "shake.json")


async def run_one(dut, msg_hex, digest_hex):
    msg = bytes.fromhex(msg_hex)
    blk = msg + b"\x00" * (136 - len(msg))
    dut.len.value = len(msg)
    dut.msg.value = int.from_bytes(blk, "big")
    await Timer(2, units="ns")
    dut.start.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    dut.start.value = 0
    while not dut.done.value:
        await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    got = int(dut.out.value).to_bytes(32, "big")
    assert got.hex() == digest_hex, f"msg_len={len(msg)} got={got.hex()} expect={digest_hex}"


@cocotb.test
async def test_shake256_vectors(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.len.value = 0
    dut.msg.value = 0
    await Timer(25, units="ns")
    dut.rst_n.value = 1
    await Timer(27, units="ns")
    with open(VECTORS) as f:
        vecs = json.load(f)
    for v in vecs:
        await run_one(dut, v["msg"], v["digest"])
