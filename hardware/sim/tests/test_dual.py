import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

CLK_PERIOD_NS = 20
BASE = os.path.join(os.path.dirname(__file__), "..", "..", "..", "software", "build")
FW_A = os.path.join(BASE, "fw_stub_a.bin")
FW_B = os.path.join(BASE, "fw_stub_b.bin")


async def load_fw(dut, flash, path):
    with open(path, "rb") as f:
        fw = f.read()
    for i, b in enumerate(fw):
        flash[i].value = b
    return len(fw)


async def boot(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    cocotb.start_soon(Clock(dut.gtx_clk, 8, unit="ns").start())
    dut.rstn.value = 0
    for _ in range(20):
        await RisingEdge(dut.clk)
    dut.rstn.value = 1
    await RisingEdge(dut.clk)


def rd32(sig):
    return int(sig.value)


@cocotb.test(timeout_time=600, timeout_unit="sec")
async def test_dual_handshake(dut):
    await load_fw(dut, dut.u_a.u_flash.mem, FW_A)
    await load_fw(dut, dut.u_b.u_flash.mem, FW_B)
    await boot(dut)

    uart_a = bytearray()
    uart_b = bytearray()

    async def uart_cap(sig, out):
        while True:
            while int(sig.value) == 1:
                await RisingEdge(dut.clk)
            await Timer(52083 // 2, unit="ns")
            byte = 0
            for i in range(8):
                await Timer(52083, unit="ns")
                byte |= int(sig.value) << i
            await Timer(52083, unit="ns")
            out.append(byte)

    cocotb.start_soon(uart_cap(dut.uart_a_txd, uart_a))
    cocotb.start_soon(uart_cap(dut.uart_b_txd, uart_b))

    deadline = 0
    while rd32(dut.u_a.u_bc.enc_spi) == 0:
        await RisingEdge(dut.clk)
        deadline += 1
        if deadline > 20_000_000:
            dut._log.info(f"uart_a: {bytes(uart_a)[:200]}")
            dut._log.info(f"uart_b: {bytes(uart_b)[:200]}")
            break
    dut._log.info(f"A enc_spi after {deadline} clk = {rd32(dut.u_a.u_bc.enc_spi):#x}")
    if rd32(dut.u_a.u_bc.enc_spi) == 0:
        raise AssertionError("handshake did not complete (A SA not written)")

    sa_a = rd32(dut.u_a.u_bc.cfg_sa_en)
    sa_b = rd32(dut.u_b.u_bc.cfg_sa_en)
    dut._log.info(f"sa_en A={sa_a} B={sa_b}")

    a_spi_i = rd32(dut.u_a.u_bc.enc_spi)
    a_spi_r = rd32(dut.u_a.u_bc.dec_spi)
    b_spi_i = rd32(dut.u_b.u_bc.enc_spi)
    b_spi_r = rd32(dut.u_b.u_bc.dec_spi)
    dut._log.info(f"A enc_spi={a_spi_i:#x} dec_spi={a_spi_r:#x}")
    dut._log.info(f"B enc_spi={b_spi_i:#x} dec_spi={b_spi_r:#x}")
    if a_spi_i != b_spi_r or a_spi_r != b_spi_i:
        raise AssertionError("SPI mismatch (A.enc != B.dec)")

    a_ek = rd32(dut.u_a.u_bc.enc_key)
    b_dk = rd32(dut.u_b.u_bc.dec_key)
    if a_ek != b_dk:
        raise AssertionError("A enc_key != B dec_key (direction key mismatch)")
    a_dk = rd32(dut.u_a.u_bc.dec_key)
    b_ek = rd32(dut.u_b.u_bc.enc_key)
    if a_dk != b_ek:
        raise AssertionError("A dec_key != B enc_key (reverse direction mismatch)")

    a_salt = rd32(dut.u_a.u_bc.enc_salt)
    b_salt = rd32(dut.u_b.u_bc.dec_salt)
    if a_salt != b_salt:
        raise AssertionError("salt mismatch")
    dut._log.info("dual handshake OK: SA established and consistent")
