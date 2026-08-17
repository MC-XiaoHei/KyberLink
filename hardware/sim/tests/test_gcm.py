import os
import json
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "..", "vectors", "generated")
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
    dut.pt_valid.value = 0
    dut.ct_ready.value = 1
    await reset_dut(dut)
    with open(VECTORS) as f:
        vecs = json.load(f)
    for v in vecs:
        dut.key.value = int(v["key"], 16)
        dut.nonce.value = int(v["nonce"], 16)
        dut.aad.value = int(v["aad"], 16)
        dut.aad_len.value = 16
        dut.pt_len.value = 128
        pt = int(v["plaintext"], 16)
        pt_blocks = [(pt >> (128 * (7 - i))) & ((1 << 128) - 1) for i in range(8)]
        bidx = 0
        hold = False
        ct_bytes = b""
        await Timer(2, units="ns")
        dut.start.value = 1
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        dut.start.value = 0
        while not int(dut.done.value):
            await RisingEdge(dut.clk)
            if hold and int(dut.pt_ready.value):
                hold = False
                bidx += 1
            if not hold and bidx < 8 and int(dut.pt_ready.value):
                dut.pt_data.value = pt_blocks[bidx]
                hold = True
            dut.pt_valid.value = 1 if hold else 0
            if int(dut.ct_valid.value):
                ct_bytes += int(dut.ct_data.value).to_bytes(16, "big")
        await Timer(1, units="ns")
        ct = int(v["ciphertext_tag"][:256], 16)
        tg = int(v["ciphertext_tag"][256:], 16)
        got_ct = int.from_bytes(ct_bytes, "big")
        got_tag = int(dut.tag.value)
        assert bidx == 8, f"index {v['index']} fed {bidx} blocks"
        assert got_ct == ct, f"index {v['index']} ct mismatch"
        assert got_tag == tg, f"index {v['index']} tag mismatch"
        dut._log.info(f"index {v['index']} ok")
