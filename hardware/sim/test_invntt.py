import json
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

VECTORS = os.path.join(os.path.dirname(__file__), "..", "..", "vectors", "generated", "invntt.json")


async def run_one(dut, coeffs_in, coeffs_exp):
    v = 0
    for k, c in enumerate(coeffs_in):
        v |= c << (12 * k)
    dut.coeffs_in.value = v
    await Timer(2, units="ns")
    dut.start.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    dut.start.value = 0
    while not dut.done.value:
        await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    got = [int(dut.r[k].value) for k in range(256)]
    assert got == coeffs_exp, f"idx={next(i for i, (a, b) in enumerate(zip(got, coeffs_exp)) if a != b)}"


@cocotb.test
async def test_invntt_vectors(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.coeffs_in.value = 0
    await Timer(25, units="ns")
    dut.rst_n.value = 1
    await Timer(27, units="ns")
    with open(VECTORS) as f:
        vecs = json.load(f)
    for v in vecs:
        await run_one(dut, v["coeffs_in"], v["coeffs_out"])
