import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


@cocotb.test()
async def bram_rw(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.waddr.value = 0
    dut.wdata.value = 0
    dut.we.value = 0
    dut.raddr.value = 0
    await ClockCycles(dut.clk, 5)

    dut.waddr.value = 3
    dut.wdata.value = 0x112233445566778899aabbccddeeff00
    dut.we.value = 1
    await ClockCycles(dut.clk, 1)
    dut.we.value = 0
    dut.raddr.value = 3
    await ClockCycles(dut.clk, 2)
    assert int(dut.rdata.value) == 0x112233445566778899aabbccddeeff00, f"read {int(dut.rdata.value):032x}"
    dut.raddr.value = 1
    await ClockCycles(dut.clk, 2)
    assert int(dut.rdata.value) == 0, f"unwritten read {int(dut.rdata.value):032x}"
