import json
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "..", "vectors", "generated")


@cocotb.test()
async def test_sha3_vectors(dut):
    RATE = int(dut.RATE_BYTES.value)
    with open(os.path.join(VECDIR, "sha3_256.json" if RATE == 136 else "sha3_512.json")) as f:
        vecs = json.load(f)

    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    dut.rst_n.value = 0
    await Timer(25, units="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    for v in vecs:
        msg = bytes.fromhex(v["msg"])
        total = len(msg)
        pos = min(RATE, total)
        dut.len.value = total
        dut.msg.value = int.from_bytes(msg[:pos], "big") << (RATE - pos) * 8
        dut.msg_valid.value = 0
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0
        while not int(dut.done.value):
            await RisingEdge(dut.clk)
            if int(dut.need_msg.value):
                nxt = min(RATE, total - pos)
                chunk = msg[pos:pos + nxt]
                dut.msg.value = int.from_bytes(chunk, "big") << (RATE - nxt) * 8
                dut.msg_valid.value = 1
                await RisingEdge(dut.clk)
                dut.msg_valid.value = 0
                pos += nxt
        await Timer(1, units="ns")
        out = int(dut.out.value).to_bytes(RATE, "big")
        digest = out[:len(v["hash"]) // 2].hex()
        if digest != v["hash"]:
            raise AssertionError(f"index {v['index']} mismatch: got {digest} exp {v['hash']}")
        dut._log.info(f"index {v['index']} ok")
