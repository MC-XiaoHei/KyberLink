import json
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "..", "vectors", "generated")
VECTORS = os.path.join(VECDIR, "basemul.json")


async def run_one(dut, coeffs_a, coeffs_b, coeffs_exp):
    va = 0
    vb = 0
    for k, c in enumerate(coeffs_a):
        va |= c << (12 * k)
    for k, c in enumerate(coeffs_b):
        vb |= c << (12 * k)
    dut.coeffs_a.value = va
    dut.coeffs_b.value = vb
    await Timer(2, units="ns")
    dut.start.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    dut.start.value = 0
    while not dut.done.value:
        await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    got = [int(dut.rc[k].value) for k in range(256)]
    assert got == coeffs_exp, f"idx={next(i for i, (a, b) in enumerate(zip(got, coeffs_exp)) if a != b)}"


@cocotb.test
async def test_basemul_vectors(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.coeffs_a.value = 0
    dut.coeffs_b.value = 0
    await Timer(25, units="ns")
    dut.rst_n.value = 1
    await Timer(27, units="ns")
    with open(VECTORS) as f:
        vecs = json.load(f)
    for v in vecs:
        await run_one(dut, v["coeffs_a"], v["coeffs_b"], v["coeffs_out"])
