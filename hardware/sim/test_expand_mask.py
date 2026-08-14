import json
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "vectors", "generated")
VECTORS = os.path.join(VECDIR, "expand_mask.json")


async def run_one(dut, seed, coeffs_exp):
    dut.rho.value = int.from_bytes(bytes.fromhex(seed[:128]), "big")
    dut.mu.value = int.from_bytes(bytes.fromhex(seed[128:]), "little")
    await Timer(2, units="ns")
    dut.start.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    dut.start.value = 0
    while not dut.done.value:
        await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    got = [int(dut.coeffs_arr[k].value) for k in range(256)]
    assert got == coeffs_exp, f"idx={next(i for i, (a, b) in enumerate(zip(got, coeffs_exp)) if a != b)}"


@cocotb.test
async def test_expand_mask_vectors(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.rho.value = 0
    dut.mu.value = 0
    await Timer(25, units="ns")
    dut.rst_n.value = 1
    await Timer(27, units="ns")
    with open(VECTORS) as f:
        vecs = json.load(f)
    for v in vecs:
        await run_one(dut, v["seed"], v["coeffs"])
