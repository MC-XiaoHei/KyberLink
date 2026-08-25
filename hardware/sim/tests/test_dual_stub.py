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


async def mgmt_status(dut, u):
    s = await xbus_req(dut, u, 0xF0000200, 0)
    return s


async def mgmt_write_word(dut, u, w):
    await xbus_req(dut, u, 0xF0000208, 1, w)


async def mgmt_read_word(dut, u):
    return await xbus_req(dut, u, 0xF0000204, 0)


async def mgmt_set_len(dut, u, n):
    await xbus_req(dut, u, 0xF0000210, 1, n & 0x1FFF)


async def mgmt_cmd(dut, u, v):
    await xbus_req(dut, u, 0xF000020C, 1, v)


def seg_count(n):
    return (n + SEG_DATA - 1) // SEG_DATA


async def send_msg(dut, u, data):
    nseg = seg_count(len(data))
    for s in range(nseg):
        start = s * SEG_DATA
        end = min(start + SEG_DATA, len(data))
        slen = 2 + (end - start)
        if s > 0:
            deadline = 0
            while True:
                st = await mgmt_status(dut, u)
                if (st >> 31) & 1:
                    await mgmt_cmd(dut, u, 1)
                    continue
                if (st >> 29) & 1:
                    break
                deadline += 1
                if deadline > 200000:
                    dut._log.warning(f"send wait frame done timeout seg {s}/{nseg}")
                    return False
        w0 = (s << 24) | (nseg << 16)
        if end - start >= 2:
            w0 |= (data[start] << 8) | data[start + 1]
        elif end - start == 1:
            w0 |= data[start] << 8
        from cocotb.utils import get_sim_time
        dut._log.info(f"  send seg {s+1} w0 write cyc={int(get_sim_time('ns')) // 20} w0={w0:08x}")
        await mgmt_write_word(dut, u, w0)
        i = 2
        while i < slen:
            w = 0
            for j in range(4):
                idx = start + i - 2 + j
                if idx < end:
                    w |= data[idx] << (24 - 8 * j)
            await mgmt_write_word(dut, u, w)
            i += 4
        await mgmt_set_len(dut, u, slen)
        await mgmt_cmd(dut, u, 2)
        dut._log.info(f"  seg {s+1}/{nseg} sent ({slen}B)")
    return True


async def recv_msg(dut, u, expect):
    out = bytearray()
    have = set()
    deadline = 0
    while len(out) < expect:
        st = await mgmt_status(dut, u)
        if (st >> 31) & 1:
            rlen = (st >> 16) & 0x1FFF
            frame = bytearray()
            nw = (rlen + 3) // 4
            for _ in range(nw):
                w = await mgmt_read_word(dut, u)
                frame += w.to_bytes(4, "big")
            pay = bytes(frame)
            sn = pay[0]
            total = pay[1]
            idx = sn * SEG_DATA
            for i, b in enumerate(pay[2:]):
                if idx + i < expect:
                    while len(out) <= idx + i:
                        out.append(0)
                    out[idx + i] = b
            if sn not in have:
                have.add(sn)
                dut._log.info(f"  seg {sn+1}/{total} recv")
            await mgmt_cmd(dut, u, 1)
        deadline += 1
        if deadline > 2000000:
            dut._log.warning(f"recv timeout got {len(out)}/{expect}")
            return None
    return bytes(out[:expect])


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

    m1 = bytes([0xA1]) * M1_LEN
    m2 = bytes([0xA2]) * M2_LEN
    m3 = bytes([0xA3]) * M3_LEN
    m4 = bytes([0xA4]) * M4_LEN

    dut._log.info("A send M1 + B recv")
    t_s = cocotb.start_soon(send_msg(dut, dut.u_a, m1))
    t_r = cocotb.start_soon(recv_msg(dut, dut.u_b, M1_LEN))
    ok = await t_s.join()
    got1 = await t_r.join()
    dut._log.info("B recv M1")
    if not ok:
        raise AssertionError("A send M1 failed")
    if got1 != m1:
        raise AssertionError(f"B got M1 mismatch len {len(got1) if got1 else 0}")

    dut._log.info("B send M2 + A recv")
    t_s = cocotb.start_soon(send_msg(dut, dut.u_b, m2))
    t_r = cocotb.start_soon(recv_msg(dut, dut.u_a, M2_LEN))
    ok = await t_s.join()
    got2 = await t_r.join()
    if not ok:
        raise AssertionError("B send M2 failed")
    if got2 != m2:
        raise AssertionError("A got M2 mismatch")

    t_s = cocotb.start_soon(send_msg(dut, dut.u_a, m3))
    t_r = cocotb.start_soon(recv_msg(dut, dut.u_b, M3_LEN))
    ok = await t_s.join()
    got3 = await t_r.join()
    if got3 != m3:
        raise AssertionError("B got M3 mismatch")

    t_s = cocotb.start_soon(send_msg(dut, dut.u_b, m4))
    t_r = cocotb.start_soon(recv_msg(dut, dut.u_a, M4_LEN))
    ok = await t_s.join()
    got4 = await t_r.join()
    if got4 != m4:
        raise AssertionError("A got M4 mismatch")

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
