import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

KEY = bytes.fromhex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
NONCE = bytes.fromhex("cafebabefacedbaddecaf880")
NBLK = 88


def nct(pt_len):
    return (pt_len >> 4) + (1 if (pt_len & 0xf) else 0)


async def drive_frame(dut, clk, start_sig, valid_sig, ready_sig, data_sig, nonce_sig,
                      pt_len_sig, tag_sig, pt_len, blk):
    nonce_sig.value = int.from_bytes(NONCE, "big")
    pt_len_sig.value = pt_len
    start_sig.value = 1
    await RisingEdge(clk)
    start_sig.value = 0
    valid_sig.value = 1
    sent = 0
    while sent < blk:
        if ready_sig.value:
            data_sig.value = (sent * 128 + 0x1122334455667788) & ((1 << 128) - 1)
            sent += 1
        await RisingEdge(clk)
    valid_sig.value = 0
    while not tag_sig.value:
        await RisingEdge(clk)


async def run_bw(dut, dual, pt_len, blk, use_b=False, period=9.09):
    dut.key.value = int.from_bytes(KEY, "big")
    dut.pt_valid_a.value = 0
    dut.pt_valid_b.value = 0
    dut.ct_ready_a.value = 1
    dut.ct_ready_b.value = 1
    dut.start_a.value = 0
    dut.start_b.value = 0
    dut.rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(5):
        await RisingEdge(dut.clk)

    async def drive_a():
        await drive_frame(dut, dut.clk, dut.start_a, dut.pt_valid_a,
                          dut.pt_ready_a, dut.pt_data_a, dut.nonce_a,
                          dut.pt_len_a, dut.tag_valid_a, pt_len, blk)
        dut._log.info("enc 核完成")

    async def drive_b():
        await drive_frame(dut, dut.clk, dut.start_b, dut.pt_valid_b,
                          dut.pt_ready_b, dut.pt_data_b, dut.nonce_b,
                          dut.pt_len_b, dut.tag_valid_b, pt_len, blk)
        dut._log.info("dec 核完成")

    t0 = cocotb.utils.get_sim_time(units="ns")
    if use_b:
        await drive_b()
    elif dual:
        ta = cocotb.start_soon(drive_a())
        await drive_b()
        await ta
    else:
        await drive_a()
    t1 = cocotb.utils.get_sim_time(units="ns")
    nclk = (t1 - t0) / period
    nbit = blk * 128 * (2 if dual else 1)
    per_block = nclk / blk
    gbps = nbit / (t1 - t0) 
    dut._log.info(f"dual={dual} pt_len={pt_len}B blk={blk} 耗时={nclk:.0f}拍 "
                  f"每块={per_block:.2f}拍 实测={gbps:.3f}Gbps @{1000/period:.0f}MHz "
                  f"(拍数外推@{1000/period:.0f}MHz={nbit/(nclk*period)*1000:.3f})")
    return per_block


@cocotb.test
async def test_bw_dec_only(dut):
    cocotb.start_soon(Clock(dut.clk, 9.09, units="ns").start())
    p = await run_bw(dut, dual=False, pt_len=1400, blk=NBLK, use_b=True)
    assert p <= 24


@cocotb.test
async def test_bw_dual_parallel(dut):
    cocotb.start_soon(Clock(dut.clk, 9.09, units="ns").start())
    p1 = await run_bw(dut, dual=False, pt_len=1400, blk=NBLK)
    p2 = await run_bw(dut, dual=True, pt_len=1400, blk=NBLK)
    assert p1 <= 24, f"单核每块 {p1:.1f} 拍，超过 24 拍预期"
    assert p2 <= 24, f"双核并发每块 {p2:.1f} 拍，超过 24 拍预期"
