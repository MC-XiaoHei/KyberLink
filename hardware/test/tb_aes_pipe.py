import json
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

_VD = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "vectors", "generated", "aes.json"), encoding="utf-8"))
VECTORS = [(int(v["key"], 16), int(v["block"], 16), int(v["ciphertext"], 16)) for v in _VD["kat"]]


async def run_block(dut, key, pt):
    dut.key.value = key
    dut.block_in.value = pt
    dut.start.value = 1
    dut.key_load.value = 1
    await ClockCycles(dut.clk, 2)
    dut.start.value = 0
    for _ in range(200):
        if int(dut.load_rdy.value):
            dut.blk_valid.value = 1
            await ClockCycles(dut.clk, 2)
            dut.blk_valid.value = 0
            break
        await ClockCycles(dut.clk, 1)
    else:
        raise AssertionError("load timeout")
    for _ in range(200):
        if int(dut.done.value):
            return int(dut.block_out.value)
        await ClockCycles(dut.clk, 1)
    raise AssertionError("done timeout")


@cocotb.test()
async def aes_keyexp(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    dut.key.value = 0
    dut.block_in.value = 0
    dut.blk_valid.value = 0
    dut.start.value = 0
    dut.key_load.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    key, pt, ct = VECTORS[0]
    out = await run_block(dut, key, pt)
    assert out == ct, f"keyexp got={out:032x} want={ct:032x}"


@cocotb.test()
async def aes_rekey(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    dut.key.value = 0
    dut.block_in.value = 0
    dut.blk_valid.value = 0
    dut.start.value = 0
    dut.key_load.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    key1, pt1, ct1 = VECTORS[1]
    out = await run_block(dut, key1, pt1)
    assert out == ct1
    key2, pt2, ct2 = VECTORS[0]
    out = await run_block(dut, key2, pt2)
    assert out == ct2


@cocotb.test()
async def aes_kat(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    dut.key.value = 0
    dut.block_in.value = 0
    dut.blk_valid.value = 0
    dut.start.value = 0
    dut.key_load.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    for key, pt, ct in VECTORS:
        out = await run_block(dut, key, pt)
        assert out == ct, f"key={key:064x} got={out:032x} want={ct:032x}"
