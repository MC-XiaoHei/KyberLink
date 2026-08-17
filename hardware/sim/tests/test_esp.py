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
    dut.tx_ready.value = 0
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
        for _ in range(6000):
            await RisingEdge(dut.clk)
            if int(dut.busy.value) == 0 and int(dut.phase.value) == 0:
                break
        dut.start.value = 1
        for _ in range(20):
            await RisingEdge(dut.clk)
            if int(dut.phase.value) != 0:
                break
        dut.start.value = 0

        got = b""
        last_seen = False
        while not last_seen:
            dut.tx_ready.value = 1
            await RisingEdge(dut.clk)
            await Timer(1, units="ns")
            if int(dut.tx_valid.value):
                got += bytes([int(dut.tx_data.value)])
                if int(dut.tx_last.value):
                    last_seen = True

        frame = bytes.fromhex(v["frame"])
        if got != frame:
            dut._log.info(f"index {v['index']} mismatch len got={len(got)} exp={len(frame)}")
            for i in range(min(len(got), len(frame))):
                if got[i] != frame[i]:
                    dut._log.info(
                        f"first diff byte {i}: got={got[i]:02x} exp={frame[i]:02x} "
                    )
                    break
            dut._log.info(f"got[:40]={got[:40].hex()}")
            dut._log.info(f"exp[:40]={frame[:40].hex()}")
        assert got == frame, f"index {v['index']} frame mismatch"
        dut._log.info(f"index {v['index']} ok")
