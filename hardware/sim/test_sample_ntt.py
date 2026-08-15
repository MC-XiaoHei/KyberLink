import json
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "vectors", "generated")
VECTORS = os.path.join(VECDIR, "sample_ntt.json")


async def run_one(dut, v):
    seed = bytes.fromhex(v["seed"])
    dut.rho.value = int.from_bytes(seed[:32], "big")
    dut.i.value = seed[32]
    dut.j.value = seed[33]
    await Timer(2, units="ns")
    dut.start.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    dut.start.value = 0
    while not dut.done.value:
        await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert not int(dut.error.value), "sample_ntt error on valid input"
    got = [int(dut.u_dut.coeffs_arr[k].value) for k in range(256)]
    assert got == v["coeffs"], f"idx={next(i for i, (a, b) in enumerate(zip(got, v['coeffs'])) if a != b)}"


@cocotb.test
async def test_sample_ntt_vectors(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.rho.value = 0
    dut.i.value = 0
    dut.j.value = 0
    await Timer(25, units="ns")
    dut.rst_n.value = 1
    await Timer(27, units="ns")
    with open(VECTORS) as f:
        vecs = json.load(f)
    for v in vecs:
        await run_one(dut, v)
