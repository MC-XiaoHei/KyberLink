import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

SRC_MAC = bytes.fromhex("020000000101")
DST_MAC = bytes.fromhex("020000000102")


async def reset_dut(dut):
    dut.rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(5):
        await RisingEdge(dut.clk)


async def drive(dut, frame):
    dut.s_tvalid.value = 0
    dut.s_tlast.value = 0
    for i, b in enumerate(frame):
        dut.s_tdata.value = b
        dut.s_tvalid.value = 1
        dut.s_tlast.value = (i == len(frame) - 1)
        while not dut.s_tready.value:
            await RisingEdge(dut.clk)
        await RisingEdge(dut.clk)
    dut.s_tvalid.value = 0
    dut.s_tlast.value = 0


async def drain(dut, tv, td, tl):
    out = bytearray()
    for _ in range(20000):
        await RisingEdge(dut.clk)
        if int(tv.value):
            out.append(int(td.value))
            if int(tl.value):
                break
    return bytes(out)


@cocotb.test()
async def test_mux_plain_to_enc(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    dut.hs_dport.value = 4501
    dut.m_enc_ready.value = 1
    await RisingEdge(dut.clk)
    frame = SRC_MAC + DST_MAC + bytes([0x08, 0x00]) + bytes((i * 3 + 1) % 256 for i in range(242))
    await drive(dut, frame)
    out = await drain(dut, dut.m_enc_valid, dut.m_enc_data, dut.m_enc_last)
    dut._log.info(f"enc got {len(out)}B exp {len(frame)}B")
    if out != frame:
        for i in range(min(len(out), len(frame))):
            if out[i] != frame[i]:
                dut._log.error(f"first diff @{i} got={out[i]:02x} exp={frame[i]:02x}")
                break
        assert False, f"enc mismatch len {len(out)}/{len(frame)}"
    dut._log.info("plain->enc OK")


@cocotb.test()
async def test_mux_udp_to_hs(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    dut.hs_dport.value = 4501
    dut.m_hs_ready.value = 1
    await RisingEdge(dut.clk)
    payload = bytes((i * 7 + 3) % 256 for i in range(128))
    udp = (4500).to_bytes(2, "big") + (4501).to_bytes(2, "big") + bytes(4) + payload
    ip = bytes([0x45, 0x00]) + (20 + len(udp)).to_bytes(2, "big") + bytes([0, 0, 0x40, 0, 0x40, 0x11, 0, 0]) + bytes([10, 0, 0, 1]) + bytes([10, 0, 0, 2])
    frame = SRC_MAC + DST_MAC + bytes([0x08, 0x00]) + ip + udp
    await drive(dut, frame)
    out = await drain(dut, dut.m_hs_valid, dut.m_hs_data, dut.m_hs_last)
    dut._log.info(f"hs got {len(out)}B exp {len(payload)}B")
    if out != payload:
        for i in range(min(len(out), len(payload))):
            if out[i] != payload[i]:
                dut._log.error(f"first diff @{i} got={out[i]:02x} exp={payload[i]:02x}")
                break
        assert False, f"hs mismatch len {len(out)}/{len(payload)}"
    dut._log.info("udp->hs OK")