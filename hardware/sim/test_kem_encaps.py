import json
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "vectors", "generated")
VECTORS = os.path.join(VECDIR, "kem_encaps_mid.json")


async def reset_dut(dut):
    dut.start.value = 0
    dut.ek_in.value = 0
    dut.m.value = 0
    await Timer(2, units="ns")
    dut.rst_n.value = 0
    await Timer(25, units="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_kem_encaps_vectors(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    with open(VECTORS) as f:
        vecs = json.load(f)

    for v in vecs:
        dut.start.value = 1
        dut.ek_in.value = int(v["ek"], 16)
        dut.m.value = int(v["m"], 16)
        await RisingEdge(dut.clk)
        dut.start.value = 0
        while not dut.done.value:
            await RisingEdge(dut.clk)
        await Timer(1, units="ns")

        k_got = int(dut.k_out.value)
        k_exp = int(v["K"], 16)
        assert k_got == k_exp, f"K mismatch idx={v['index']}: got {k_got:064x} exp {k_exp:064x}"

        c_got = bytes(int(dut.c_byte[k].value) for k in range(1088))
        c_exp = bytes.fromhex(v["c"])
        assert c_got == c_exp, f"c mismatch idx={v['index']}"
        await RisingEdge(dut.clk)
