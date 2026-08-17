import json
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "..", "vectors", "generated")
VECTORS = os.path.join(VECDIR, "sample_in_ball.json")


async def run_one(dut, seed, coeffs_exp):
    dut.ctilde.value = int.from_bytes(bytes.fromhex(seed), "big")
    await Timer(2, units="ns")
    dut.start.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    dut.start.value = 0
    while not dut.done.value:
        await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert not int(dut.error.value), "sample_in_ball error on valid input"
    got = [int(dut.u_dut.coeffs_arr[k].value) for k in range(256)]
    assert got == coeffs_exp, f"idx={next(i for i, (a, b) in enumerate(zip(got, coeffs_exp)) if a != b)}"


@cocotb.test
async def test_sample_in_ball_vectors(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.ctilde.value = 0
    await Timer(25, units="ns")
    dut.rst_n.value = 1
    await Timer(27, units="ns")
    with open(VECTORS) as f:
        vecs = json.load(f)
    for v in vecs:
        await run_one(dut, v["seed"], v["coeffs"])
