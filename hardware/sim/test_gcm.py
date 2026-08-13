import os
import json
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "vectors", "generated")
VECTORS = os.path.join(VECDIR, "cipher.json")


async def reset_dut(dut):
    dut.rst_n.value = 0
    await Timer(25, units="ns")
    dut.rst_n.value = 1
    await Timer(27, units="ns")


@cocotb.test()
async def test_gcm_vectors(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.start.value = 0
    await reset_dut(dut)
    with open(VECTORS) as f:
        vecs = json.load(f)
    for v in vecs:
        dut.key.value = int(v["key"], 16)
        dut.nonce.value = int(v["nonce"], 16)
        dut.aad.value = int(v["aad"], 16)
        dut.plaintext_in.value = int(v["plaintext"], 16)
        await Timer(2, units="ns")
        dut.start.value = 1
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        dut.start.value = 0
        while not int(dut.done.value):
            await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        ct = int(v["ciphertext_tag"][:256], 16)
        tg = int(v["ciphertext_tag"][256:], 16)
        got_ct = int(dut.ciphertext_out.value)
        got_tag = int(dut.tag.value)
        assert got_ct == ct, f"index {v['index']} ct mismatch"
        assert got_tag == tg, f"index {v['index']} tag mismatch"
        dut._log.info(f"index {v['index']} ok")
