import json
import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer
from cryptography.hazmat.primitives.ciphers.aead import AESGCM


VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "..", "vectors", "generated")

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


def build_eth(payload, src_mac=SRC_MAC, dst_mac=DST_MAC):
    return dst_mac + src_mac + bytes([0x08, 0x00]) + payload


def build_esp_frame(key, iv, spi, seq, plain, aad):
    ct_tag = AESGCM(key).encrypt(iv, plain, aad)
    ct = ct_tag[:-16]
    tag = ct_tag[-16:]
    esp = spi + seq + iv + ct + b"\x00\x04" + tag
    udp_len = 8 + len(esp)
    total_len = 20 + udp_len
    udp = (SRC_PORT.to_bytes(2, "big") + DST_PORT.to_bytes(2, "big") +
           udp_len.to_bytes(2, "big") + b"\x00\x00" + esp)
    ip = bytearray(bytes([0x45, 0x00]) + total_len.to_bytes(2, "big") + b"\x00\x00" +
                   bytes([0x40, 0x00, 0x40, 0x11]) + b"\x00\x00" + SRC_IP + DST_IP)
    s = 0
    for i in range(0, len(ip), 2):
        s += (ip[i] << 8) | ip[i + 1]
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    ip[10:12] = ((~s) & 0xFFFF).to_bytes(2, "big")
    return DST_MAC + SRC_MAC + bytes([0x08, 0x00]) + ip + udp


def mac_ref(dut, name):
    return getattr(dut, name)


async def rgmii_drive(dut, clk_sig, rxd_sig, ctl_sig, gmii_bytes):
    for b in gmii_bytes:
        rxd_sig.value = b & 0xF
        ctl_sig.value = 1
        await RisingEdge(clk_sig)
        rxd_sig.value = (b >> 4) & 0xF
        ctl_sig.value = 1
        await FallingEdge(clk_sig)
    ctl_sig.value = 0
    await RisingEdge(clk_sig)
    ctl_sig.value = 0
    await FallingEdge(clk_sig)


async def tx_collect(dut, tv, td, tl, max_cyc):
    out = bytearray()
    for _ in range(max_cyc):
        await RisingEdge(dut.clk)
        if int(tv.value):
            out.append(int(td.value))
            if int(tl.value):
                break
    return bytes(out)


async def reset_dut(dut):
    dut.rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(5):
        await RisingEdge(dut.clk)
    await Timer(1, units="ns")


@cocotb.test()
async def test_bridge_loopback(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    cocotb.start_soon(Clock(dut.gtx_clk, 8, units="ns").start())
    cocotb.start_soon(Clock(dut.wan_rgmii_rx_clk, 8, units="ns").start())
    cocotb.start_soon(Clock(dut.lan_rgmii_rx_clk, 8, units="ns").start())

    async def _clk90():
        await Timer(2, units="ns")
        while True:
            dut.gtx_clk90.value = 1
            await Timer(4, units="ns")
            dut.gtx_clk90.value = 0
            await Timer(4, units="ns")

    cocotb.start_soon(_clk90())
    dut.wan_rgmii_rxd.value = 0
    dut.wan_rgmii_rx_ctl.value = 0
    dut.lan_rgmii_rxd.value = 0
    dut.lan_rgmii_rx_ctl.value = 0
    await reset_dut(dut)

    with open(os.path.join(VECDIR, "esp.json")) as f:
        v = json.load(f)[0]
    key = bytes.fromhex(v["key"])
    spi = bytes.fromhex(v["spi"])
    iv = bytes.fromhex(v["iv"])
    seq = (0x11223344).to_bytes(4, "big")
    aad = spi + seq

    dut.key.value = int(v["key"], 16)
    dut.cfg_spi.value = int(v["spi"], 16)
    dut.cfg_iv.value = int(v["iv"], 16)
    dut.seq_in.value = int.from_bytes(seq, "big")
    dut.cfg_src_mac.value = int.from_bytes(SRC_MAC, "big")
    dut.cfg_dst_mac.value = int.from_bytes(DST_MAC, "big")
    dut.cfg_src_ip.value = int.from_bytes(SRC_IP, "big")
    dut.cfg_dst_ip.value = int.from_bytes(DST_IP, "big")
    dut.cfg_src_port.value = SRC_PORT
    dut.cfg_dst_port.value = DST_PORT
    await RisingEdge(dut.clk)

    payload = bytes((i * 3 + 1) % 256 for i in range(214))
    lan_frame = build_eth(payload)
    fcs = crc32(lan_frame).to_bytes(4, "little")
    gmii_lan = b"\x55" * 7 + b"\xd5" + lan_frame + fcs

    exp_wan = build_esp_frame(key, iv, spi, seq, lan_frame, aad)
    exp_fcs = crc32(exp_wan).to_bytes(4, "little")
    gmii_wan = b"\x55" * 7 + b"\xd5" + exp_wan + exp_fcs

    dut._log.info(f"lan_frame={len(lan_frame)}B exp_wan={len(exp_wan)}B")
    wm = dut.u_wan_mac
    lm = dut.u_lan_mac
    await rgmii_drive(dut, dut.lan_rgmii_rx_clk, dut.lan_rgmii_rxd,
                      dut.lan_rgmii_rx_ctl, gmii_lan)
    wan_body = await tx_collect(dut, dut.u_enc.m_tvalid, dut.u_enc.m_tdata, dut.u_enc.m_tlast, 40000)
    if wan_body != exp_wan:
        for i in range(min(len(wan_body), len(exp_wan))):
            if wan_body[i] != exp_wan[i]:
                dut._log.error(f'first diff @{i} got={wan_body[i]:02x} exp={exp_wan[i]:02x}')
                dut._log.error(f'got={wan_body[max(0,i-8):i+16].hex()}')
                dut._log.error(f'exp={exp_wan[max(0,i-8):i+16].hex()}')
                break
        dut._log.error(f'len got={len(wan_body)} exp={len(exp_wan)}')
        assert False, "wan enc mismatch"
    dut._log.info("wan enc OK")

    await rgmii_drive(dut, dut.wan_rgmii_rx_clk, dut.wan_rgmii_rxd,
                      dut.wan_rgmii_rx_ctl, gmii_wan)
    lan_body = await tx_collect(dut, dut.u_dec.m_tvalid, dut.u_dec.m_tdata, dut.u_dec.m_tlast, 40000)
    dut._log.info(f"lan tx {len(lan_body)}B")
    await Timer(3000, units="ns")
    assert int(dut.u_dec.tag_ok_r.value) == 1, "dec tag mismatch"
    dut._log.info("dec tag OK")
    assert lan_body is not None, "lan no frame"
    if lan_body != lan_frame:
        dut._log.error(f"LAN MISMATCH got={lan_body[:40].hex()} exp={lan_frame[:40].hex()}")
        assert False, "lan dec mismatch"
    dut._log.info("lan dec OK")
