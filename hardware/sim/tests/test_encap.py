import os
import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

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
    eth = DST_MAC + SRC_MAC + bytes([0x08, 0x00]) + bytes(ip_pkt) + bytes(udp_pkt)
    return eth


def set_cfg(dut):
    dut.cfg_src_mac.value = int.from_bytes(SRC_MAC, "big")
    dut.cfg_dst_mac.value = int.from_bytes(DST_MAC, "big")
    dut.cfg_src_ip.value = int.from_bytes(SRC_IP, "big")
    dut.cfg_dst_ip.value = int.from_bytes(DST_IP, "big")
    dut.cfg_src_port.value = SRC_PORT
    dut.cfg_dst_port.value = DST_PORT


async def reset_dut(dut):
    dut.rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(5):
        await RisingEdge(dut.clk)
    await Timer(1, units="ns")


async def feed_esp(dut, data):
    L = len(data)
    for idx in range(L):
        dut.s_tdata.value = data[idx]
        dut.s_tvalid.value = 1
        dut.s_tlast.value = 1 if idx == L - 1 else 0
        await RisingEdge(dut.clk)
    dut.s_tvalid.value = 0
    dut.s_tlast.value = 0


async def recv_eth(dut):
    got = b""
    for _ in range(20000):
        await RisingEdge(dut.clk)
        if int(dut.m_tvalid.value):
            got += bytes([int(dut.m_tdata.value)])
            if int(dut.m_tlast.value):
                return got
    dut._log.error(f"recv timeout got_len={len(got)} last_valid_bytes={[format(b,'02x') for b in got[-8:]]}")
    raise AssertionError("recv timeout")


@cocotb.test()
async def test_encap_random(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.s_tvalid.value = 0
    dut.s_tlast.value = 0
    dut.m_tready.value = 1
    await reset_dut(dut)
    set_cfg(dut)
    await RisingEdge(dut.clk)

    rng = random.Random(1234)
    lengths = [1, 2, 3, 15, 16, 31, 32, 37, 38, 39, 63, 127, 200, 255, 292, 293]
    for _ in range(16):
        lengths.append(rng.randint(1, 293))
    for li, L in enumerate(lengths):
        esp = bytes(rng.randrange(256) for _ in range(L))
        exp = build_expected(esp)
        dut._log.info(f"case {li} esp_len={L} exp_frame={len(exp)}")
        await feed_esp(dut, esp)
        got = await recv_eth(dut)
        if got != exp:
            dut._log.error(f"case {li} (L={L}) MISMATCH len got={len(got)} exp={len(exp)}")
            for i in range(min(len(got), len(exp))):
                if got[i] != exp[i]:
                    dut._log.error(f"  first diff byte {i}: got={got[i]:02x} exp={exp[i]:02x}")
                    break
            assert False, f"case {li} frame mismatch"
        dut._log.info(f"case {li} ok")
    for bi in range(5):
        L = rng.randint(1, 293)
        esp = bytes(rng.randrange(256) for _ in range(L))
        exp = build_expected(esp)
        await feed_esp(dut, esp)
        got = await recv_eth(dut)
        assert got == exp, f"burst {bi} mismatch"
        dut._log.info(f"burst {bi} ok L={L}")
