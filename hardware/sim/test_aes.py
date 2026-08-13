import json
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "vectors", "generated")
VECTORS = os.path.join(VECDIR, "aes.json")


@cocotb.test
async def test_aes_vectors(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.key.value = 0
    dut.block_in.value = 0
    await Timer(25, units="ns")
    dut.rst_n.value = 1
    await Timer(27, units="ns")
    with open(VECTORS) as f:
        vecs = json.load(f)
    for v in vecs:
        dut.key.value = int.from_bytes(bytes.fromhex(v["key"]), "big")
        dut.block_in.value = int.from_bytes(bytes.fromhex(v["block"]), "big")
        await Timer(2, units="ns")
        dut.start.value = 1
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        dut.start.value = 0
        while not dut.done.value:
            await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        got = int(dut.block_out.value).to_bytes(16, "big").hex()
        assert got == v["ciphertext"], f"idx={v['index']} got={got} exp={v['ciphertext']}"
