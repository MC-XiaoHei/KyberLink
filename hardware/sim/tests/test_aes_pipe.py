import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
@cocotb.test()
async def test_aes_pipe_single(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst_n.value = 0
    dut.key_mode.value = 1
    dut.key_load.value = 1
    dut.start.value = 0
    dut.blk_valid.value = 0
    dut.block_in.value = 0
    dut.key.value = int.from_bytes(bytes.fromhex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"), "big")
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.start.value = 1
    dut.blk_valid.value = 1
    for _ in range(200):
        await RisingEdge(dut.clk)
        if int(dut.done.value):
            got = int(dut.block_out.value).to_bytes(16, "big").hex()
            exp = "f29000b62a499fd0a9f39a6add2e7780"
            dut._log.info(f"AES(0) got={got} exp={exp}")
            assert got == exp, "AES-256(0) mismatch"
            return
    assert False, "AES timeout"
