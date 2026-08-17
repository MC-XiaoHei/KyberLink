import json
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "..", "vectors", "generated")
VECTORS = os.path.join(VECDIR, "sha3_256.json")


@cocotb.test()
async def test_sha3_256_vectors(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.msg_wr.value = 0
    await Timer(25, units="ns")
    dut.rst_n.value = 1
    await Timer(2, units="ns")

    with open(VECTORS) as f:
        vecs = json.load(f)

    for v in vecs:
        msg = bytes.fromhex(v["msg"])
        total = len(msg)
        for i, b in enumerate(msg):
            dut.msg_wdata.value = b
            dut.msg_waddr.value = i
            dut.msg_wr.value = 1
            await RisingEdge(dut.clk)
        dut.msg_wr.value = 0
        dut.len.value = total
        dut.start.value = 1
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        dut.start.value = 0
        while int(dut.done.value) != 1:
            await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        got = int(dut.digest.value).to_bytes(32, "big").hex()
        assert got == v["hash"], f"idx={v['index']} len={total} got={got} exp={v['hash']}"
