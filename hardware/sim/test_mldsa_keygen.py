import os
import json
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge
from cocotb.utils import get_sim_time

VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "vectors", "generated")
VECTORS = os.path.join(VECDIR, "mldsa_keygen_mid.json")


async def reset_dut(dut):
    dut.start.value = 0
    dut.seed.value = 0
    await Timer(25, units="ns")
    dut.rst_n.value = 0
    await Timer(25, units="ns")
    dut.rst_n.value = 1
    await Timer(2, units="ns")


@cocotb.test()
async def test_mldsa_keygen(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    with open(VECTORS) as f:
        vecs = json.load(f)

    for v in vecs:
        dut.seed.value = int(v["seed"], 16)
        await RisingEdge(dut.clk)
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0
        await RisingEdge(dut.clk)
        dut.start.value = 0

        while int(dut.done.value) != 1:
            await RisingEdge(dut.clk)
        await Timer(1, units="ns")

        got_vk = bytes(int(dut.vk_byte[k].value) for k in range(1952))
        got_sk = bytes(int(dut.sk_byte[k].value) for k in range(4032))
        assert got_vk.hex() == v["vk"], f"idx={v['index']} vk mismatch"
        assert got_sk.hex() == v["sk"], f"idx={v['index']} sk mismatch"
        await RisingEdge(dut.clk)
