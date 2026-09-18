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

    data = bytes((i * 13 + 7) & 0xFF for i in range(2000))
    await spi_write(dut, 0x3C, len(data))
    for i in range(0, len(data), 4):
        chunk = data[i:i + 4]
        w = int.from_bytes(chunk + b"\x00" * (4 - len(chunk)), "big")
        await spi_write(dut, 0x40, w)
    await spi_write(dut, 0x00, 1 << 1)

    got = bytearray()
    last_seen = 0
    for cyc in range(6000):
        if int(dut.hsk_tx_valid.value):
            w = int(dut.hsk_tx_data.value)
            got += w.to_bytes(4, "big")
            if int(dut.hsk_tx_last.value):
                last_seen = 1
        await ClockCycles(dut.clk, 1)
    assert len(got) == 2000, f"txbig len {len(got)}"
    assert got == data, f"txbig content {got[:8].hex()}"
    assert last_seen, "txbig last"
    print(f"TXBIG ok len={len(got)} head={got[:16].hex()} tail={got[-16:].hex()}", flush=True)


@cocotb.test()
async def spi_tx_fifo_overflow(dut):
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

    words = 600
    declared = words * 4
    await spi_write(dut, 0x3C, declared)
    pat = [((w * 7) & 0xFFFFFFFF) for w in range(words)]
    for w in pat:
        await spi_write(dut, 0x40, w)

    await spi_write(dut, 0x00, 1 << 1)
    got = []
    for cyc in range(8000):
        if int(dut.hsk_tx_valid.value):
            got.append(int(dut.hsk_tx_data.value))
            if int(dut.hsk_tx_last.value):
                break
        await ClockCycles(dut.clk, 1)
    assert len(got) > 0, "overflow no out"
    assert got == pat[:512], f"overflow got {len(got)} words"
    st = await spi_read(dut, 0x50)
    assert st & 0x20, f"overflow flag {st:08x}"
    print(f"tx overflow ok {len(got)} words", flush=True)
