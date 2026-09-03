import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from tb_bridge import make_frame, KEY, SPI, IV, SRC_IP, DST_IP, SRC_PORT, DST_PORT, SRC_MAC, DST_MAC


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


async def spi_configure(dut):
    salt = IV >> 32
    await spi_write(dut, 0x08, SPI)
    await spi_write(dut, 0x0C, salt & 0xFFFFFFFF)
    await spi_write(dut, 0x10, salt >> 32)
    await spi_write(dut, 0x14, SRC_IP)
    await spi_write(dut, 0x18, DST_IP)
    await spi_write(dut, 0x1C, SRC_PORT)
    await spi_write(dut, 0x20, DST_PORT)
    await spi_write(dut, 0x24, SRC_MAC & 0xFFFFFFFF)
    await spi_write(dut, 0x28, SRC_MAC >> 32)
    await spi_write(dut, 0x2C, DST_MAC & 0xFFFFFFFF)
    await spi_write(dut, 0x30, DST_MAC >> 32)
    for i in range(8):
        await spi_write(dut, 0x44 + i, (KEY >> (224 - 32 * i)) & 0xFFFFFFFF)
    for i in range(8):
        await spi_write(dut, 0x64 + i, (KEY >> (224 - 32 * i)) & 0xFFFFFFFF)
    await spi_write(dut, 0x00, 1)
    await ClockCycles(dut.clk, 3)


@cocotb.test()
async def end_to_end(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    dut.spi_sck.value = 0
    dut.spi_mosi.value = 0
    dut.spi_csn.value = 1
    dut.lan_rxd.value = 0
    dut.lan_rx_dv.value = 0
    dut.lan_rx_last.value = 0
    dut.wan_rxd.value = 0
    dut.wan_rx_dv.value = 0
    dut.wan_rx_last.value = 0
    dut.lan_tx_ready.value = 1
    dut.wan_tx_ready.value = 1
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    await spi_configure(dut)
    await ClockCycles(dut.clk, 10)

    n = 4
    frame = make_frame(100)
    esp_out = bytearray()

    async def enc_drive():
        for j, b in enumerate(frame):
            dut.lan_rxd.value = b
            dut.lan_rx_dv.value = 1
            dut.lan_rx_last.value = 1 if j == len(frame) - 1 else 0
            await ClockCycles(dut.clk, 1)
        dut.lan_rx_dv.value = 0
        dut.lan_rx_last.value = 0
        await ClockCycles(dut.clk, 100)

    async def wan_collect():
        while True:
            if int(dut.wan_tx_en.value):
                esp_out.append(int(dut.wan_txd.value))
                if int(dut.wan_tx_last.value):
                    return
            await ClockCycles(dut.clk, 1)

    c = cocotb.start_soon(wan_collect())
    enc_bytes = []

    async def enc_mon():
        while True:
            if int(dut.u_bridge.m_enc_tvalid.value):
                enc_bytes.append(int(dut.u_bridge.m_enc_tdata.value))
                if int(dut.u_bridge.m_enc_tlast.value):
                    return
            await ClockCycles(dut.clk, 1)

    m = cocotb.start_soon(enc_mon())
    await enc_drive()
    await c
    await m
    esp = bytes(esp_out)
    assert len(esp) == 42 + 20 + 112 + 16, f"esp len {len(esp)}"
    assert esp[:6] == DST_MAC.to_bytes(6, "big"), f"esp dst mac {esp[:6].hex()}"
    assert esp[42:46] == SPI.to_bytes(4, "big"), f"esp spi {esp[42:46].hex()}"

    rsp = bytearray()
    rsp += SRC_MAC.to_bytes(6, "big")
    rsp += DST_MAC.to_bytes(6, "big")
    rsp += esp[12:]

    plain = bytearray()

    async def dec_collect():
        while True:
            if int(dut.lan_tx_en.value):
                plain.append(int(dut.lan_txd.value))
                if int(dut.lan_tx_last.value):
                    return
            await ClockCycles(dut.clk, 1)

    async def rsp_drive():
        for j, b in enumerate(rsp):
            dut.wan_rxd.value = b
            dut.wan_rx_dv.value = 1
            dut.wan_rx_last.value = 1 if j == len(rsp) - 1 else 0
            await ClockCycles(dut.clk, 1)
        dut.wan_rx_dv.value = 0
        dut.wan_rx_last.value = 0
        await ClockCycles(dut.clk, 100)

    c = cocotb.start_soon(dec_collect())
    await rsp_drive()
    await c
    assert bytes(plain) == frame, f"roundtrip: {len(plain)} vs {len(frame)}"


@cocotb.test()
async def hsk_roundtrip(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    dut.spi_sck.value = 0
    dut.spi_mosi.value = 0
    dut.spi_csn.value = 1
    dut.lan_rxd.value = 0
    dut.lan_rx_dv.value = 0
    dut.lan_rx_last.value = 0
    dut.wan_rxd.value = 0
    dut.wan_rx_dv.value = 0
    dut.wan_rx_last.value = 0
    dut.lan_tx_ready.value = 1
    dut.wan_tx_ready.value = 1
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    await spi_configure(dut)
    await ClockCycles(dut.clk, 10)

    hsk = bytes(range(1, 33))
    eth = SRC_MAC.to_bytes(6, "big") + DST_MAC.to_bytes(6, "big") + b"\x08\x00"
    total = 20 + 8 + len(hsk)
    ip = bytes([0x45, 0x00]) + total.to_bytes(2, "big") + b"\x00\x00\x40\x00\x40\x11\x00\x00" + SRC_IP.to_bytes(4, "big") + DST_IP.to_bytes(4, "big")
    udp = (4501).to_bytes(2, "big") + (4501).to_bytes(2, "big") + (8 + len(hsk)).to_bytes(2, "big") + b"\x00\x00"
    frame = eth + ip + udp + hsk

    for j, b in enumerate(frame):
        dut.wan_rxd.value = b
        dut.wan_rx_dv.value = 1
        dut.wan_rx_last.value = 1 if j == len(frame) - 1 else 0
        await ClockCycles(dut.clk, 1)
    dut.wan_rx_dv.value = 0
    dut.wan_rx_last.value = 0
    await ClockCycles(dut.clk, 5)

    status = await spi_read(dut, 0x04)
    assert status & 1, "hsk pending not set"
    assert await spi_read(dut, 0x34) == len(hsk), f"hsk len {await spi_read(dut, 0x34)}"
    words = [int.from_bytes(hsk[i:i+4], "big") for i in range(0, len(hsk), 4)]
    for i, w in enumerate(words):
        got = await spi_read(dut, 0x38)
        assert got == w, f"hsk word {i}: {got:08x} vs {w:08x}"

    payload = bytes(range(100, 116))
    pwords = [int.from_bytes(payload[i:i+4], "big") for i in range(0, 16, 4)]
    await spi_write(dut, 0x3C, len(payload))
    for w in pwords:
        await spi_write(dut, 0x40, w)
    out = bytearray()

    async def collect_tx():
        for _ in range(2000):
            if int(dut.wan_tx_en.value):
                out.append(int(dut.wan_txd.value))
                if int(dut.wan_tx_last.value):
                    return
            await ClockCycles(dut.clk, 1)

    c = cocotb.start_soon(collect_tx())
    await spi_write(dut, 0x00, 2)
    await c
    assert len(out) == 42 + len(payload), f"hsk frame len {len(out)}"
    assert out[36:38] == b"\x11\x95", f"dst port {out[36:38].hex()}"
    assert bytes(out[42:]) == payload, f"hsk payload {bytes(out[42:]).hex()}"
