import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, ReadOnly, RisingEdge, Timer

DEPTH = 16


async def init(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    await FallingEdge(dut.clk)
    await Timer(1, "ps")
    dut.rst.value = 1
    dut.s_tvalid.value = 0
    dut.s_tdata.value = 0
    dut.s_tlast.value = 0
    dut.m_tready.value = 0
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    await Timer(1, "ps")
    dut.rst.value = 0
    await RisingEdge(dut.clk)


async def step(dut, s_tvalid=0, s_tdata=0, s_tlast=0, m_tready=0):
    await FallingEdge(dut.clk)
    await Timer(1, "ps")
    dut.s_tvalid.value = s_tvalid
    dut.s_tdata.value = s_tdata
    dut.s_tlast.value = s_tlast
    dut.m_tready.value = m_tready
    await Timer(1, "ps")
    await ReadOnly()
    st = (int(dut.s_tready.value), int(dut.m_tvalid.value),
          int(dut.m_tdata.value), int(dut.m_tlast.value))
    await RisingEdge(dut.clk)
    return st


@cocotb.test()
async def ready_not_stuck_low_after_reset(dut):
    await init(dut)
    st = await step(dut, s_tvalid=1, s_tdata=0x11)
    assert st[0] == 1, f"s_tready {st[0]}"
    for k in range(3):
        st = await step(dut, s_tvalid=1, s_tdata=0x20 + k)
        assert st[0] == 1, f"wr {k}"
    print("reset s_tready PASS", flush=True)


@cocotb.test()
async def fill_to_depth_and_reject(dut):
    await init(dut)
    accepted = 0
    for i in range(DEPTH + 16):
        st = await step(dut, s_tvalid=1, s_tdata=i & 0xFF)
        if st[0]:
            accepted += 1
    assert accepted == DEPTH, f"accepted {accepted}"

    got = []
    for _ in range(DEPTH + 4):
        st = await step(dut, m_tready=1)
        if not st[1]:
            break
        got.append(st[2])
    assert len(got) == DEPTH, f"got {len(got)}"
    expect = [i & 0xFF for i in range(DEPTH)]
    assert got == expect, f"data {got[:8].hex()}"
    print(f"depth boundary PASS ({accepted} bytes)", flush=True)


@cocotb.test()
async def wrapping_preserves_data(dut):
    await init(dut)
    half = DEPTH // 2
    for round_i in range(24):
        base = (round_i * 7) & 0xFF
        acc = 0
        for k in range(half):
            st = await step(dut, s_tvalid=1, s_tdata=(base + k) & 0xFF)
            if st[0]:
                acc += 1
        assert acc == half, f"round {round_i} {acc}/{half}"
        got = []
        for _ in range(half):
            st = await step(dut, m_tready=1)
            assert st[1], f"round {round_i} idx {len(got)}"
            got.append(st[2])
        for k, d in enumerate(got):
            assert d == ((base + k) & 0xFF), f"round {round_i} k {k} {d:#x}"
    print("wraparound PASS", flush=True)


@cocotb.test()
async def tlast_preserved_through_fifo(dut):
    await init(dut)
    seq = [0xA1, 0xB2, 0xC3]
    for i, b in enumerate(seq):
        await step(dut, s_tvalid=1, s_tdata=b, s_tlast=(1 if i == len(seq) - 1 else 0))
    got = []
    for _ in range(len(seq)):
        st = await step(dut, m_tready=1)
        assert st[1], f"idx {len(got)}"
        got.append((st[2], st[3]))
    for i, (d, tlast) in enumerate(got):
        assert d == seq[i], f"idx {i} {d:#x}"
        assert tlast == (1 if i == len(seq) - 1 else 0), f"idx {i} tlast {tlast}"
    print("tlast PASS", flush=True)
