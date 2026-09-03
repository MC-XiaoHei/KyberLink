import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

KEY = int.from_bytes(bytes(range(32)), "big")


async def spi_write(dut, addr, data):
    dut.spi_csn.value = 0
    await ClockCycles(dut.clk, 1)
    word = (addr << 32) | data
    for i in range(39, -1, -1):
        dut.spi_mosi.value = (word >> i) & 1
        dut.spi_sck.value = 1
        await ClockCycles(dut.clk, 1)
        dut.spi_sck.value = 0
        await ClockCycles(dut.clk, 1)
    dut.spi_csn.value = 1
    await ClockCycles(dut.clk, 2)


async def spi_read(dut, addr):
    dut.spi_csn.value = 0
    await ClockCycles(dut.clk, 1)
    word = (1 << 39) | (addr << 32)
    got = 0
    for i in range(39, -1, -1):
        dut.spi_mosi.value = (word >> i) & 1
        dut.spi_sck.value = 1
        await ClockCycles(dut.clk, 1)
        if i < 32:
            got = (got << 1) | int(dut.spi_miso.value)
        dut.spi_sck.value = 0
        await ClockCycles(dut.clk, 1)
    dut.spi_csn.value = 1
    await ClockCycles(dut.clk, 2)
    return got


@cocotb.test()
async def spi_regs_roundtrip(dut):
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
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    spi = 0x11223344
    src_ip = 0xc0a80101
    dst_ip = 0xc0a80102
    src_port = 4500
    dst_port = 4500
    src_mac = 0x001122334455
    dst_mac = 0x66778899aabb
    salt = 0x0102030405060708

    await spi_write(dut, 0x08, spi)
    await spi_write(dut, 0x0C, salt & 0xFFFFFFFF)
    await spi_write(dut, 0x10, salt >> 32)
    await spi_write(dut, 0x14, src_ip)
    await spi_write(dut, 0x18, dst_ip)
    await spi_write(dut, 0x1C, src_port)
    await spi_write(dut, 0x20, dst_port)
    await spi_write(dut, 0x24, src_mac & 0xFFFFFFFF)
    await spi_write(dut, 0x28, src_mac >> 32)
    await spi_write(dut, 0x2C, dst_mac & 0xFFFFFFFF)
    await spi_write(dut, 0x30, dst_mac >> 32)
    for i in range(8):
        await spi_write(dut, 0x44 + i, (KEY >> (224 - 32 * i)) & 0xFFFFFFFF)
    for i in range(8):
        await spi_write(dut, 0x64 + i, (KEY >> (224 - 32 * i)) & 0xFFFFFFFF)

    assert await spi_read(dut, 0x08) == spi
    assert await spi_read(dut, 0x0C) == (salt & 0xFFFFFFFF)
    assert await spi_read(dut, 0x10) == (salt >> 32)
    assert await spi_read(dut, 0x14) == src_ip
    assert await spi_read(dut, 0x18) == dst_ip
    assert await spi_read(dut, 0x1C) == src_port
    assert await spi_read(dut, 0x20) == dst_port
    assert await spi_read(dut, 0x24) == (src_mac & 0xFFFFFFFF)
    assert await spi_read(dut, 0x28) == (src_mac >> 32)
    assert await spi_read(dut, 0x2C) == (dst_mac & 0xFFFFFFFF)
    assert await spi_read(dut, 0x30) == (dst_mac >> 32)

    await spi_write(dut, 0x00, 1)
    await ClockCycles(dut.clk, 3)
    assert int(dut.key_enc.value) == KEY
    assert int(dut.key_dec.value) == KEY
    assert int(dut.cfg_spi.value) == spi
    assert int(dut.cfg_iv.value) == (salt << 32)
    assert int(dut.cfg_src_ip.value) == src_ip
    assert int(dut.cfg_dst_ip.value) == dst_ip
    assert int(dut.cfg_src_port.value) == src_port
    assert int(dut.cfg_dst_port.value) == dst_port
    assert int(dut.cfg_src_mac.value) == src_mac
    assert int(dut.cfg_dst_mac.value) == dst_mac


@cocotb.test()
async def spi_hsk_fifo(dut):
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
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    payload = [0x00112233, 0x44556677, 0x8899aabb, 0xccddeeff]
    for i, w in enumerate(payload):
        dut.hsk_rx_data.value = w
        dut.hsk_rx_wr.value = 1
        dut.hsk_rx_last.value = 1 if i == len(payload) - 1 else 0
        dut.hsk_rx_len.value = len(payload) * 4
        await ClockCycles(dut.clk, 1)
    dut.hsk_rx_wr.value = 0
    dut.hsk_rx_last.value = 0
    await ClockCycles(dut.clk, 2)

    status = await spi_read(dut, 0x04)
    assert status & 1, "hsk_rx_pending not set"
    assert await spi_read(dut, 0x34) == len(payload) * 4
    for i, w in enumerate(payload):
        got = await spi_read(dut, 0x38)
        assert got == w, f"rx word {i}: got {got:08x} exp {w:08x}"
    await ClockCycles(dut.clk, 2)
    status = await spi_read(dut, 0x04)
    assert (status & 1) == 0, "pending not cleared"

    out = []
    dut.hsk_tx_valid.value = 0
    tx_done = []

    async def collect_tx():
        for _ in range(10000):
            if int(dut.hsk_tx_valid.value):
                out.append(int(dut.hsk_tx_data.value))
                if int(dut.hsk_tx_last.value):
                    tx_done.append(True)
                    return
            await ClockCycles(dut.clk, 1)

    await spi_write(dut, 0x3C, len(payload) * 4)
    for w in payload:
        await spi_write(dut, 0x40, w)
    c = cocotb.start_soon(collect_tx())
    await spi_write(dut, 0x00, 2)
    await c
    assert tx_done, "tx never finished"
    assert out == payload, f"tx mismatch {out} vs {payload}"
