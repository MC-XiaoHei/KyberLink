import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
from cocotb.utils import get_sim_time

from tb_bridge import make_frame, setup, DST_MAC, SPI

PAYLOAD = 1400
PAD_N = (16 - ((PAYLOAD + 2) & 0xF)) & 0xF
PT_LEN = PAYLOAD + 2 + PAD_N
ESP_LEN = 42 + 20 + PT_LEN + 16


@cocotb.test()
async def enc_bw(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    await setup(dut)
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    n = 50
    frame = make_frame(PAYLOAD)
    dut.s_enc_tdata.value = 0
    dut.s_enc_tvalid.value = 0
    dut.s_enc_tlast.value = 0
    dut.m_enc_tready.value = 1

    async def feed():
        from cocotb.triggers import ReadOnly
        for i in range(n):
            idx = 0
            while True:
                dut.s_enc_tdata.value = frame[idx]
                dut.s_enc_tvalid.value = 1
                dut.s_enc_tlast.value = 1 if idx == len(frame) - 1 else 0
                await ReadOnly()
                ready = int(dut.s_enc_tready.value)
                await ClockCycles(dut.clk, 1)
                if ready:
                    idx += 1
                if idx >= len(frame):
                    break
            dut.s_enc_tvalid.value = 0
            dut.s_enc_tlast.value = 0
            await ClockCycles(dut.clk, 1)

    frames = []

    async def watchdog():
        for _ in range(200000):
            await ClockCycles(dut.clk, 1)

    times = []
    async def collect():
        for i in range(n):
            out = bytearray()
            t_start = None
            while True:
                if int(dut.m_enc_tvalid.value):
                    if t_start is None:
                        t_start = get_sim_time("ns")
                    out.append(int(dut.m_enc_tdata.value))
                    if int(dut.m_enc_tlast.value):
                        t_end = get_sim_time("ns") + 8
                        break
                await ClockCycles(dut.clk, 1)
            frames.append(bytes(out))
            times.append((t_start, t_end))
            await ClockCycles(dut.clk, 1)

    cocotb.start_soon(watchdog())
    f_task = cocotb.start_soon(feed())
    c_task = cocotb.start_soon(collect())
    await f_task
    await c_task
    elapsed = int(sum(times[i + 1][0] - times[i][0] for i in range(1, n - 1)) / (n - 2) * n)
    gbps = n * ESP_LEN * 8 / elapsed
    pgbps = n * PAYLOAD * 8 / elapsed
    ok = all(
        len(f) == ESP_LEN
        and f[:6] == DST_MAC.to_bytes(6, "big")
        and f[42:46] == SPI.to_bytes(4, "big")
        for f in frames
    )
    for i, f in enumerate(frames):
        if len(f) != ESP_LEN or f[:6] != DST_MAC.to_bytes(6, "big") or f[42:46] != SPI.to_bytes(4, "big"):
            print(f"frame {i} len={len(f)} head={f[:8].hex()} spi={f[42:46].hex()}")
    print(f"enc bw: {n} frames in {elapsed:.0f}ns -> esp={gbps:.4f} Gbps payload={pgbps:.4f} Gbps content_ok={ok}", flush=True)
    assert ok, "content mismatch"

    from Crypto.Cipher import AES
    KEY_B = bytes(range(32))
    pat_pt = bytes((j * 7 + 3) & 0xFF for j in range(1400)) + bytes(6) + bytes([6, 4])
    ecb = AES.new(KEY_B, AES.MODE_ECB)
    crypto_ok = True
    for i, f in enumerate(frames):
        seq = i
        nonce = seq.to_bytes(4, "big") + bytes.fromhex("0102030405060708")
        aad = SPI.to_bytes(4, "big") + seq.to_bytes(4, "big")
        ks = b"".join(ecb.encrypt(nonce + (2 + j).to_bytes(4, "big")) for j in range(88))
        ct_exp = bytes(a ^ b for a, b in zip(pat_pt, ks))
        e = AES.new(KEY_B, AES.MODE_GCM, nonce=nonce)
        e.update(aad)
        e.encrypt(pat_pt)
        tag_exp = e.digest()
        esp = f[42:]
        ct_hw = esp[20:20 + 1408]
        tag_hw = esp[1428:1428 + 16]
        if esp[8:20] != nonce:
            print(f"enc IV field mismatch frame {i+1} iv={esp[8:20].hex()}")
            crypto_ok = False
        if ct_hw != ct_exp:
            bad = next(j for j in range(88) if ct_hw[j*16:(j+1)*16] != ct_exp[j*16:(j+1)*16])
            print(f"enc CT mismatch frame {i+1} blk {bad} "
                  f"hw={ct_hw[bad*16:bad*16+16].hex()} exp={ct_exp[bad*16:bad*16+16].hex()}")
            with open(f"bad_frame_{i+1}.bin", "wb") as fh:
                fh.write(ct_hw)
            crypto_ok = False
        if tag_hw != tag_exp:
            print(f"enc TAG mismatch frame {i+1} hw={tag_hw.hex()} exp={tag_exp.hex()}")
            crypto_ok = False
    print(f"enc crypto_ok={crypto_ok}", flush=True)
    assert crypto_ok, "enc crypto mismatch"
    assert gbps > 0.99, f"enc esp-rate {gbps:.4f} below 0.99 Gbps"


@cocotb.test()
async def dec_bw(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    await setup(dut)
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    n = 50
    frame = make_frame(PAYLOAD)
    dut.s_enc_tdata.value = 0
    dut.s_enc_tvalid.value = 0
    dut.s_enc_tlast.value = 0
    dut.m_enc_tready.value = 1

    esps = []

    async def enc_feed():
        from cocotb.triggers import ReadOnly
        for i in range(n):
            idx = 0
            while True:
                dut.s_enc_tdata.value = frame[idx]
                dut.s_enc_tvalid.value = 1
                dut.s_enc_tlast.value = 1 if idx == len(frame) - 1 else 0
                await ReadOnly()
                ready = int(dut.s_enc_tready.value)
                await ClockCycles(dut.clk, 1)
                if ready:
                    idx += 1
                if idx >= len(frame):
                    break
            dut.s_enc_tvalid.value = 0
            dut.s_enc_tlast.value = 0
            await ClockCycles(dut.clk, 1)

    async def enc_collect():
        for i in range(n):
            out = bytearray()
            while True:
                if int(dut.m_enc_tvalid.value):
                    out.append(int(dut.m_enc_tdata.value))
                    if int(dut.m_enc_tlast.value):
                        break
                await ClockCycles(dut.clk, 1)
            esps.append(bytes(out))
            await ClockCycles(dut.clk, 1)

    async def dec_feed():
        from cocotb.triggers import ReadOnly
        for i in range(n):
            e = esps[i][42:]
            idx = 0
            while True:
                dut.s_dec_tdata.value = e[idx]
                dut.s_dec_tvalid.value = 1
                dut.s_dec_tlast.value = 1 if idx == len(e) - 1 else 0
                await ReadOnly()
                ready = int(dut.s_dec_tready.value)
                await ClockCycles(dut.clk, 1)
                if ready:
                    idx += 1
                if idx >= len(e):
                    break
            dut.s_dec_tvalid.value = 0
            dut.s_dec_tlast.value = 0
            await ClockCycles(dut.clk, 42)
    ef = cocotb.start_soon(enc_feed())
    ec = cocotb.start_soon(enc_collect())
    await ef
    await ec
    assert all(len(e) == ESP_LEN for e in esps), "enc feed produced bad esp"
    dut.s_dec_tdata.value = 0
    dut.s_dec_tvalid.value = 0
    dut.s_dec_tlast.value = 0
    dut.m_dec_tready.value = 1
    plains = []
    times = []
    async def dec_collect():
        for i in range(n):
            out = bytearray()
            t_start = None
            while True:
                if int(dut.m_dec_tvalid.value):
                    if t_start is None:
                        t_start = get_sim_time("ns")
                    out.append(int(dut.m_dec_tdata.value))
                    if int(dut.m_dec_tlast.value):
                        t_end = get_sim_time("ns") + 8
                        break
                await ClockCycles(dut.clk, 1)
            plains.append(bytes(out))
            times.append((t_start, t_end))
            await ClockCycles(dut.clk, 1)

    df = cocotb.start_soon(dec_feed())
    dc = cocotb.start_soon(dec_collect())
    await df
    await dc
    elapsed = int(sum(times[i + 1][0] - times[i][0] for i in range(1, n - 1)) / (n - 2) * n)
    gbps = n * ESP_LEN * 8 / elapsed
    pgbps = n * PAYLOAD * 8 / elapsed
    ok = all(p == frame for p in plains)
    for i, p in enumerate(plains):
        if p != frame:
            d = next((j for j in range(min(len(p), len(frame))) if p[j] != frame[j]), min(len(p), len(frame)))
            print(f"plain {i} len={len(p)} first_diff={d} got={p[d:d+8].hex()} exp={frame[d:d+8].hex()}")
    print(f"dec bw: {n} frames in {elapsed:.0f}ns -> esp={gbps:.4f} Gbps payload={pgbps:.4f} Gbps content_ok={ok}", flush=True)
    assert ok, "content mismatch"
    assert gbps > 0.99, f"dec esp-rate {gbps:.4f} below 0.99 Gbps"
