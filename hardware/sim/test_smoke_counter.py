import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge


@cocotb.test
async def test_count(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst_n.value = 0
    dut.incr.value = 0
    await Timer(30, units="ns")
    dut.rst_n.value = 1
    await Timer(30, units="ns")
    dut.incr.value = 1
    for _ in range(5):
        await RisingEdge(dut.clk)
    assert dut.count.value == 5, f"count={dut.count.value}"
