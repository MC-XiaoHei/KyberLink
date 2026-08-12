import json
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

V = json.load(open(os.path.join(os.path.dirname(__file__), "..", "..", "vectors", "generated", "sample_ntt.json")))


@cocotb.test
async def test_dbg(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.rho.value = 0
    dut.i.value = 0
    dut.j.value = 0
    await Timer(25, units="ns")
    dut.rst_n.value = 1
    await Timer(27, units="ns")
    v = V[0]
    seed = bytes.fromhex(v["seed"])
    dut.rho.value = int.from_bytes(seed[:32], "big")
    dut.i.value = seed[32]
    dut.j.value = seed[33]
    await Timer(2, units="ns")
    dut.start.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    dut.start.value = 0
    with open("/tmp/sntt_dbg.txt", "w") as f:
        pass
    for n in range(400):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        ph = int(dut.phase.value)
        grp = int(dut.grp.value)
        idx = int(dut.idx.value)
        if 160 <= idx <= 172 and ph == 2:
            b0a = int(dut.b0a.value)
            b1a = int(dut.b1a.value)
            d1a = int(dut.d1a.value)
            with open("/tmp/sntt_dbg.txt", "a") as f:
                f.write(f"n={n} grp={grp} idx={idx} b0a={b0a:02x} b1a={b1a:02x} d1a={d1a}\n")
        if int(dut.done.value):
            with open("/tmp/sntt_dbg.txt", "a") as f:
                f.write(f"DONE n={n} idx={idx}\n")
            return
    raise AssertionError("timeout")
