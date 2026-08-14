import json
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge

VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "vectors", "generated")
VECTORS = os.path.join(VECDIR, "matmul_dsa.json")


async def reset_dut(dut):
    dut.start.value = 0
    await Timer(2, units="ns")
    dut.rst_n.value = 0
    await Timer(25, units="ns")
    dut.rst_n.value = 1
    await Timer(2, units="ns")


@cocotb.test()
async def test_matmul_dsa_vectors(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    with open(VECTORS) as f:
        vecs = json.load(f)
    for v in vecs:
        fa = v["coeffs_a"]
        fb = v["coeffs_b"]
        fc = v["coeffs_c"]
        a_in = 0
        for k in range(7680):
            a_in |= fa[k] << (23 * k)
        b_in = 0
        for k in range(1280):
            b_in |= fb[k] << (23 * k)
        dut.a_in.value = a_in
        dut.b_in.value = b_in
        dut.start.value = 1
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        dut.start.value = 0
        while int(dut.done.value) != 1:
            await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        got = [int(dut.c_arr[k].value) for k in range(1536)]
        assert got == fc, f"index {v['index']} mismatch"
    dut._log.info("matmul_dsa 32 vectors PASS")
