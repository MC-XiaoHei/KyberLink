import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
from tb_top import spi_read, spi_write

CLK_NS = 20.0

CTRL_ENABLE = 0x1
CTRL_LOOPBACK = 0x2
CTRL_CLEAR = 0x4

R_STATUS = 0x04
R_LAN_TX = 0x08
R_LAN_GOOD = 0x0C
R_LAN_BAD = 0x10
R_LAN_DIFF = 0x14
R_LAN_SEQ_TX = 0x18
R_WAN_TX = 0x20
R_WAN_GOOD = 0x24
R_WAN_BAD = 0x28
R_WAN_DIFF = 0x2C
R_WAN_SEQ_RX = 0x34

FAULT_BITS = 0x18


async def boot(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_NS, "ns").start())
    dut.rst_n.value = 0
    dut.spi_sck.value = 0
    dut.spi_mosi.value = 0
    dut.spi_csn.value = 1
    dut.corrupt.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 4)


@cocotb.test()
async def loopback_counts_without_fault(dut):
    await boot(dut)
    await spi_write(dut, 0x00, CTRL_ENABLE | CTRL_LOOPBACK)
    await ClockCycles(dut.clk, 2000)
    status = await spi_read(dut, R_STATUS)
    assert status & 0x3 == 0x3, f"status {status:#x}"
    assert status & FAULT_BITS == 0, f"fault on loopback {status:#x}"
    tx = await spi_read(dut, R_LAN_TX)
    good = await spi_read(dut, R_LAN_GOOD)
    bad = await spi_read(dut, R_LAN_BAD)
    diff = await spi_read(dut, R_LAN_DIFF)
    assert tx > 0 and good > 0, f"tx {tx} good {good}"
    assert bad == 0 and diff == 0, f"bad {bad} diff {diff}"
    print(f"loopback tx {tx} good {good} PASS", flush=True)


@cocotb.test()
async def clear_zeroes_counters(dut):
    await boot(dut)
    await spi_write(dut, 0x00, CTRL_ENABLE | CTRL_LOOPBACK)
    await ClockCycles(dut.clk, 1000)
    assert await spi_read(dut, R_LAN_TX) > 0
    await spi_write(dut, 0x00, CTRL_CLEAR)
    await ClockCycles(dut.clk, 8)
    for addr in (R_LAN_TX, R_LAN_GOOD, R_LAN_BAD, R_LAN_DIFF, R_WAN_TX, R_WAN_GOOD):
        got = await spi_read(dut, addr)
        assert got == 0, f"{addr:#x} = {got}"
    status = await spi_read(dut, R_STATUS)
    assert status & 0x3 == 0, f"still running {status:#x}"
    print("clear PASS", flush=True)


@cocotb.test()
async def cable_roundtrip_no_fault(dut):
    await boot(dut)
    await spi_write(dut, 0x00, CTRL_ENABLE)
    await ClockCycles(dut.clk, 2000)
    wan_good = await spi_read(dut, R_WAN_GOOD)
    wan_bad = await spi_read(dut, R_WAN_BAD)
    wan_diff = await spi_read(dut, R_WAN_DIFF)
    lan_good = await spi_read(dut, R_LAN_GOOD)
    lan_bad = await spi_read(dut, R_LAN_BAD)
    assert wan_good > 0 and lan_good > 0, f"wan {wan_good} lan {lan_good}"
    assert wan_bad == 0 and wan_diff == 0, f"wan bad {wan_bad} diff {wan_diff}"
    assert lan_bad == 0, f"lan bad {lan_bad}"
    status = await spi_read(dut, R_STATUS)
    assert status & FAULT_BITS == 0, f"fault {status:#x}"
    print(f"cable wan_good {wan_good} lan_good {lan_good} PASS", flush=True)


@cocotb.test()
async def sequence_advances(dut):
    await boot(dut)
    await spi_write(dut, 0x00, CTRL_ENABLE)
    await ClockCycles(dut.clk, 2000)
    wan_seq = await spi_read(dut, R_WAN_SEQ_RX)
    lan_seq = await spi_read(dut, R_LAN_SEQ_TX)
    assert wan_seq > 0, f"wan seq {wan_seq}"
    assert wan_seq <= lan_seq + 4, f"wan seq {wan_seq} beyond lan tx {lan_seq}"
    print(f"seq wan_rx {wan_seq} lan_tx {lan_seq} PASS", flush=True)


@cocotb.test()
async def corruption_is_flagged(dut):
    await boot(dut)
    await spi_write(dut, 0x00, CTRL_ENABLE)
    dut.corrupt.value = 1
    await ClockCycles(dut.clk, 2000)
    dut.corrupt.value = 0
    wan_bad = await spi_read(dut, R_WAN_BAD)
    wan_diff = await spi_read(dut, R_WAN_DIFF)
    assert wan_bad > 0, f"bad {wan_bad}"
    assert wan_diff > 0, f"diff {wan_diff}"
    status = await spi_read(dut, R_STATUS)
    assert status & 0x10 != 0, f"fault bit clear {status:#x}"
    print(f"corruption bad {wan_bad} diff {wan_diff} PASS", flush=True)
