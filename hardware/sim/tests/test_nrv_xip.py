import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

CLK_PERIOD_NS = 20
BIT_NS = 52083  # 19200 baud

FW_BIN = os.path.join(os.path.dirname(__file__), "..", "..", "..", "software", "build", "firmware.bin")


@cocotb.test()
async def test_xip_firmware(dut):
    """XIP: boot IMEM stub -> SMC -> flash firmware (Rust, no_std).
    Firmware sets GPIO=0xAA and prints 'XIP firmware OK' over UART0."""
    # load firmware into flash model memory (u_flash.mem)
    with open(FW_BIN, "rb") as f:
        fw = f.read()
    for i, b in enumerate(fw):
        dut.u_flash.mem[i].value = b
    dut._log.info("firmware loaded: %d bytes", len(fw))

    clock = Clock(dut.clk_i, CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())
    dut.rstn_i.value = 0
    dut.uart0_rxd_i.value = 1
    await Timer(100, unit="ns")
    dut.rstn_i.value = 1

    # firmware GPIO marker
    deadline = 0
    while int(dut.gpio_o.value) != 0xAA:
        await RisingEdge(dut.clk_i)
        deadline += 1
        if deadline > 500000:
            raise AssertionError("firmware GPIO never 0xAA, got 0x%02x" % int(dut.gpio_o.value))
    dut._log.info("firmware running: GPIO=0xAA")

    # decode UART 'X' (0x58) at 19200
    deadline = 0
    while int(dut.uart0_txd_o.value) == 1:
        await RisingEdge(dut.clk_i)
        deadline += 1
        if deadline > 500000:
            raise AssertionError("no UART output from firmware")
    await Timer(BIT_NS // 2, unit="ns")
    byte = 0
    for i in range(8):
        await Timer(BIT_NS, unit="ns")
        byte |= int(dut.uart0_txd_o.value) << i
    dut._log.info("UART first byte = 0x%02x ('%c')", byte, chr(byte) if 32 <= byte < 127 else '?')
    assert byte == 0x58, "expected 'X' (0x58), got 0x%02x" % byte
    dut._log.info("XIP firmware UART OK: sent 'X'")
