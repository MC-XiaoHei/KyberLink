import os
import json
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "..", "vectors", "generated")
VECTORS = os.path.join(VECDIR, "matmul.json")


async def reset_dut(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst_n.value = 0
    await Timer(25, units="ns")
    dut.rst_n.value = 1
    await Timer(2, units="ns")


@cocotb.test()
async def test_matmul_vectors(dut):
    with open(VECTORS) as f:
        vecs = json.load(f)
    await reset_dut(dut)
    for v in vecs:
        dut.mode.value = v["transpose"]
        dut.a_in.value = sum(v["coeffs_a"][256 * j + k] << (12 * (256 * j + k)) for j in range(9) for k in range(256))
        dut.b_in.value = sum(v["coeffs_b"][256 * j + k] << (12 * (256 * j + k)) for j in range(3) for k in range(256))
        await Timer(2, units="ns")
        dut.start.value = 1
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        dut.start.value = 0
        while not int(dut.done.value):
            await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        got = [[int(dut.c_arr[256 * i + k].value) for k in range(256)] for i in range(3)]
        exp = [v["coeffs_c"][256 * i:256 * (i + 1)] for i in range(3)]
        assert got == exp, f"index {v['index']} transpose={v['transpose']} mismatch"
        dut._log.info(f"index {v['index']} transpose={v['transpose']} ok")
