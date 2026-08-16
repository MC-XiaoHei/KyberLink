import json
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "vectors", "generated")
VECTORS = os.path.join(VECDIR, "hkdf.json")


@cocotb.test()
async def test_hkdf_vectors(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst_n.value = 0
    dut.start.value = 0
    await Timer(25, units="ns")
    dut.rst_n.value = 1
    await Timer(2, units="ns")

    with open(VECTORS) as f:
        vecs = json.load(f)

    for v in vecs:
        h4 = bytes.fromhex(v["h4"])
        ss_i = bytes.fromhex(v["ss_i"])
        ss_r = bytes.fromhex(v["ss_r"])
        spi_i = int(v["spi_i"], 16)
        spi_r = int(v["spi_r"], 16)

        dut.h4_in.value = int.from_bytes(h4, "big")
        dut.ss_i_in.value = int.from_bytes(ss_i, "big")
        dut.ss_r_in.value = int.from_bytes(ss_r, "big")
        dut.spi_i_in.value = spi_i
        dut.spi_r_in.value = spi_r

        dut.start.value = 1
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        dut.start.value = 0

        while int(dut.done.value) != 1:
            await RisingEdge(dut.clk)
        await Timer(1, units="ns")

        got = int(dut.okm.value).to_bytes(96, "big").hex()
        assert got == v["okm"], f"idx={v['index']} got={got} exp={v['okm']}"
