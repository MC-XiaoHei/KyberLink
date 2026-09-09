import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


async def spi_write(dut, addr, data):
    dut.spi_csn.value = 0
    await ClockCycles(dut.clk, 1)
    word = (addr << 32) | data
    for i in range(39, -1, -1):
        dut.spi_mosi.value = (word >> i) & 1
        await ClockCycles(dut.clk, 2)
        dut.spi_sck.value = 1
        await ClockCycles(dut.clk, 2)
        dut.spi_sck.value = 0
        await ClockCycles(dut.clk, 2)
    dut.spi_csn.value = 1
    await ClockCycles(dut.clk, 2)


async def spi_read(dut, addr):
    dut.spi_csn.value = 0
    await ClockCycles(dut.clk, 1)
    word = (1 << 39) | (addr << 32)
    got = 0
    for i in range(39, -1, -1):
        dut.spi_mosi.value = (word >> i) & 1
        await ClockCycles(dut.clk, 2)
        dut.spi_sck.value = 1
        await ClockCycles(dut.clk, 2)
        if i < 32:
            got = (got << 1) | int(dut.spi_miso.value)
        dut.spi_sck.value = 0
        await ClockCycles(dut.clk, 2)
    dut.spi_csn.value = 1
    await ClockCycles(dut.clk, 2)
    return got


@cocotb.test()
async def spi_tx_big(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    dut.spi_sck.value = 0
    dut.spi_mosi.value = 0
    dut.spi_csn.value = 1
    dut.hsk_rx_wr.value = 0
    dut.hsk_rx_data.value = 0
    dut.hsk_rx_last.value = 0
    dut.hsk_rx_len.value = 0
    dut.hsk_tx_ready.value = 1
    await ClockCycles(dut.clk, 4)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    data = bytes([0x55] * 3168)
    await spi_write(dut, 0x3C, len(data))
    for i in range(0, len(data), 4):
        chunk = data[i:i + 4]
        w = int.from_bytes(chunk + b"\x00" * (4 - len(chunk)), "big")
        await spi_write(dut, 0x40, w)
    await spi_write(dut, 0x00, 1 << 1)

    got = bytearray()
    for cyc in range(4000):
        if int(dut.hsk_tx_valid.value):
            w = int(dut.hsk_tx_data.value)
            got += w.to_bytes(4, "big")
        if cyc % 500 == 0 and got:
            print(f"cyc={cyc} gotlen={len(got)} last={got[-8:].hex()}", flush=True)
        await ClockCycles(dut.clk, 1)
    print(f"TXBIG gotlen={len(got)} head={got[:16].hex()} tail={got[-16:].hex()}", flush=True)
