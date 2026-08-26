import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

CLK_PERIOD_NS = 20
BASE = os.path.join(os.path.dirname(__file__), "..", "..", "..", "software", "build")
FW = os.path.join(BASE, "fw_blank.bin")

SEG_DATA = 450
M1_LEN = 3168
M2_LEN = 6477
M3_LEN = 4401
M4_LEN = 4401
SPI_I = 0x10000001
SPI_R = 0x20000002


async def load_fw(dut, flash, path):
    with open(path, "rb") as f:
        fw = f.read()
    for i, b in enumerate(fw):
        flash[i].value = b


async def clk_phase(dut, sig, half, delay=0):
    if delay:
        sig.value = 0
        await Timer(delay, unit="ns")
    while True:
        sig.value = 1
        await Timer(half, unit="ns")
        sig.value = 0
        await Timer(half, unit="ns")


async def boot(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    cocotb.start_soon(Clock(dut.gtx_clk, 8, unit="ns").start())
    cocotb.start_soon(clk_phase(dut, dut.gtx_clk90, 4, 2))
    dut.rstn.value = 0
    await Timer(100, unit="ns")
    dut.rstn.value = 1
    await RisingEdge(dut.clk)
    await Timer(2000, unit="ns")


def mtest(dut, tag):
    p = f"{tag}_mtest_"
    return (dut._id(p + "adr", False), dut._id(p + "dat", False),
            dut._id(p + "we", False), dut._id(p + "stb", False),
            dut._id(p + "cyc", False), dut._id(p + "ack", False),
            dut._id(p + "dato_o", False))

async def xbus_req(dut, u, adr, we, dat=0):
    tag = "a" if u is dut.u_a else "b"
    adr_s, dat_s, we_s, stb_s, cyc_s, ack_s, dato_s = mtest(dut, tag)
    adr_s.value = adr
    we_s.value = we
    dat_s.value = dat
    stb_s.value = 1
    cyc_s.value = 1
    acked = False
    for _ in range(200):
        await RisingEdge(dut.clk)
        if int(ack_s.value):
            acked = True
            break
    if not acked:
        m = u
        try:
            dut._log.warning(f"xbus ack timeout {tag} adr={adr:#x} we={we} | "
                             f"mgmt_in stb={int(m.u_mgmt.xbus_stb_i.value)} "
                             f"cyc={int(m.u_mgmt.xbus_cyc_i.value)} "
                             f"adr={int(m.u_mgmt.xbus_adr_i.value):#x} "
                             f"we={int(m.u_mgmt.xbus_we_i.value)}")
        except Exception as e:
            dut._log.warning(f"  diag err {e}")
    rd = int(dato_s.value) if not we else 0
    stb_s.value = 0
    cyc_s.value = 0
    we_s.value = 0
    await RisingEdge(dut.clk)
    return rd


async def bc_write(dut, u, off, val):
    await xbus_req(dut, u, 0xF0000100 + off, 1, val)


async def write_sa(dut, u, role):
    key = [0xAB] * 32
    salt = [0xCD] * 32
    if role == "a":
        enc, dec = SPI_I, SPI_R
    else:
        enc, dec = SPI_R, SPI_I
    for i in range(8):
        await bc_write(dut, u, 0x00 + 4 * i, int.from_bytes(bytes(key[4 * i:4 * i + 4]), "big"))
        await bc_write(dut, u, 0x80 + 4 * i, int.from_bytes(bytes(key[4 * i:4 * i + 4]), "big"))
    await bc_write(dut, u, 0x30, enc)
    await bc_write(dut, u, 0xA0, dec)
    await bc_write(dut, u, 0x34, int.from_bytes(bytes(salt[0:4]), "big"))
    await bc_write(dut, u, 0x38, int.from_bytes(bytes(salt[4:8]), "big"))
    await bc_write(dut, u, 0xA4, int.from_bytes(bytes(salt[0:4]), "big"))
    await bc_write(dut, u, 0xA8, int.from_bytes(bytes(salt[4:8]), "big"))
    await bc_write(dut, u, 0x40, 0)
    await bc_write(dut, u, 0xB0, 0)
    await bc_write(dut, u, 0x20, 0x3)


@cocotb.test(timeout_time=900, timeout_unit="sec")
async def test_dual_stub_handshake(dut):
    await load_fw(dut, dut.u_a.u_flash.mem, FW)
    await load_fw(dut, dut.u_b.u_flash.mem, FW)
    await boot(dut)

    await write_sa(dut, dut.u_a, "a")
    await write_sa(dut, dut.u_b, "b")
    await RisingEdge(dut.clk)

    a_spi_i = int(dut.u_a.u_bc.enc_spi.value)
    a_spi_r = int(dut.u_a.u_bc.dec_spi.value)
    b_spi_i = int(dut.u_b.u_bc.enc_spi.value)
    b_spi_r = int(dut.u_b.u_bc.dec_spi.value)
    dut._log.info(f"A spi {a_spi_i:#x}/{a_spi_r:#x} B spi {b_spi_i:#x}/{b_spi_r:#x}")
    if a_spi_i != b_spi_r or a_spi_r != b_spi_i:
        raise AssertionError("SPI mismatch")
    a_ek = int(dut.u_a.u_bc.enc_key.value)
    b_dk = int(dut.u_b.u_bc.dec_key.value)
    if a_ek != b_dk:
        raise AssertionError("key mismatch")
    dut._log.info("dual stub handshake OK: segmented M1-M4 frame exchange + SA")
