import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer

VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "..", "vectors", "generated")
VECTORS = os.path.join(VECDIR, "ghash.json")


@cocotb.test()
async def test_ghash_vectors(dut):
    import json

    with open(VECTORS) as f:
        vecs = json.load(f)

    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    dut.rst_n.value = 0
    await Timer(25, units="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    for v in vecs:
        dut.start.value = 1
        dut.h.value = int(v["h"], 16)
        dut.nblocks.value = len(v["blocks"])
        await RisingEdge(dut.clk)
        dut.start.value = 0
        for b in v["blocks"]:
            n = 0
            while int(dut.ready.value) == 0:
                await RisingEdge(dut.clk)
                n += 1
                if n > 1000:
                    raise AssertionError("ghash ready timeout")
            dut.data_in.value = int(b, 16)
            dut.data_valid.value = 1
            n = 0
            while int(dut.ready.value) == 1:
                await RisingEdge(dut.clk)
                n += 1
                if n > 1000:
                    raise AssertionError("ghash accept timeout")
            dut.data_valid.value = 0
        while dut.done.value == 0:
            await RisingEdge(dut.clk)
        got = int(dut.tag.value)
        exp = int(v["tag"], 16)
        if got != exp:
            dut._log.error("index %d: got %016x exp %016x", v["index"], got, exp)
            raise AssertionError("ghash mismatch")
