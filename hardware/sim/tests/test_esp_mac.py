import os
import json
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer

VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "..", "vectors", "generated")
VECTORS = os.path.join(VECDIR, "esp.json")

SRC_MAC = bytes.fromhex("020000000101")
DST_MAC = bytes.fromhex("020000000102")
SRC_IP = bytes.fromhex("0a000001")
DST_IP = bytes.fromhex("0a000002")
SRC_PORT = 4500
DST_PORT = 4500


def ip_checksum(hdr: bytes) -> int:
    s = 0
    for i in range(0, len(hdr), 2):
        s += (hdr[i] << 8) | hdr[i + 1]
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return (~s) & 0xFFFF


def udp_checksum(src_ip, dst_ip, udp_pkt: bytes) -> int:
    udp_len = len(udp_pkt)
    pseudo = src_ip + dst_ip + bytes([0, 17]) + udp_len.to_bytes(2, "big")
    buf = pseudo + udp_pkt
    if len(buf) % 2:
        buf += b"\x00"
    s = 0
    for i in range(0, len(buf), 2):
        s += (buf[i] << 8) | buf[i + 1]
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return (~s) & 0xFFFF


def build_frame(vec, ct_tag):
    spi = bytes.fromhex(vec["spi"])
    seq = bytes.fromhex(vec["seq"])
    iv = bytes.fromhex(vec["iv"])
    pt = bytes.fromhex(vec["plaintext"])
    pt_len = len(pt)
    ct = ct_tag[:pt_len]
    tag = ct_tag[pt_len:]
    return spi + seq + iv + ct + b"\x00\x04" + tag


def build_expected(esp_payload: bytes):
    udp_len = 8 + len(esp_payload)
    total_len = 20 + udp_len
    udp_pkt = bytearray()
    udp_pkt += SRC_PORT.to_bytes(2, "big")
    udp_pkt += DST_PORT.to_bytes(2, "big")
    udp_pkt += udp_len.to_bytes(2, "big")
    udp_pkt += b"\x00\x00"
    udp_pkt += esp_payload
    u_csum = udp_checksum(SRC_IP, DST_IP, bytes(udp_pkt))
    udp_pkt[6:8] = u_csum.to_bytes(2, "big")
    ip_pkt = bytearray()
    ip_pkt += bytes([0x45, 0x00])
    ip_pkt += total_len.to_bytes(2, "big")
    ip_pkt += b"\x00\x00"
    ip_pkt += bytes([0x40, 0x00])
    ip_pkt += bytes([0x40, 17])
    ip_pkt += b"\x00\x00"
    ip_pkt += SRC_IP + DST_IP
    i_csum = ip_checksum(bytes(ip_pkt))
    ip_pkt[10:12] = i_csum.to_bytes(2, "big")
    return DST_MAC + SRC_MAC + bytes([0x08, 0x00]) + bytes(ip_pkt) + bytes(udp_pkt)


async def reset_dut(dut):
    dut.rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(5):
        await RisingEdge(dut.clk)
    await Timer(1, units="ns")


def set_cfg(dut):
    dut.cfg_src_mac.value = int.from_bytes(SRC_MAC, "big")
    dut.cfg_dst_mac.value = int.from_bytes(DST_MAC, "big")
    dut.cfg_src_ip.value = int.from_bytes(SRC_IP, "big")
    dut.cfg_dst_ip.value = int.from_bytes(DST_IP, "big")
    dut.cfg_src_port.value = SRC_PORT
    dut.cfg_dst_port.value = DST_PORT


async def drive_esp(dut, v):
    pt = bytes.fromhex(v["plaintext"])
    dut.key.value = int(v["key"], 16)
    dut.spi.value = int(v["spi"], 16)
    dut.seq.value = int(v["seq"], 16)
    dut.iv.value = int(v["iv"], 16)
    dut.plaintext_len.value = len(pt)
    dut.plaintext_in.value = int.from_bytes(pt.ljust(255, b"\x00"), "big") << 8
    for _ in range(10000):
        await RisingEdge(dut.clk)
        if int(dut.busy.value) == 0:
            break
    dut.start.value = 1
    for _ in range(10):
        await RisingEdge(dut.clk)
        if int(dut.busy.value) == 1:
            break
    dut.start.value = 0
    for _ in range(200000):
        await RisingEdge(dut.clk)
        if int(dut.done.value) == 1:
            break


def gmii_ref(dut):
    mm = dut.u_mac.eth_mac_1g_rgmii_inst.eth_mac_1g_inst
    return mm


async def gmii_collect(dut, max_cyc):
    mm = gmii_ref(dut)
    out = bytearray()
    en = bytearray()
    for _ in range(max_cyc):
        await RisingEdge(dut.gtx_clk)
        out.append(int(mm.gmii_txd.value))
        en.append(int(mm.gmii_tx_en.value))
    return bytes(out), en


@cocotb.test()
async def test_esp_mac_frames(dut):
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
    dut.start.value = 0
    dut.plaintext_len.value = 0
    dut.plaintext_in.value = 0
    await reset_dut(dut)
    set_cfg(dut)
    await Timer(100, units="ns")

    with open(VECTORS) as f:
        vecs = json.load(f)
    nvec = min(4, len(vecs))
    mm = gmii_ref(dut)
    for vi in range(nvec):
        v = vecs[vi]
        esp_frame = bytes.fromhex(v["frame"])
        exp_payload = build_expected(esp_frame)
        body_len = len(exp_payload)
        await drive_esp(dut, v)
        dut._log.info(f"vec {vi} esp done, collecting GMII frame")
        data = bytearray()
        idle_run = 0
        guard = 0
        collected = bytearray()
        while guard < 4000:
            guard += 1
            await RisingEdge(dut.gtx_clk)
            en = int(mm.gmii_tx_en.value)
            if en:
                collected.append(int(mm.gmii_txd.value))
                idle_run = 0
            else:
                idle_run += 1
            if collected and idle_run >= 12:
                break
        data = bytes(collected)
        dut._log.info(f"  collected={len(data)}B first={data[:12].hex()} last={data[-8:].hex()}")
        body_start = None
        for i in range(len(data) - 8):
            if data[i:i+7] == b"\x55"*7 and data[i+7] == 0xD5:
                body_start = i + 8
                break
        if body_start is None:
            for i in range(len(data) - 1):
                if data[i] == 0xD5 and i + 1 < len(data) and data[i+1] == 0x02:
                    body_start = i + 1
                    break
        if body_start is None:
            dut._log.error(f"vec {vi} preamble/SFD not found; collected={data[:40].hex()}")
            assert False, f"vec {vi} no SFD"
        got_frame = bytes(data[body_start:body_start + body_len])
        if got_frame != exp_payload:
            dut._log.error(f"vec {vi} frame MISMATCH (body_len={body_len})")
            for i in range(min(len(got_frame), len(exp_payload))):
                if got_frame[i] != exp_payload[i]:
                    dut._log.error(f"  first diff byte {i}: got={got_frame[i]:02x} exp={exp_payload[i]:02x}")
                    break
            dut._log.error(f"  got_body={got_frame[:20].hex()}")
            dut._log.error(f"  exp_body={exp_payload[:20].hex()}")
            assert False, f"vec {vi} frame mismatch"
        fcs = bytes(data[body_start + body_len:body_start + body_len + 4])
        assert len(fcs) == 4 and any(fcs), f"vec {vi} FCS missing"
        dut._log.info(f"vec {vi} OK body_len={body_len} fcs={fcs.hex()}")
