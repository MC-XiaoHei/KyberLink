import json
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

_VD = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "vectors", "generated", "gcm.json"), encoding="utf-8"))
KEY = int(_VD["key"], 16)
VECTORS = [(bytes.fromhex(v["pt"]), bytes.fromhex(v["ct"]), bytes.fromhex(v["aad"]), int(v["tag"], 16)) for v in _VD["vectors"]]


async def run_gcm(dut, in_bytes, aad_bytes, out_exp, tag_exp, decrypt, key=KEY, key_load=0):
    if isinstance(tag_exp, (bytes, bytearray)):
        tag_exp = int.from_bytes(tag_exp, "big")
    dut.key.value = key
    dut.key_load.value = key_load
    dut.nonce.value = 0
    if aad_bytes:
        dut.aad.value = int.from_bytes(aad_bytes, "big") << (128 - 8 * len(aad_bytes))
    else:
        dut.aad.value = 0
    dut.aad_len.value = len(aad_bytes)
    dut.pt_len.value = len(in_bytes)
    dut.decrypt.value = 1 if decrypt else 0
    dut.ct_ready.value = 1
    dut.pt_valid.value = 0
    dut.start.value = 1
    await ClockCycles(dut.clk, 1)
    dut.start.value = 0
    out = b""
    idx = 0
    tag = None
    for _ in range(1000):
        if int(dut.pt_ready.value) and idx < len(in_bytes):
            blk = in_bytes[idx : idx + 16]
            if len(blk) < 16:
                blk = blk + b"\x00" * (16 - len(blk))
            dut.pt_valid.value = 1
            dut.pt_data.value = int.from_bytes(blk, "big")
            idx += 16
        else:
            dut.pt_valid.value = 0
        if int(dut.ct_valid.value):
            out += int(dut.ct_data.value).to_bytes(16, "big")
        if int(dut.tag_valid.value):
            tag = int(dut.tag.value)
            break
        await ClockCycles(dut.clk, 1)
    else:
        raise AssertionError("gcm timeout")
    if len(out) > len(out_exp):
        out = out[: len(out_exp)]
    assert out == out_exp, f"ct got={out.hex()} want={out_exp.hex()}"
    assert tag == tag_exp, f"tag got={tag:032x} want={tag_exp:032x}"


@cocotb.test()
async def gcm_kat(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    dut.key.value = 0
    dut.nonce.value = 0
    dut.aad.value = 0
    dut.aad_len.value = 0
    dut.pt_len.value = 0
    dut.pt_valid.value = 0
    dut.pt_data.value = 0
    dut.ct_ready.value = 0
    dut.decrypt.value = 0
    dut.start.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    for pt, ct, aad, tag in VECTORS:
        await run_gcm(dut, pt, aad, ct, tag, decrypt=False)


@cocotb.test()
async def gcm_decrypt(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    dut.key.value = 0
    dut.key_load.value = 0
    dut.nonce.value = 0
    dut.aad.value = 0
    dut.aad_len.value = 0
    dut.pt_len.value = 0
    dut.pt_valid.value = 0
    dut.pt_data.value = 0
    dut.ct_ready.value = 0
    dut.decrypt.value = 0
    dut.start.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    pt, ct, aad, tag = VECTORS[1]
    await run_gcm(dut, ct, aad, pt, tag, decrypt=True)


def _ref_gcm(key, nonce, aad, pt):
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    ct = AESGCM(key.to_bytes(32, "big")).encrypt(nonce.to_bytes(12, "big"), pt, aad)
    return ct[:-16], ct[-16:]


@cocotb.test()
async def gcm_rekey(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    dut.key.value = 0
    dut.key_load.value = 0
    dut.nonce.value = 0
    dut.aad.value = 0
    dut.aad_len.value = 0
    dut.pt_len.value = 0
    dut.pt_valid.value = 0
    dut.pt_data.value = 0
    dut.ct_ready.value = 0
    dut.decrypt.value = 0
    dut.start.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    pt = VECTORS[1][0]
    aad = VECTORS[1][2]
    key2 = KEY ^ int.from_bytes(b"\xa5" * 32, "big")
    ct2, tag2 = _ref_gcm(key2, 0, aad, pt)

    await run_gcm(dut, pt, aad, *(_ref_gcm(KEY, 0, aad, pt)), decrypt=False)
    await run_gcm(dut, pt, aad, ct2, tag2, decrypt=False, key=key2, key_load=1)
    await run_gcm(dut, pt, aad, ct2, tag2, decrypt=False, key=key2)
    await run_gcm(dut, pt, aad, *(_ref_gcm(KEY, 0, aad, pt)), decrypt=False, key=KEY, key_load=1)
    await run_gcm(dut, ct2, aad, pt, tag2, decrypt=True, key=key2)
