import json
import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "..", "vectors", "generated")
VECTORS = os.path.join(VECDIR, "esp.json")

SRC_MAC = bytes.fromhex("020000000101")
DST_MAC = bytes.fromhex("020000000102")
SRC_IP = bytes.fromhex("0a000001")
DST_IP = bytes.fromhex("0a000002")
SRC_PORT = 4500
DST_PORT = 4500


def crc32(data):
    crc = 0xFFFFFFFF
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ (0xEDB88320 if crc & 1 else 0)
    return (~crc) & 0xFFFFFFFF


def build_frame(spi, seq, iv, ct, tag):
    esp = spi + seq + iv + ct + b"\x00\x04" + tag
    udp_len = 8 + len(esp)
    total_len = 20 + udp_len
    udp = (SRC_PORT.to_bytes(2, "big") + DST_PORT.to_bytes(2, "big") +
           udp_len.to_bytes(2, "big") + b"\x00\x00" + esp)
    ip = (bytes([0x45, 0x00]) + total_len.to_bytes(2, "big") + b"\x00\x00" +
          bytes([0x40, 0x00, 0x40, 0x11]) + b"\x00\x00" + SRC_IP + DST_IP)
    return DST_MAC + SRC_MAC + bytes([0x08, 0x00]) + ip + udp


async def rgmii_drive(dut, gmii_bytes):
    for b in gmii_bytes:
        dut.rgmii_rxd.value = b & 0xF
        dut.rgmii_rx_ctl.value = 1
        await RisingEdge(dut.rgmii_rx_clk)
        dut.rgmii_rxd.value = (b >> 4) & 0xF
        dut.rgmii_rx_ctl.value = 1
        await FallingEdge(dut.rgmii_rx_clk)
    dut.rgmii_rx_ctl.value = 0
    await RisingEdge(dut.rgmii_rx_clk)
    dut.rgmii_rx_ctl.value = 0
    await FallingEdge(dut.rgmii_rx_clk)


async def reset_dut(dut):
    dut.rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(5):
        await RisingEdge(dut.clk)
    await Timer(1, units="ns")


def set_cfg(dut):
    dut.cfg_dst_mac.value = int.from_bytes(DST_MAC, "big")
    dut.cfg_dst_port.value = DST_PORT


async def wait_rx(dut):
    for _ in range(100000):
        await RisingEdge(dut.clk)
        if int(dut.rx_plaintext_valid.value):
            return True
    return False


@cocotb.test()
async def test_esp_mac_rx(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    cocotb.start_soon(Clock(dut.gtx_clk, 8, units="ns").start())
    cocotb.start_soon(Clock(dut.rgmii_rx_clk, 8, units="ns").start())

    async def _clk90():
        await Timer(2, units="ns")
        while True:
            dut.gtx_clk90.value = 1
            await Timer(4, units="ns")
            dut.gtx_clk90.value = 0
            await Timer(4, units="ns")

    cocotb.start_soon(_clk90())
    dut.rgmii_rxd.value = 0
    dut.rgmii_rx_ctl.value = 0
    await reset_dut(dut)
    set_cfg(dut)
    await RisingEdge(dut.clk)

    with open(VECTORS) as f:
        vecs = json.load(f)
    nvec = min(4, len(vecs))
    for vi in range(nvec):
        v = vecs[vi]
        key = bytes.fromhex(v["key"])
        iv = bytes.fromhex(v["iv"])
        pt = bytes.fromhex(v["plaintext"])
        spi = bytes.fromhex(v["spi"])
        seq = bytes.fromhex(v["seq"])
        dut.key.value = int(v["key"], 16)
        ct_tag = AESGCM(key).encrypt(iv, pt, spi + seq)
        body = build_frame(spi, seq, iv, ct_tag[:len(pt)], ct_tag[len(pt):])
        fcs = crc32(body).to_bytes(4, "little")
        gmii = b"\x55" * 7 + b"\xd5" + body + fcs
        dut._log.info(f"vec {vi} pt_len={len(pt)} frame_len={len(body)}")
        await rgmii_drive(dut, gmii)
        ok = await wait_rx(dut)
        if not ok:
            assert False, f"vec {vi} rx timeout"
        got_len = int(dut.rx_plaintext_len.value)
        got = int(dut.rx_plaintext_out.value) >> (2048 - got_len * 8)
        tag_ok = int(dut.rx_tag_ok.value)
        exp = int.from_bytes(pt, "big")
        dut._log.info(f"vec {vi} got_len={got_len} tag_ok={tag_ok}")
        if got != exp or tag_ok != 1 or got_len != len(pt):
            dut._log.error(f"vec {vi} MISMATCH len got={got_len} exp={len(pt)} tag_ok={tag_ok}")
            assert False, f"vec {vi} rx mismatch"
        dut._log.info(f"vec {vi} OK")
