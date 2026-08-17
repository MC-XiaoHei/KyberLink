import json
import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "..", "vectors", "generated")
VECTORS = os.path.join(VECDIR, "mldsa_verify_mid.json")


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.start.value = 0
    await Timer(25, units="ns")
    dut.rst_n.value = 1
    await Timer(2, units="ns")


@cocotb.test()
async def test_verify_vectors(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    with open(VECTORS) as f:
        vecs = json.load(f)

    for v in vecs:
        vk = bytes.fromhex(v["vk"])
        sig = bytes.fromhex(v["sig"])
        mu = bytes.fromhex(v["mu_b"])

        dut.vk_in.value = int.from_bytes(vk, "big")
        dut.sig_in.value = int.from_bytes(sig, "big")
        dut.mu_b.value = int.from_bytes(mu, "big")

        dut.start.value = 1
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        dut.start.value = 0

        while int(dut.done.value) != 1:
            await RisingEdge(dut.clk)
        await Timer(1, units="ns")

        got = int(dut.valid_out.value)
        exp = 1 if v["ok"] else 0
        assert got == exp, f"idx={v['index']} valid got={got} exp={exp}"
