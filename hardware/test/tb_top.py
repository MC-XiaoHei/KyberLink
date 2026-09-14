import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer
from tb_bridge import DST_IP, DST_MAC, DST_PORT, IV, KEY, SPI, SRC_IP, SRC_MAC, SRC_PORT

CLK_NS = 20.0


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


async def boot(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_NS, "ns").start())
    dut.rst_n.value = 0
    dut.spi_sck.value = 0
    dut.spi_mosi.value = 0
    dut.spi_csn.value = 1
    dut.lan_rgmii_rx_clk.value = 0
    dut.lan_rgmii_rxd.value = 0
    dut.lan_rgmii_rx_ctl.value = 0
    dut.wan_rgmii_rx_clk.value = 0
    dut.wan_rgmii_rxd.value = 0
    dut.wan_rgmii_rx_ctl.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 4)


async def cfg_gw(dut):
    await spi_write(dut, 0x08, SPI)
    salt = IV >> 32
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
        await spi_write(dut, 0x64 + i, (KEY >> (224 - 32 * i)) & 0xFFFFFFFF)
    await spi_write(dut, 0x00, 1)
    await ClockCycles(dut.clk, 5)


@cocotb.test()
async def pll_lock_and_sys_clk(dut):
    await boot(dut)
    locked = int(dut.u_pll.pll_inst.lock_r.value)
    assert locked == 1, f"lock {locked}"

    edges = []
    for _ in range(9):
        await RisingEdge(dut.clk_sys)
        edges.append(cocotb.utils.get_sim_time("ns"))
    periods = [b - a for a, b in zip(edges, edges[1:])]
    avg = sum(periods) / len(periods)
    assert abs(avg - 8.0) < 0.05, f"clk_sys {avg:.3f}ns"
    print(f"pll lock {avg:.3f}ns ({1000/avg:.2f}MHz) PASS", flush=True)


@cocotb.test()
async def reset_held_until_pll_lock(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_NS, "ns").start())
    dut.rst_n.value = 0
    dut.spi_csn.value = 1
    dut.spi_sck.value = 0
    dut.spi_mosi.value = 0
    dut.lan_rgmii_rx_clk.value = 0
    dut.wan_rgmii_rx_clk.value = 0
    await ClockCycles(dut.clk, 3)
    assert int(dut.gtx_rst.value) == 1, "rst during lock"
    dut.rst_n.value = 1
    for _ in range(200):
        await ClockCycles(dut.clk, 1)
        if int(dut.gtx_rst.value) == 0:
            break
    assert int(dut.gtx_rst.value) == 0, "rst after lock"
    print("rst depends on lock PASS", flush=True)


@cocotb.test()
async def spi_register_access(dut):
    await boot(dut)
    await cfg_gw(dut)
    seq = await spi_read(dut, 0x74)
    assert seq == 1, f"seq {seq:#x}"
    await spi_write(dut, 0x74, 0xDEADBEEF)
    seq = await spi_read(dut, 0x74)
    assert seq == 0xDEADBEEF, f"seq rdbk {seq:#x}"
    st = await spi_read(dut, 0x04)
    assert st & ~0x3 == 0, f"status {st:#010x}"
    err = await spi_read(dut, 0x50)
    assert err == 0, f"err {err:#x}"
    print(f"spi regs PASS seq={seq:#x}", flush=True)


@cocotb.test()
async def rgmii_tx_activity(dut):
    await boot(dut)
    await cfg_gw(dut)

    tx_clk_seen = set()

    async def watch():
        for _ in range(6000):
            await Timer(1, "ns")
            tx_clk_seen.add(int(dut.lan_rgmii_tx_clk.value))

    w = cocotb.start_soon(watch())
    await ClockCycles(dut.clk, 400)
    w.kill()
    assert tx_clk_seen == {0, 1}, f"txc {tx_clk_seen}"
    print(f"rgmii tx PASS {sorted(tx_clk_seen)}", flush=True)


@cocotb.test()
async def rx_clock_input_accepted(dut):
    await boot(dut)
    await cfg_gw(dut)
    cocotb.start_soon(Clock(dut.lan_rgmii_rx_clk, 8.0, "ns").start())
    cocotb.start_soon(Clock(dut.wan_rgmii_rx_clk, 8.0, "ns").start())
    await ClockCycles(dut.clk, 200)
    st = await spi_read(dut, 0x04)
    assert st & ~0x3 == 0, f"status {st:#010x}"
    print(f"rx clk inject PASS st={st:#x}", flush=True)
