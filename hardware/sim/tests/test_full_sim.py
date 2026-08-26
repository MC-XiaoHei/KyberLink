import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

CLK_PERIOD_NS = 20
FW_BIN = os.path.join(os.path.dirname(__file__), "..", "..", "..", "software", "build", "firmware_echo.bin")

SRC_MAC = bytes.fromhex("020000000101")
DST_MAC = bytes.fromhex("020000000102")
SRC_IP = bytes.fromhex("0a000001")
DST_IP = bytes.fromhex("0a000002")


def build_udp(dst_mac, src_mac, payload):
    udp = (4501).to_bytes(2, "big") + (4501).to_bytes(2, "big") + \
          (8 + len(payload)).to_bytes(2, "big") + b"\x00\x00" + payload
    total = 20 + len(udp)
    ip = bytearray(bytes([0x45, 0x00]) + total.to_bytes(2, "big") + b"\x00\x00" +
                   bytes([0x40, 0x00, 0x40, 0x11]) + b"\x00\x00" + SRC_IP + DST_IP)
    s = 0
    for i in range(0, len(ip), 2):
        s += (ip[i] << 8) | ip[i + 1]
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    ip[10:12] = ((~s) & 0xFFFF).to_bytes(2, "big")
    return dst_mac + src_mac + bytes([0x08, 0x00]) + bytes(ip) + udp


def crc32(data):
    crc = 0xFFFFFFFF
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ (0xEDB88320 if crc & 1 else 0)
    return (~crc) & 0xFFFFFFFF


async def load_fw(dut):
    with open(FW_BIN, "rb") as f:
        fw = f.read()
    for i, b in enumerate(fw):
        dut.u_flash.mem[i].value = b
    return len(fw)


async def uart_drain(dut):
    BIT_NS = 52083
    while True:
        while int(dut.uart0_txd.value) == 1:
            await RisingEdge(dut.clk)
        await Timer(BIT_NS // 2, unit="ns")
        byte = 0
        for i in range(8):
            await Timer(BIT_NS, unit="ns")
            byte |= int(dut.uart0_txd.value) << i
        await Timer(BIT_NS, unit="ns")
        if byte == 0:
            break


async def boot(dut):
    clock = Clock(dut.clk, CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())
    cocotb.start_soon(uart_drain(dut))
    dut.rstn.value = 0
    dut.uart0_rxd.value = 1
    await Timer(100, unit="ns")
    dut.rstn.value = 1
    deadline = 0
    while int(dut.u_nrv.gpio_o.value) != 0xAA:
        await RisingEdge(dut.clk)
        deadline += 1
        if deadline > 500000:
            raise AssertionError("firmware GPIO never 0xAA")
    dut._log.info("firmware running")


async def rgmii_drive(dut, rxd, ctl, clk_sig, frame):
    await RisingEdge(clk_sig)
    rxd.value = frame[0] & 0xF
    ctl.value = 1
    prev = 0.0
    for i, b in enumerate(frame):
        if i > 0:
            hi_t = 8.0 * i
            await Timer(hi_t - prev, unit="ns")
            rxd.value = b & 0xF
            ctl.value = 1
            prev = hi_t
        lo_t = 8.0 * i + 4.0
        await Timer(lo_t - prev, unit="ns")
        rxd.value = (b >> 4) & 0xF
        prev = lo_t
    await Timer(4.0, unit="ns")
    rxd.value = 0
    ctl.value = 0


@cocotb.test()
async def test_full_system(dut):
    n = await load_fw(dut)
    dut._log.info(f"firmware loaded: {n} bytes")
    await boot(dut)
    dut._log.info("full system OK: XIP firmware running")


@cocotb.test(skip="90KB config fw XIP too slow in sim; verify on HW")
async def test_serial_config(dut):
    FW_CFG = os.path.join(os.path.dirname(__file__), "..", "..", "..", "software", "build", "firmware.bin")
    with open(FW_CFG, "rb") as f:
        fw = f.read()
    for i, b in enumerate(fw):
        dut.u_flash.mem[i].value = b
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    dut.rstn.value = 0
    dut.uart0_rxd.value = 1
    await Timer(100, unit="ns")
    dut.rstn.value = 1
    deadline = 0
    while int(dut.u_nrv.gpio_o.value) != 0xAA:
        await RisingEdge(dut.clk)
        deadline += 1
        if deadline > 80000000:
            raise AssertionError("firmware GPIO never 0xAA")
    dut._log.info("firmware running")
    fp_hex = "a69fd77e13d7f9244373dcaf7d72001c77a238472b6b34f2bb4cfd000eb2e2b8"
    for ch in fp_hex.encode() + b"\r":
        dut.uart0_rxd.value = 0
        await Timer(52083 // 2, unit="ns")
        for i in range(8):
            dut.uart0_rxd.value = (ch >> i) & 1
            await Timer(52083, unit="ns")
        dut.uart0_rxd.value = 1
        await Timer(52083, unit="ns")
    for ch in b"show\r":
        dut.uart0_rxd.value = 0
        await Timer(52083 // 2, unit="ns")
        for i in range(8):
            dut.uart0_rxd.value = (ch >> i) & 1
            await Timer(52083, unit="ns")
        dut.uart0_rxd.value = 1
        await Timer(52083, unit="ns")
    got = bytearray()
    for _ in range(2000000):
        if int(dut.uart0_txd.value) == 0:
            await Timer(52083 // 2, unit="ns")
            byte = 0
            for i in range(8):
                await Timer(52083, unit="ns")
                byte |= int(dut.uart0_txd.value) << i
            await Timer(52083, unit="ns")
            got.append(byte)
        else:
            await Timer(52083, unit="ns")
        if b"fp ok" in bytes(got):
            break
    dut._log.info(f"serial got: {bytes(got)[:80]}")
    if b"fp ok" not in bytes(got):
        raise AssertionError("fp command not acked")
    if fp_hex.encode() not in bytes(got):
        raise AssertionError("fp not echoed back")
    dut._log.info("serial config OK")


