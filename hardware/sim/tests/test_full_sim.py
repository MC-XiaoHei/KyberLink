import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer

CLK_PERIOD_NS = 20
BIT_NS = 52083  # 19200 baud


async def uart_rx_byte(dut):
    while int(dut.uart0_txd.value) == 1:
        await RisingEdge(dut.clk)
    await Timer(BIT_NS // 2, unit="ns")
    byte = 0
    for i in range(8):
        await Timer(BIT_NS, unit="ns")
        byte |= int(dut.uart0_txd.value) << i
    await Timer(BIT_NS, unit="ns")
    return byte


@cocotb.test()
async def test_full_system(dut):
    clock = Clock(dut.clk, CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    dut.uart0_rxd.value = 1
    await Timer(100, unit="ns")
    dut.rstn.value = 1
    # bootloader (BOOT_MODE_SELECT=0) prints banner over UART
    got = bytearray()
    deadline = 0
    while b"NEORV32" not in bytes(got):
        got.append(await uart_rx_byte(dut))
        deadline += 1
        if deadline > 500:
            raise AssertionError("no bootloader banner, got: %r" % bytes(got[:40]))
    dut._log.info("full system OK: bootloader banner %r", bytes(got[:30]))
