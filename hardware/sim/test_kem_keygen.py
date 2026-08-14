import json
import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "vectors", "generated")
VECTORS = os.path.join(VECDIR, "kem_keygen_mid.json")


@cocotb.test()
async def test_kem_keygen_vectors(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await Timer(25, units="ns")
    dut.rst_n.value = 0
    await Timer(2, units="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await Timer(2, units="ns")

    with open(VECTORS) as f:
        vecs = json.load(f)

    for v in vecs:
        d = int.from_bytes(bytes.fromhex(v["d"]), "big")
        z = int.from_bytes(bytes.fromhex(v["z"]), "big")
        want_ek = bytes.fromhex(v["ek"])
        want_dk = bytes.fromhex(v["dk"])

        dut.d.value = d
        dut.z.value = z
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0

        while not dut.done.value:
            await RisingEdge(dut.clk)
        await Timer(1, units="ns")

        got_ek = bytes(int(dut.ek_byte[k].value) for k in range(1184))
        got_dk = bytes(int(dut.dk_byte[k].value) for k in range(2400))
        assert got_ek == want_ek, f"idx={v['index']} ek mismatch first {next((i for i,(a,b) in enumerate(zip(got_ek,want_ek)) if a!=b), None)}"
        assert got_dk == want_dk, f"idx={v['index']} dk mismatch first {next((i for i,(a,b) in enumerate(zip(got_dk,want_dk)) if a!=b), None)}"
    dut._log.info(f"kem_keygen {len(vecs)} vectors PASS")
