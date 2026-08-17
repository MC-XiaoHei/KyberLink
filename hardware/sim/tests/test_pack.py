import os
import json
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "..", "vectors", "generated")
VECTORS = os.path.join(VECDIR, "pack.json")


async def reset_dut(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst_n.value = 0
    await Timer(25, units="ns")
    dut.rst_n.value = 1
    await Timer(2, units="ns")


@cocotb.test()
async def test_pack_vectors(dut):
    await reset_dut(dut)
    dut.start.value = 0
    dut.mode.value = 0
    dut.d.value = 0
    dut.coeffs_in.value = 0
    dut.bytes_in.value = 0
    with open(VECTORS) as f:
        vecs = json.load(f)
    for v in vecs:
        d = v["d"]
        if v["mode"] == "encode":
            c = v["coeffs"]
            val = sum(c[k] << (12 * k) for k in range(256))
            dut.coeffs_in.value = val
            dut.bytes_in.value = 0
        else:
            b = bytes.fromhex(v["bytes"])
            dut.bytes_in.value = int.from_bytes(b, "big") << (3072 - 8 * len(b))
            dut.coeffs_in.value = 0
        dut.mode.value = 0 if v["mode"] == "encode" else 1
        dut.d.value = d
        await Timer(2, units="ns")
        dut.start.value = 1
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        dut.start.value = 0
        while not int(dut.done.value):
            await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if v["mode"] == "encode":
            got_bytes = bytes(int(dut.b_byte[k].value) for k in range(384))
            want = bytes.fromhex(v["bytes"])
            got_b = got_bytes[: len(want)]
            assert got_b == want, f"index {v['index']} d={d} bytes mismatch"
        else:
            got_c = [int(dut.co_arr[k].value) for k in range(256)]
            assert got_c == v["coeffs"], f"index {v['index']} d={d} coeffs mismatch"
        dut._log.info(f"index {v['index']} mode={v['mode']} d={d} ok")
