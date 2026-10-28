import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer

KEY = int.from_bytes(bytes(range(32)), "big")


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
async def spi_half_key_write(dut):
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

    full = 0xAABBCCDD
    for i in range(3):
        await spi_write(dut, 0x44 + i, full)
    await spi_write(dut, 0x00, 1)
    await ClockCycles(dut.clk, 3)
    got = int(dut.key_enc.value)
    exp = (full << 224) | (full << 192) | (full << 160)
    print(f"half_key enc={got:064x} exp={exp:064x}", flush=True)
    assert got == exp, f"half key enc mismatch {got:064x} vs {exp:064x}"

    for i in range(3):
        await spi_write(dut, 0x44 + i, 0)
    for i in range(3, 8):
        await spi_write(dut, 0x44 + i, full)
    await ClockCycles(dut.clk, 4)
    rk = int(dut.u_regs.r_key_enc.value)
    print(f"half_key2 rk={rk:064x}", flush=True)
    exp_rk = (full << 128) | (full << 96) | (full << 64) | (full << 32) | full
    assert rk == exp_rk, f"key2 readback mismatch {rk:064x}"

    await spi_write(dut, 0x00, 1)
    await ClockCycles(dut.clk, 3)
    got = int(dut.key_enc.value)
    exp = (full << 128) | (full << 96) | (full << 64) | (full << 32) | full
    print(f"half_key2 enc={got:064x} exp={exp:064x}", flush=True)
    assert got == exp, f"half key2 enc mismatch {got:064x} vs {exp:064x}"


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


@cocotb.test()
async def err_counters_and_soft_rst(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    dut.spi_sck.value = 0
    dut.spi_mosi.value = 0
    dut.spi_csn.value = 1
    dut.err_badtag_i.value = 0
    dut.err_badpad_i.value = 0
    dut.err_replay_i.value = 0
    dut.err_oversize_i.value = 0
    dut.hsk_rx_wr.value = 0
    dut.hsk_rx_data.value = 0
    dut.hsk_rx_last.value = 0
    dut.hsk_rx_len.value = 0
    dut.hsk_tx_ready.value = 1
    dut.seq_upd.value = 0
    dut.seq_val.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    cfg = 0xA5A5A5A5
    await spi_write(dut, 0x08, cfg)

    for _ in range(3):
        dut.err_badtag_i.value = 1
        await ClockCycles(dut.clk, 1)
        dut.err_badtag_i.value = 0
        await ClockCycles(dut.clk, 1)
    for _ in range(2):
        dut.err_replay_i.value = 1
        await ClockCycles(dut.clk, 1)
        dut.err_replay_i.value = 0
        await ClockCycles(dut.clk, 1)
    dut.err_oversize_i.value = 1
    await ClockCycles(dut.clk, 1)
    dut.err_oversize_i.value = 0
    await ClockCycles(dut.clk, 1)

    st = await spi_read(dut, 0x50)
    assert st & 1, "badtag flag"
    assert not (st & 2), "badpad flag"
    assert st & 4, "replay flag"
    assert st & 8, "oversize flag"
    assert not (st & 16), "rxdrop flag retired"

    await spi_write(dut, 0x00, 4)
    await ClockCycles(dut.clk, 2)
    assert await spi_read(dut, 0x50) == 0, "flags not cleared"
    assert int(dut.cfg_spi.value) == cfg, "cfg lost after soft rst"

    dut.err_oversize_i.value = 1
    await ClockCycles(dut.clk, 1)
    dut.err_oversize_i.value = 0
    await ClockCycles(dut.clk, 1)
    st = await spi_read(dut, 0x50)
    assert st & 8, "oversize after soft rst"


@cocotb.test()
async def timing_injection(dut):
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

    await spi_write(dut, 0x08, 0xCAFEBABE)

    dut.spi_csn.value = 0
    await ClockCycles(dut.clk, 3)
    for i in range(39, -1, -1):
        dut.spi_mosi.value = ((0x08 << 32) | 0xDEADBEEF) >> i & 1
        await ClockCycles(dut.clk, 2)
        dut.spi_sck.value = 1
        await ClockCycles(dut.clk, 2)
        dut.spi_sck.value = 0
        await Timer(4, "ns")
        dut.spi_sck.value = 1
        await Timer(3, "ns")
        dut.spi_sck.value = 0
        await Timer(1, "ns")
    dut.spi_csn.value = 1
    await ClockCycles(dut.clk, 4)
    got = int(dut.cfg_spi.value)
    assert got == 0xCAFEBABE, f"sub-window glitch latched {got:08x}"

    word = (0x08 << 32) | 0x11112222
    dut.spi_csn.value = 0
    await ClockCycles(dut.clk, 2)
    for i in range(39, 19, -1):
        dut.spi_mosi.value = (word >> i) & 1
        await ClockCycles(dut.clk, 2)
        dut.spi_sck.value = 1
        await ClockCycles(dut.clk, 2)
        dut.spi_sck.value = 0
        await ClockCycles(dut.clk, 2)
    dut.spi_csn.value = 1
    await ClockCycles(dut.clk, 4)
    assert int(dut.cfg_spi.value) == 0xCAFEBABE, "csn abort should not write"

    word = (0x08 << 32) | 0x55667788
    dut.spi_csn.value = 0
    await ClockCycles(dut.clk, 2)
    for i in range(39, -1, -1):
        dut.spi_mosi.value = (word >> i) & 1
        await ClockCycles(dut.clk, 2)
        dut.spi_sck.value = 1
        await ClockCycles(dut.clk, 2)
        dut.spi_sck.value = 0
        await ClockCycles(dut.clk, 2)
    dut.spi_csn.value = 1
    await ClockCycles(dut.clk, 4)
    assert int(dut.cfg_spi.value) == 0x55667788, "next frame broken"


@cocotb.test()
async def soft_rst_mid_traffic(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    dut.spi_sck.value = 0
    dut.spi_mosi.value = 0
    dut.spi_csn.value = 1
    dut.err_badtag_i.value = 0
    dut.err_badpad_i.value = 0
    dut.err_replay_i.value = 0
    dut.err_oversize_i.value = 0
    dut.hsk_rx_wr.value = 0
    dut.hsk_rx_data.value = 0
    dut.hsk_rx_last.value = 0
    dut.hsk_rx_len.value = 0
    dut.hsk_tx_ready.value = 1
    dut.seq_upd.value = 0
    dut.seq_val.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    cfg = 0x12345678
    await spi_write(dut, 0x08, cfg)
    payload = [0x00112233, 0x44556677, 0x8899aabb, 0xccddeeff]

    await spi_write(dut, 0x3C, len(payload) * 4)
    for w in payload[:2]:
        await spi_write(dut, 0x40, w)
    dut.err_oversize_i.value = 1
    await ClockCycles(dut.clk, 1)
    dut.err_oversize_i.value = 0
    await ClockCycles(dut.clk, 1)
    assert await spi_read(dut, 0x50) & 8, "oversize counted mid-traffic"

    await spi_write(dut, 0x00, 4)
    await ClockCycles(dut.clk, 2)
    assert await spi_read(dut, 0x50) == 0, "badtag not cleared"
    assert int(dut.cfg_spi.value) == cfg, "cfg lost after mid-traffic soft rst"

    out = []

    async def collect_tx():
        for _ in range(10000):
            if int(dut.hsk_tx_valid.value):
                out.append(int(dut.hsk_tx_data.value))
                if int(dut.hsk_tx_last.value):
                    return
            await ClockCycles(dut.clk, 1)

    await spi_write(dut, 0x3C, len(payload) * 4)
    for w in payload:
        await spi_write(dut, 0x40, w)
    c = cocotb.start_soon(collect_tx())
    await spi_write(dut, 0x00, 2)
    await ClockCycles(dut.clk, 200)
    await c
    assert out == payload, f"tx mismatch {out} vs {payload}"
    print("soft_rst_mid_traffic PASS", flush=True)


async def spi_read_slow(dut, addr, half=30):
    dut.spi_csn.value = 0
    await ClockCycles(dut.clk, 1)
    word = (1 << 39) | (addr << 32)
    got = 0
    for i in range(39, -1, -1):
        dut.spi_mosi.value = (word >> i) & 1
        await ClockCycles(dut.clk, half)
        dut.spi_sck.value = 1
        await ClockCycles(dut.clk, half)
        if i < 32:
            got = (got << 1) | int(dut.spi_miso.value)
        dut.spi_sck.value = 0
    dut.spi_csn.value = 1
    await ClockCycles(dut.clk, 2)
    return got


@cocotb.test()
async def slow_sck_read_block(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    dut.spi_sck.value = 0
    dut.spi_mosi.value = 0
    dut.spi_csn.value = 1
    dut.hsk_rx_wr.value = 0
    dut.hsk_rx_data.value = 0
    dut.hsk_rx_last.value = 0
    dut.hsk_rx_len.value = 0
    dut.hsk_rx_ready.value = 1
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    words = [0xA1B2C3D4, 0x11223344, 0x55667788, 0x99AABBCC]
    for i, w in enumerate(words):
        dut.hsk_rx_data.value = w
        dut.hsk_rx_wr.value = 1
        await ClockCycles(dut.clk, 1)
        dut.hsk_rx_wr.value = 0
        await ClockCycles(dut.clk, 1)
    dut.hsk_rx_len.value = len(words) * 4
    dut.hsk_rx_last.value = 1
    await ClockCycles(dut.clk, 1)
    dut.hsk_rx_last.value = 0
    await ClockCycles(dut.clk, 3)

    st = await spi_read_slow(dut, 0x04)
    assert st & 1, f"rx pending {st:#x}"
    ln = await spi_read_slow(dut, 0x34)
    assert ln == len(words) * 4, f"len {ln} exp {len(words)*4}"

    for i, want in enumerate(words):
        got = await spi_read_slow(dut, 0x38)
        assert got == want, f"word {i} {got:#010x} exp {want:#010x}"
    print("slow sck read PASS", flush=True)
