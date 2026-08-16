import json
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "vectors", "generated")
VECTORS = os.path.join(VECDIR, "sample_cbd.json")


async def run_one(dut, seed_hex, coeffs_exp):
    seed = bytes.fromhex(seed_hex)
    dut.rho.value = int.from_bytes(seed[:32], "big")
    dut.i.value = seed[32]
    await Timer(2, units="ns")
    dut.start.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    dut.start.value = 0
    while not dut.done.value:
        await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    v = int(dut.coeffs.value)
    got = []
    for k in range(256):
        c = (v >> (3 * k)) & 0x7
        if c >= 4:
            c -= 8
        got.append(c)
    assert got == coeffs_exp, f"seed={seed_hex[:16]}.. idx={next(i for i, (a, b) in enumerate(zip(got, coeffs_exp)) if a != b)}"


@cocotb.test
async def test_sample_cbd_vectors(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.rho.value = 0
    dut.i.value = 0
    await Timer(25, units="ns")
    dut.rst_n.value = 1
    await Timer(27, units="ns")
    with open(VECTORS) as f:
        vecs = json.load(f)
    for v in vecs:
        await run_one(dut, v["seed"], v["coeffs"])
