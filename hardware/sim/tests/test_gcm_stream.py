import json
import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from Crypto.Cipher import AES

VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "..", "vectors", "generated")
VECTORS = os.path.join(VECDIR, "esp.json")


def blocks(data):
    data = data + b"\x00" * (-len(data) % 16)
    return [int.from_bytes(data[i:i + 16], "big") for i in range(0, len(data), 16)]


async def reset_dut(dut):
    dut.rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(5):
        await RisingEdge(dut.clk)
    await Timer(1, unit="ns")


async def run_crypto(dut, key, nonce, aad, pt_len, decrypt, tag_in, blks):
    dut.key.value = int.from_bytes(key, "big")
    dut.nonce.value = int.from_bytes(nonce, "big")
    dut.aad.value = int.from_bytes(aad, "big") << 64
    dut.aad_len.value = 8
    dut.pt_len.value = pt_len
    dut.decrypt.value = 1 if decrypt else 0
    dut.tag_in.value = int.from_bytes(tag_in, "big") if decrypt else 0
    dut.start.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk)
    dut.start.value = 0

    bi = 0
    out = b""
    prev_r = 0
    dut.pt_valid.value = 1 if blks else 0
    dut.pt_data.value = blks[0] if blks else 0
    dut._log.info(f"RUN pt_valid_set={1 if blks else 0} blks={len(blks) if blks else 0}")
    for _ in range(300000):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        if _ < 20:
            dut._log.info(f"LOOP{_} pv={int(dut.pt_valid.value)} pr={int(dut.pt_ready.value)} bi={bi} prev={prev_r}")
        if int(dut.ct_valid.value) and int(dut.ct_ready.value):
            out += int(dut.ct_data.value).to_bytes(16, "big")
        cur_r = int(dut.pt_ready.value)
        if int(dut.pt_valid.value) and prev_r:
            bi += 1
            if bi < len(blks):
                dut.pt_data.value = blks[bi]
            else:
                dut.pt_valid.value = 0
        prev_r = cur_r
        if int(dut.tag_valid.value):
            tag = int(dut.tag.value).to_bytes(16, "big")
            tag_ok = int(dut.tag_ok.value)
            return out[:pt_len], tag, tag_ok
    assert False, "crypto timeout"


@cocotb.test()
async def test_gcm_stream_roundtrip(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.pt_valid.value = 0
    dut.ct_ready.value = 1
    dut.start.value = 0
    dut.decrypt.value = 0
    dut.tag_in.value = 0
    await reset_dut(dut)

    with open(VECTORS) as f:
        vecs = json.load(f)
    lens = [0, 1, 15, 16, 17, 31, 255, 256, 1000, 1500]
    for li, L in enumerate(lens):
        v = vecs[0]
        key = bytes.fromhex(v["key"])
        iv = bytes.fromhex(v["iv"])
        spi = bytes.fromhex(v["spi"])
        seq = bytes.fromhex(v["seq"])
        aad = spi + seq
        pt = bytes((i * 7 + li) % 256 for i in range(L))
        aes = AES.new(key, AES.MODE_GCM, nonce=iv)
        aes.update(aad)
        ct_tag = aes.encrypt(pt) + aes.digest()
        exp_ct = ct_tag[:-16]
        exp_tag = ct_tag[-16:]
        ct, tag, _ = await run_crypto(dut, key, iv, aad, L, False, b"", blocks(pt))
        if L == 17 or L == 1:
            dut._log.info(f"DEBUG{li} exp_ct={exp_ct.hex()} got_ct={ct.hex()}")
            dut._log.info(f"DEBUG{li} exp_tag={exp_tag.hex()} got_tag={tag.hex()}")
        dut._log.info(f"len {li} L={L} enc ct={ct == exp_ct} tag={tag == exp_tag}")
        assert ct == exp_ct and tag == exp_tag, f"len {li} enc mismatch"
        pt2, _, ok = await run_crypto(dut, key, iv, aad, L, True, tag, blocks(ct))
        dut._log.info(f"len {li} dec pt={pt2 == pt} tag_ok={ok}")
        assert pt2 == pt and ok == 1, f"len {li} dec mismatch"
        dut._log.info(f"len {li} OK")
