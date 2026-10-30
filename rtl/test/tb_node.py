import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
from tb_bridge import DST_IP, DST_MAC, DST_PORT, IV, KEY, SPI, SRC_IP, SRC_MAC, SRC_PORT, make_frame


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


async def drain_garp(dut):
    await ClockCycles(dut.clk, 10)

async def start(dut):
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


async def start_drained(dut):
    await start(dut)
    await drain_garp(dut)


@cocotb.test()
async def end_to_end(dut):
    await start_drained(dut)

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
        for _ in range(20000):
            if int(dut.lan_tx_en.value):
                plain.append(int(dut.lan_txd.value))
                if int(dut.lan_tx_last.value):
                    return
            await ClockCycles(dut.clk, 1)
        raise AssertionError("dec no output")

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
async def err_counters(dut):
    await start_drained(dut)

    frame = make_frame(100)
    esp_out = bytearray()

    async def wan_collect():
        while True:
            if int(dut.wan_tx_en.value):
                esp_out.append(int(dut.wan_txd.value))
                if int(dut.wan_tx_last.value):
                    return
            await ClockCycles(dut.clk, 1)

    c = cocotb.start_soon(wan_collect())
    for j, b in enumerate(frame):
        dut.lan_rxd.value = b
        dut.lan_rx_dv.value = 1
        dut.lan_rx_last.value = 1 if j == len(frame) - 1 else 0
        await ClockCycles(dut.clk, 1)
    dut.lan_rx_dv.value = 0
    dut.lan_rx_last.value = 0
    await c
    esp = bytearray(esp_out)

    async def wait_idle():
        for _ in range(200000):
            if int(dut.u_bridge.u_dec.ds.value) == 0 and int(dut.u_bridge.u_dec.dec_pend.value) == 0:
                return
            await ClockCycles(dut.clk, 1)
        raise AssertionError("dec never idle")

    async def drive_esp(data):
        rsp = bytearray()
        rsp += SRC_MAC.to_bytes(6, "big")
        rsp += DST_MAC.to_bytes(6, "big")
        rsp += data
        for j, b in enumerate(rsp):
            dut.wan_rxd.value = b
            dut.wan_rx_dv.value = 1
            dut.wan_rx_last.value = 1 if j == len(rsp) - 1 else 0
            await ClockCycles(dut.clk, 1)
        dut.wan_rx_dv.value = 0
        dut.wan_rx_last.value = 0
        await ClockCycles(dut.clk, 100)

    bad = bytearray(esp[12:])
    bad[-1] ^= 0xFF
    bad[-2] ^= 0xFF
    await drive_esp(bad)
    await wait_idle()
    await drive_esp(bad)
    await wait_idle()
    st = await spi_read(dut, 0x50)
    assert st & 1, f"badtag flag {st:08x}"

    big = bytes((j * 3) & 0xFF for j in range(2200))
    for j, b in enumerate(big):
        dut.lan_rxd.value = b
        dut.lan_rx_dv.value = 1
        dut.lan_rx_last.value = 1 if j == len(big) - 1 else 0
        await ClockCycles(dut.clk, 1)
    dut.lan_rx_dv.value = 0
    dut.lan_rx_last.value = 0
    await ClockCycles(dut.clk, 4000)
    assert (await spi_read(dut, 0x50)) & 8, f"oversize flag {await spi_read(dut, 0x50):08x}"

    plain = bytearray()

    async def dec_collect():
        for _ in range(20000):
            if int(dut.lan_tx_en.value):
                plain.append(int(dut.lan_txd.value))
                if int(dut.lan_tx_last.value):
                    return
            await ClockCycles(dut.clk, 1)
        raise AssertionError("dec no output")

    esp2 = bytearray()

    async def wan_collect2():
        for _ in range(20000):
            if int(dut.wan_tx_en.value):
                esp2.append(int(dut.wan_txd.value))
                if int(dut.wan_tx_last.value):
                    return
            await ClockCycles(dut.clk, 1)
        raise AssertionError("enc no output")

    cw = cocotb.start_soon(wan_collect2())
    for j, b in enumerate(frame):
        dut.lan_rxd.value = b
        dut.lan_rx_dv.value = 1
        dut.lan_rx_last.value = 1 if j == len(frame) - 1 else 0
        await ClockCycles(dut.clk, 1)
    dut.lan_rx_dv.value = 0
    dut.lan_rx_last.value = 0
    await cw
    c = cocotb.start_soon(dec_collect())
    await drive_esp(esp2[12:])
    await c
    assert bytes(plain) == frame, "recover after errors"

    await spi_write(dut, 0x00, 4)
    await ClockCycles(dut.clk, 2)
    assert await spi_read(dut, 0x50) == 0, "soft rst clear flags"

    plain2 = bytearray()

    async def dec_collect2():
        for _ in range(20000):
            if int(dut.lan_tx_en.value):
                plain2.append(int(dut.lan_txd.value))
                if int(dut.lan_tx_last.value):
                    return
            await ClockCycles(dut.clk, 1)
        raise AssertionError("dec no output after soft rst")

    esp3 = bytearray()

    async def wan_collect3():
        for _ in range(20000):
            if int(dut.wan_tx_en.value):
                esp3.append(int(dut.wan_txd.value))
                if int(dut.wan_tx_last.value):
                    return
            await ClockCycles(dut.clk, 1)
        raise AssertionError("enc no output after soft rst")

    cw2 = cocotb.start_soon(wan_collect3())
    for j, b in enumerate(frame):
        dut.lan_rxd.value = b
        dut.lan_rx_dv.value = 1
        dut.lan_rx_last.value = 1 if j == len(frame) - 1 else 0
        await ClockCycles(dut.clk, 1)
    dut.lan_rx_dv.value = 0
    dut.lan_rx_last.value = 0
    await cw2
    c2 = cocotb.start_soon(dec_collect2())
    await drive_esp(esp3[12:])
    await c2
    assert bytes(plain2) == frame, "link works after soft rst"


@cocotb.test()
async def oversize_drop(dut):
    await start_drained(dut)

    cnt = 0

    async def wan_watch():
        nonlocal cnt
        while True:
            if int(dut.wan_tx_en.value):
                cnt += 1
            await ClockCycles(dut.clk, 1)

    cocotb.start_soon(wan_watch())
    big = bytes((j * 3) & 0xFF for j in range(2200))
    for j, b in enumerate(big):
        dut.lan_rxd.value = b
        dut.lan_rx_dv.value = 1
        dut.lan_rx_last.value = 1 if j == len(big) - 1 else 0
        await ClockCycles(dut.clk, 1)
    dut.lan_rx_dv.value = 0
    dut.lan_rx_last.value = 0
    await ClockCycles(dut.clk, 4000)
    assert cnt == 0, f"oversize frame leaked {cnt} bytes to wan"
    print("full oversize drop PASS", flush=True)


@cocotb.test()
async def bad_frame_silent(dut):
    await start_drained(dut)

    bad_mac = (SRC_MAC ^ 0x02).to_bytes(6, "big")
    hsk = b"\x11" * 8
    total = 20 + 8 + len(hsk)
    eth = bad_mac + SRC_MAC.to_bytes(6, "big") + b"\x08\x00"
    ip = bytes([0x45, 0x00]) + total.to_bytes(2, "big") + b"\x00\x00\x40\x00\x40\x11\x00\x00" + SRC_IP.to_bytes(4, "big") + DST_IP.to_bytes(4, "big")
    udp = (4501).to_bytes(2, "big") + (4501).to_bytes(2, "big") + (8 + len(hsk)).to_bytes(2, "big") + b"\x00\x00"
    bad = eth + ip + udp + hsk + b"\x00" * 10

    eth = SRC_MAC.to_bytes(6, "big") + SRC_MAC.to_bytes(6, "big") + b"\x08\x00"
    good = eth + ip + udp + hsk + b"\x00" * 10

    async def wan_send(frame):
        for j, b in enumerate(frame):
            dut.wan_rxd.value = b
            dut.wan_rx_dv.value = 1
            dut.wan_rx_last.value = 1 if j == len(frame) - 1 else 0
            await ClockCycles(dut.clk, 1)
        dut.wan_rx_dv.value = 0
        dut.wan_rx_last.value = 0
        await ClockCycles(dut.clk, 5)

    await wan_send(bad)
    await wan_send(good)
    assert (await spi_read(dut, 0x04)) & 1, "good frame after bad frame lost"
    ln = await spi_read(dut, 0x34) & 0xFFFF
    assert ln == len(hsk), f"hsk len {ln} != {len(hsk)}"
    words = [int.from_bytes(hsk[i:i+4], "big") for i in range(0, len(hsk), 4)]
    for i, w in enumerate(words):
        got = await spi_read(dut, 0x38)
        assert got == w, f"hsk word {i}: {got:08x} vs {w:08x}"
    print("full bad frame silent PASS", flush=True)


@cocotb.test()
async def hsk_roundtrip(dut):
    await start_drained(dut)

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


@cocotb.test()
async def soft_rst_mid_flight(dut):
    await start_drained(dut)

    frame = make_frame(64)
    esp_out = bytearray()

    async def wan_watch():
        for _ in range(30000):
            if int(dut.wan_tx_en.value):
                esp_out.append(int(dut.wan_txd.value))
                if int(dut.wan_tx_last.value):
                    return
            await ClockCycles(dut.clk, 1)
        raise AssertionError("no enc output")

    c = cocotb.start_soon(wan_watch())
    for j, b in enumerate(frame):
        dut.lan_rxd.value = b
        dut.lan_rx_dv.value = 1
        dut.lan_rx_last.value = 1 if j == len(frame) - 1 else 0
        await ClockCycles(dut.clk, 1)
    dut.lan_rx_dv.value = 0
    dut.lan_rx_last.value = 0
    await c
    assert len(esp_out) > 40

    await spi_write(dut, 0x00, 4)
    await ClockCycles(dut.clk, 20)

    esp2 = bytearray()

    async def wan_watch2():
        for _ in range(30000):
            if int(dut.wan_tx_en.value):
                esp2.append(int(dut.wan_txd.value))
                if int(dut.wan_tx_last.value):
                    return
            await ClockCycles(dut.clk, 1)
        raise AssertionError("no enc output after soft rst")

    cw = cocotb.start_soon(wan_watch2())
    for j, b in enumerate(frame):
        dut.lan_rxd.value = b
        dut.lan_rx_dv.value = 1
        dut.lan_rx_last.value = 1 if j == len(frame) - 1 else 0
        await ClockCycles(dut.clk, 1)
    dut.lan_rx_dv.value = 0
    dut.lan_rx_last.value = 0
    await cw

    plain = bytearray()

    async def dec_collect():
        for _ in range(20000):
            if int(dut.lan_tx_en.value):
                plain.append(int(dut.lan_txd.value))
                if int(dut.lan_tx_last.value):
                    return
            await ClockCycles(dut.clk, 1)
        raise AssertionError("dec no output")

    rsp = bytearray()
    rsp += SRC_MAC.to_bytes(6, "big")
    rsp += DST_MAC.to_bytes(6, "big")
    rsp += bytes(esp2[12:])
    dc = cocotb.start_soon(dec_collect())
    for j, b in enumerate(rsp):
        dut.wan_rxd.value = b
        dut.wan_rx_dv.value = 1
        dut.wan_rx_last.value = 1 if j == len(rsp) - 1 else 0
        await ClockCycles(dut.clk, 1)
    dut.wan_rx_dv.value = 0
    dut.wan_rx_last.value = 0
    await dc
    assert bytes(plain) == frame, f"post-soft-rst roundtrip {bytes(plain).hex()}"

    bt, rp = await spi_read(dut, 0x50), await spi_read(dut, 0x58)
    assert bt == 0 and rp == 0, f"stale errors after soft rst badtag={bt} replay={rp}"


@cocotb.test()
async def replay_window_bounds(dut):
    await start_drained(dut)

    e1 = await lan_emit_esp(dut)
    e2 = await lan_emit_esp(dut)
    data = bytes(e1[12:])
    data2 = bytes(e2[12:])
    assert len(data) > 38 and len(data2) > 38, "esp too short"

    async def wait_idle():
        for _ in range(200000):
            if int(dut.u_bridge.u_dec.ds.value) == 0 and int(dut.u_bridge.u_dec.dec_pend.value) == 0:
                return
            await ClockCycles(dut.clk, 1)
        raise AssertionError("dec never idle")

    async def drive_esp(payload):
        rsp = SRC_MAC.to_bytes(6, "big") + DST_MAC.to_bytes(6, "big") + payload
        for j, b in enumerate(rsp):
            dut.wan_rxd.value = b
            dut.wan_rx_dv.value = 1
            dut.wan_rx_last.value = 1 if j == len(rsp) - 1 else 0
            await ClockCycles(dut.clk, 1)
        dut.wan_rx_dv.value = 0
        dut.wan_rx_last.value = 0
        await ClockCycles(dut.clk, 100)

    def with_seq(v):
        d = bytearray(data)
        d[34:38] = v.to_bytes(4, "big")
        return bytes(d)

    async def counters():
        st = await spi_read(dut, 0x50)
        await spi_write(dut, 0x50, 0)
        return 1 if st & 1 else 0, 1 if st & 4 else 0

    b0, r0 = await counters()
    assert (b0, r0) == (0, 0), f"pre clean bt={b0} rp={r0}"
    await drive_esp(with_seq(100))
    await wait_idle()
    b1, r1 = await counters()
    assert (b1, r1) == (1, 0), f"forged fwd: badtag {b1} replay {r1}"
    await drive_esp(with_seq(36))
    await wait_idle()
    b2, r2 = await counters()
    assert (b2, r2) == (1, 0), f"forged back: badtag {b2} replay {r2}"
    await drive_esp(data)
    await wait_idle()
    b3, r3 = await counters()
    assert (b3, r3) == (0, 0), f"authentic accept: badtag {b3} replay {r3}"
    await drive_esp(data2)
    await wait_idle()
    b4, r4 = await counters()
    assert (b4, r4) == (0, 0), f"authentic next: badtag {b4} replay {r4}"
    await drive_esp(data)
    await wait_idle()
    b5, r5 = await counters()
    assert (b5, r5) == (0, 1), f"in-window replay: badtag {b5} replay {r5}"
    print("replay_window_bounds PASS", flush=True)


def make_esp_payload(seq, esp_len):
    d = bytearray(30 + esp_len)
    d[0:2] = b"\x08\x00"
    d[2] = 0x45
    d[11] = 0x11
    d[14:18] = SRC_IP.to_bytes(4, "big")
    d[18:22] = DST_IP.to_bytes(4, "big")
    d[22:24] = SRC_PORT.to_bytes(2, "big")
    d[24:26] = DST_PORT.to_bytes(2, "big")
    d[26:28] = (8 + esp_len).to_bytes(2, "big")
    d[30:34] = SPI.to_bytes(4, "big")
    d[34:38] = seq.to_bytes(4, "big")
    return bytes(d)


async def drive_wan(dut, payload):
    frame = SRC_MAC.to_bytes(6, "big") + DST_MAC.to_bytes(6, "big") + payload
    for j, b in enumerate(frame):
        dut.wan_rxd.value = b
        dut.wan_rx_dv.value = 1
        dut.wan_rx_last.value = 1 if j == len(frame) - 1 else 0
        await ClockCycles(dut.clk, 1)
    dut.wan_rx_dv.value = 0
    dut.wan_rx_last.value = 0
    await ClockCycles(dut.clk, 200)


async def lan_emit_esp(dut, n=100):
    frame = make_frame(n)
    esp_out = bytearray()

    async def wan_collect():
        for _ in range(200000):
            if int(dut.wan_tx_en.value):
                esp_out.append(int(dut.wan_txd.value))
                if int(dut.wan_tx_last.value):
                    return
            await ClockCycles(dut.clk, 1)

    c = cocotb.start_soon(wan_collect())
    for j, b in enumerate(frame):
        dut.lan_rxd.value = b
        dut.lan_rx_dv.value = 1
        dut.lan_rx_last.value = 1 if j == len(frame) - 1 else 0
        await ClockCycles(dut.clk, 1)
    dut.lan_rx_dv.value = 0
    dut.lan_rx_last.value = 0
    for _ in range(400000):
        await ClockCycles(dut.clk, 1)
        if c.done():
            break
    c.kill()
    return bytes(esp_out)


async def lan_roundtrip(dut, n=100):
    frame = make_frame(n)
    esp_out = bytearray()

    async def wan_collect():
        for _ in range(200000):
            if int(dut.wan_tx_en.value):
                esp_out.append(int(dut.wan_txd.value))
                if int(dut.wan_tx_last.value):
                    return
            await ClockCycles(dut.clk, 1)

    c = cocotb.start_soon(wan_collect())
    for j, b in enumerate(frame):
        dut.lan_rxd.value = b
        dut.lan_rx_dv.value = 1
        dut.lan_rx_last.value = 1 if j == len(frame) - 1 else 0
        await ClockCycles(dut.clk, 1)
    dut.lan_rx_dv.value = 0
    dut.lan_rx_last.value = 0
    for _ in range(400000):
        await ClockCycles(dut.clk, 1)
        if c.done():
            break
    c.kill()
    esp = bytes(esp_out)
    if not esp:
        return False, b""

    plain = bytearray()

    async def dec_collect():
        for _ in range(200000):
            if int(dut.lan_tx_en.value):
                plain.append(int(dut.lan_txd.value))
                if int(dut.lan_tx_last.value):
                    return
            await ClockCycles(dut.clk, 1)

    c2 = cocotb.start_soon(dec_collect())
    await drive_wan(dut, esp[12:])
    for _ in range(400000):
        await ClockCycles(dut.clk, 1)
        if c2.done():
            break
    c2.kill()
    return bytes(plain) == frame, bytes(plain)


@cocotb.test()
async def short_frame_no_hang(dut):
    await start(dut)

    ok, _ = await lan_roundtrip(dut)
    assert ok, "baseline roundtrip"

    for esp_len in (8, 20, 35):
        await drive_wan(dut, make_esp_payload(0x1000 + esp_len, esp_len))
        await ClockCycles(dut.clk, 500)

    ok2, got = await lan_roundtrip(dut)
    assert ok2, f"short frame hang got={len(got)}"
    print("short frame no hang PASS", flush=True)


@cocotb.test()
async def in_order_replay_rejected(dut):
    await start(dut)

    e1 = await lan_emit_esp(dut)
    e2 = await lan_emit_esp(dut)
    data = bytes(e1[12:])
    data2 = bytes(e2[12:])

    async def wait_idle():
        for _ in range(200000):
            if int(dut.u_bridge.u_dec.ds.value) == 0 and int(dut.u_bridge.u_dec.dec_pend.value) == 0:
                return
            await ClockCycles(dut.clk, 1)
        raise AssertionError("dec never idle")

    async def drive_esp(payload):
        rsp = SRC_MAC.to_bytes(6, "big") + DST_MAC.to_bytes(6, "big") + payload
        for j, b in enumerate(rsp):
            dut.wan_rxd.value = b
            dut.wan_rx_dv.value = 1
            dut.wan_rx_last.value = 1 if j == len(rsp) - 1 else 0
            await ClockCycles(dut.clk, 1)
        dut.wan_rx_dv.value = 0
        dut.wan_rx_last.value = 0
        await ClockCycles(dut.clk, 100)

    async def counters():
        st = await spi_read(dut, 0x50)
        await spi_write(dut, 0x50, 0)
        return 1 if st & 1 else 0, 1 if st & 4 else 0

    b, r = await counters()
    assert (b, r) == (0, 0), f"init errors {b} {r}"

    await drive_esp(data)
    await wait_idle()
    b, r = await counters()
    assert (b, r) == (0, 0), f"first accept {b} {r}"

    await drive_esp(data2)
    await wait_idle()
    b, r = await counters()
    assert (b, r) == (0, 0), f"next accept {b} {r}"

    await drive_esp(data)
    await wait_idle()
    b, r = await counters()
    assert (b, r) == (0, 1), f"replay {b} {r}"
    print("in-order replay rejected PASS", flush=True)


@cocotb.test()
async def jump_keeps_replay_window(dut):
    await start(dut)

    e1 = await lan_emit_esp(dut)
    e2 = await lan_emit_esp(dut)
    e3 = await lan_emit_esp(dut)
    d1 = bytes(e1[12:])
    d2 = bytes(e2[12:])
    d3 = bytes(e3[12:])

    async def wait_idle():
        for _ in range(200000):
            if int(dut.u_bridge.u_dec.ds.value) == 0 and int(dut.u_bridge.u_dec.dec_pend.value) == 0:
                return
            await ClockCycles(dut.clk, 1)
        raise AssertionError("dec never idle")

    async def drive_esp(payload):
        rsp = SRC_MAC.to_bytes(6, "big") + DST_MAC.to_bytes(6, "big") + payload
        for j, b in enumerate(rsp):
            dut.wan_rxd.value = b
            dut.wan_rx_dv.value = 1
            dut.wan_rx_last.value = 1 if j == len(rsp) - 1 else 0
            await ClockCycles(dut.clk, 1)
        dut.wan_rx_dv.value = 0
        dut.wan_rx_last.value = 0
        await ClockCycles(dut.clk, 100)

    async def counters():
        st = await spi_read(dut, 0x50)
        await spi_write(dut, 0x50, 0)
        return 1 if st & 1 else 0, 1 if st & 4 else 0

    b, r = await counters()
    assert (b, r) == (0, 0), f"init errors {b} {r}"

    await drive_esp(d1)
    await wait_idle()
    b, r = await counters()
    assert (b, r) == (0, 0), f"first {b} {r}"

    await drive_esp(d3)
    await wait_idle()
    b, r = await counters()
    assert (b, r) == (0, 0), f"jump fwd {b} {r}"

    await drive_esp(d1)
    await wait_idle()
    b, r = await counters()
    assert (b, r) == (0, 1), f"behind window {b} {r}"

    await drive_esp(d2)
    await wait_idle()
    b, r = await counters()
    assert (b, r) == (0, 0), f"inside window {b} {r}"
    print("jump keeps window PASS", flush=True)
