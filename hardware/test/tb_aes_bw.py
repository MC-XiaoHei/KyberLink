import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

KEY = 0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f
N = 2000


@cocotb.test()
async def aes_bw(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    dut.key.value = KEY
    dut.block_in.value = 0x00112233445566778899aabbccddeeff
    dut.blk_valid.value = 0
    dut.key_load.value = 0
    dut.start.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    dut.key_load.value = 1
    dut.start.value = 1
    await ClockCycles(dut.clk, 1)
    dut.key_load.value = 0
    await ClockCycles(dut.clk, 1)
    dut.start.value = 0
    blocks = 0
    t_first = None
    t_last = None
    for i in range(N * 40):
        dut.blk_valid.value = 1 if int(dut.load_rdy.value) else 0
        if int(dut.done.value):
            if blocks == 0:
                t_first = i
            blocks += 1
            if blocks == N:
                t_last = i
                break
        await ClockCycles(dut.clk, 1)
    assert t_first is not None, "no block completed"
    per = (t_last - t_first) / (N - 1)
    gbps = 128 / per * 125e6 / 1e9
    print(f"aes bw: {N} blocks over {t_last - t_first} clk -> {per:.3f} clk/block = {gbps:.3f} Gbps @125MHz")
