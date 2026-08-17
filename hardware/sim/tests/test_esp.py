import os
import json
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "..", "vectors", "generated")
VECTORS = os.path.join(VECDIR, "esp.json")


async def reset_dut(dut):
    dut.rst_n.value = 0
    await Timer(25, units="ns")
    dut.rst_n.value = 1
    await Timer(27, units="ns")


@cocotb.test()
async def test_esp_vectors(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.start.value = 0
    await reset_dut(dut)
    with open(VECTORS) as f:
        vecs = json.load(f)
    for v in vecs:
        pt_len = v["plaintext_len"]
        pt = bytes.fromhex(v["plaintext"])
        dut.key.value = int(v["key"], 16)
        dut.spi.value = int(v["spi"], 16)
        dut.seq.value = int(v["seq"], 16)
        dut.iv.value = int(v["iv"], 16)
        dut.plaintext_len.value = pt_len
        dut.plaintext_in.value = int.from_bytes(pt.ljust(255, b"\x00"), "big") << 8
        await Timer(2, units="ns")
        dut.start.value = 1
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        dut.start.value = 0
        while not int(dut.done.value):
            await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        got = bytes(int(dut.frame_byte[k].value) for k in range(38 + pt_len))
        frame = bytes.fromhex(v["frame"])
        if got != frame:
            for i in range(min(len(got), len(frame))):
                if got[i] != frame[i]:
                    dut._log.info(
                        f"first diff byte {i}: got={got[i]:02x} exp={frame[i]:02x} "
                        f"ctx got={got[max(0,i-4):i+5].hex()} exp={frame[max(0,i-4):i+5].hex()}"
                    )
                    break
            dut._log.info(f"got[:38]={got[:38].hex()}")
            dut._log.info(f"exp[:38]={frame[:38].hex()}")
        assert got == frame, f"index {v['index']} frame mismatch"
        dut._log.info(f"index {v['index']} ok")
