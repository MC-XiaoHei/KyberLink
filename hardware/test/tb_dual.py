import json
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, ReadOnly

PAYLOAD = 1400
MAC_A = 0xAABBCC000001
MAC_B = 0xAABBCC000002
IP_A = 0xC0A80101
IP_B = 0xC0A80202
PORT = 0x1194

VEC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..",
                   "vectors", "generated", "handshake.json")
OBS = bytearray()


async def spi_write(dut, sck, mosi, miso, csn, addr, data):
    csn.value = 0
    await ClockCycles(dut.clk, 1)
    word = (addr << 32) | data
    for i in range(39, -1, -1):
        mosi.value = (word >> i) & 1
        await ClockCycles(dut.clk, 2)
        sck.value = 1
        await ClockCycles(dut.clk, 2)
        sck.value = 0
        await ClockCycles(dut.clk, 2)
    csn.value = 1
    await ClockCycles(dut.clk, 2)


async def spi_read(dut, sck, mosi, miso, csn, addr):
    csn.value = 0
    await ClockCycles(dut.clk, 1)
    word = (1 << 39) | (addr << 32)
    got = 0
    for i in range(39, -1, -1):
        mosi.value = (word >> i) & 1
        await ClockCycles(dut.clk, 2)
        sck.value = 1
        await ClockCycles(dut.clk, 2)
        if i < 32:
            got = (got << 1) | int(miso.value)
        sck.value = 0
        await ClockCycles(dut.clk, 2)
    csn.value = 1
    await ClockCycles(dut.clk, 2)
    return got


async def cfg_gw(dut, sck, mosi, miso, csn, mac_src, mac_dst, ip_src, ip_dst):
    await spi_write(dut, sck, mosi, miso, csn, 0x14, ip_src)
    await spi_write(dut, sck, mosi, miso, csn, 0x18, ip_dst)
    await spi_write(dut, sck, mosi, miso, csn, 0x1C, PORT)
    await spi_write(dut, sck, mosi, miso, csn, 0x20, PORT)
    await spi_write(dut, sck, mosi, miso, csn, 0x24, mac_src & 0xFFFFFFFF)
    await spi_write(dut, sck, mosi, miso, csn, 0x28, mac_src >> 32)
    await spi_write(dut, sck, mosi, miso, csn, 0x2C, mac_dst & 0xFFFFFFFF)
    await spi_write(dut, sck, mosi, miso, csn, 0x30, mac_dst >> 32)
    await spi_write(dut, sck, mosi, miso, csn, 0x00, 1)


async def hsk_send(dut, spi, data):
    await spi_write(dut, *spi, 0x3C, len(data))
    for chunk in (data[i:i + 4] for i in range(0, len(data), 4)):
        w = int.from_bytes(chunk + b"\x00" * (4 - len(chunk)), "big")
        await spi_write(dut, *spi, 0x40, w)
    await spi_write(dut, *spi, 0x00, 1 << 1)


async def hsk_recv(dut, spi, expect, tag):
    got = bytearray()
    for _ in range(800):
        st = await spi_read(dut, *spi, 0x04)
        if st & 1:
            break
        for _ in range(200):
            await ClockCycles(dut.clk, 1)
    else:
        for side, br_, rx_, tx_ in (("A", dut.u_a_full.u_spi.u_regs, dut.u_a_full.u_rx_wan, dut.u_a_full.u_tx_wan),
                                    ("B", dut.u_b_full.u_spi.u_regs, dut.u_b_full.u_rx_wan, dut.u_b_full.u_tx_wan)):
            print(f"{side} regs: txcnt={int(br_.tx_cnt.value)} txst={int(br_.tx_state.value)} "
                  f"txn={int(br_.tx_n.value)} txwords={int(br_.tx_words.value)} txlen={int(br_.r_hsk_tx_len.value)} "
                  f"rxcnt={int(br_.rx_cnt.value)} ctrl={int(br_.r_ctrl.value)} | "
                  f"txstate={int(tx_.state.value)} paylen={int(tx_.pay_len.value)} hcnt={int(tx_.hcnt.value)} "
                  f"pb={int(tx_.pb.value)} s_hskv={int(tx_.s_hsk_tvalid.value)} mtv={int(tx_.m_tvalid.value)} | "
                  f"rxstate={int(rx_.state.value)} rxcnt2={int(rx_.cnt.value)} drop={int(rx_.drop.value)} "
                  f"is_hsk={int(rx_.is_hsk.value)} is_data={int(rx_.is_data.value)} pd={int(rx_.pay_done.value)} "
                  f"tv={int(rx_.hsk_tail_v.value)} last={int(rx_.hsk_last.value)} len={int(rx_.hsk_len.value)}",
                  flush=True)
        print(f"fcs a={int(dut.a_mac_rx_fcs_err.value)} b={int(dut.b_mac_rx_fcs_err.value)} "
              f"b_rx_dv={int(dut.b_wan_rx_dv.value)} b_rx_last={int(dut.b_wan_rx_last.value)}", flush=True)
        for side, ph, trdy in (("A", dut.u_a_wan_phy, dut.a_wan_tx_ready),
                               ("B", dut.u_b_wan_phy, dut.b_wan_tx_ready)):
            txm = ph.axis_gmii_tx_inst
            print(f"{side} mac: tready={int(trdy.value)} gmii_en={int(ph.gmii_tx_en.value)} "
                  f"txst={int(txm.state_reg.value)} txvalid={int(txm.s_axis_tvalid.value)} "
                  f"txlast={int(txm.s_axis_tlast.value)} txer={int(ph.gmii_tx_er.value)}",
                  flush=True)
        raise TimeoutError(f"{tag} hsk recv timeout")
    ln = await spi_read(dut, *spi, 0x34) & 0xFFFF
    for w_i in range((ln + 3) // 4):
        w = await spi_read(dut, *spi, 0x38)
        got += w.to_bytes(4, "big")
    got = bytes(got[:ln])
    ar = dut.u_a_full.u_spi.u_regs
    print(f"RXF tag={tag} ln={ln} wptr={int(ar.rx_wr_ptr.value)} rptr={int(ar.rx_rd_ptr.value)} "
          f"cnt={int(ar.rx_cnt.value)} f1619={int(ar.rx_fifo[1619].value):08x} "
          f"f1620={int(ar.rx_fifo[1620].value):08x} f1621={int(ar.rx_fifo[1621].value):08x}",
          flush=True)
    assert got == expect, f"hsk mismatch got={got[:16].hex()}.. exp={expect[:16].hex()}.."
    return got


async def write_sa(dut, spi, sa, initiator):
    sk_ei = bytes.fromhex(sa["sk_ei"])
    sk_er = bytes.fromhex(sa["sk_er"])
    enc_key, dec_key = (sk_ei, sk_er) if initiator else (sk_er, sk_ei)
    await spi_write(dut, *spi, 0x08, int.from_bytes(bytes.fromhex(sa["spi_i"]), "big"))
    for i in range(8):
        await spi_write(dut, *spi, 0x44 + i, int.from_bytes(enc_key[i * 4:i * 4 + 4], "big"))
    for i in range(8):
        await spi_write(dut, *spi, 0x64 + i, int.from_bytes(dec_key[i * 4:i * 4 + 4], "big"))
    salt = bytes.fromhex(sa["sa_salt"])[:8]
    await spi_write(dut, *spi, 0x0C, int.from_bytes(salt[4:8], "big"))
    await spi_write(dut, *spi, 0x10, int.from_bytes(salt[0:4], "big"))
    await spi_write(dut, *spi, 0x00, 1)


async def feed(dut, rxd, dv, last, ready, frame):
    for j, b in enumerate(frame):
        rxd.value = b
        dv.value = 1
        last.value = 1 if j == len(frame) - 1 else 0
        await ReadOnly()
        r = int(ready.value)
        await ClockCycles(dut.clk, 1)
        if r:
            continue
        while not int(ready.value):
            await ClockCycles(dut.clk, 1)
        await ClockCycles(dut.clk, 1)
    dv.value = 0
    last.value = 0
    await ClockCycles(dut.clk, 1)


async def collect(dut, tdata, tvalid, tlast, n, tag):
    frames = []
    for i in range(n):
        out = bytearray()
        waits = 0
        while True:
            if int(tvalid.value):
                out.append(int(tdata.value))
                if int(tlast.value):
                    break
            await ClockCycles(dut.clk, 1)
            waits += 1
            if waits > 400000:
                raise TimeoutError(f"{tag} frame timeout")
        frames.append(bytes(out))
        await ClockCycles(dut.clk, 1)
    return frames


@cocotb.test()
async def dual_handshake(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    for sig in ("a_lan_rxd", "a_lan_rx_dv", "a_lan_rx_last",
                "b_lan_rxd", "b_lan_rx_dv", "b_lan_rx_last",
                "spi_a_sck", "spi_a_mosi", "spi_b_sck", "spi_b_mosi"):
        getattr(dut, sig).value = 0
    dut.a_lan_tx_ready.value = 1
    dut.b_lan_tx_ready.value = 1
    dut.spi_a_csn.value = 1
    dut.spi_b_csn.value = 1
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    with open(VEC) as f:
        vec = json.load(f)[0]
    ini, rsp = vec["initiator"], vec["responder"]
    m1 = bytes.fromhex(ini["tx"][0])
    m2 = bytes.fromhex(ini["rx"][0])
    m3 = bytes.fromhex(ini["tx"][1])
    m4 = bytes.fromhex(ini["rx"][1])
    sa = ini["sa"]

    spi_a = (dut.spi_a_sck, dut.spi_a_mosi, dut.spi_a_miso, dut.spi_a_csn)
    spi_b = (dut.spi_b_sck, dut.spi_b_mosi, dut.spi_b_miso, dut.spi_b_csn)
    await cfg_gw(dut, *spi_a, MAC_A, MAC_B, IP_A, IP_B)
    await cfg_gw(dut, *spi_b, MAC_B, MAC_A, IP_B, IP_A)
    await ClockCycles(dut.clk, 10)

    obs = OBS
    CAP = []

    async def wan_sniff(name, en, dat, sink):
        frame = []
        for _ in range(4000000):
            await ClockCycles(dut.clk, 1)
            if int(en.value):
                b = int(dat.value)
                frame.append(b)
                if sink is not None:
                    sink.append(b)
            elif frame:
                fb = bytes(frame)
                CAP.append((name, fb))
                print(f"CAP {name} len={len(fb)} head={fb[:24].hex()} tail={fb[-24:].hex()}", flush=True)
                frame = []

    cocotb.start_soon(wan_sniff("A", dut.a_wan_tx_en_obs, dut.a_wan_txd_obs, obs))
    cocotb.start_soon(wan_sniff("B", dut.b_wan_tx_en_obs, dut.b_wan_txd_obs, None))

    async def rx_axis_sniff(name, dv, dat, last):
        frame = []
        for _ in range(4000000):
            await ClockCycles(dut.clk, 1)
            if int(dv.value):
                frame.append(int(dat.value))
            elif frame:
                fb = bytes(frame)
                print(f"RXS {name} len={len(fb)} head={fb[:16].hex()} tail={fb[-16:].hex()}", flush=True)
                frame = []

    cocotb.start_soon(rx_axis_sniff("A", dut.a_wan_rx_dv, dut.a_wan_rxd, dut.a_wan_rx_last))
    cocotb.start_soon(rx_axis_sniff("B", dut.b_wan_rx_dv, dut.b_wan_rxd, dut.b_wan_rx_last))

    await hsk_send(dut, spi_a, m1)
    print("A sent m1", flush=True)
    await hsk_recv(dut, spi_b, m1, "B")
    await hsk_send(dut, spi_b, m2)
    print("B sent m2", flush=True)
    await hsk_recv(dut, spi_a, m2, "A")
    await hsk_send(dut, spi_a, m3)
    print("A sent m3", flush=True)
    await hsk_recv(dut, spi_b, m3, "B")
    await hsk_send(dut, spi_b, m4)
    print("B sent m4", flush=True)
    await hsk_recv(dut, spi_a, m4, "A")
    print("dual handshake m1-m4 done", flush=True)

    await write_sa(dut, spi_a, sa, True)
    await write_sa(dut, spi_b, sa, False)
    await ClockCycles(dut.clk, 4)

    for i in range(8):
        w = int.from_bytes(bytes.fromhex(sa["sk_ei"])[i * 4:i * 4 + 4], "big")
        assert await spi_read(dut, *spi_a, 0x44 + i) == w, f"a key_enc[{i}]"
        assert await spi_read(dut, *spi_b, 0x64 + i) == w, f"b key_dec[{i}]"
        w = int.from_bytes(bytes.fromhex(sa["sk_er"])[i * 4:i * 4 + 4], "big")
        assert await spi_read(dut, *spi_a, 0x64 + i) == w, f"a key_dec[{i}]"
        assert await spi_read(dut, *spi_b, 0x44 + i) == w, f"b key_enc[{i}]"
    print("dual SA loaded and verified", flush=True)

    plain = bytes((j * 7 + 3) & 0xFF for j in range(PAYLOAD))

    fa = cocotb.start_soon(feed(dut, dut.a_lan_rxd, dut.a_lan_rx_dv, dut.a_lan_rx_last,
                                dut.u_a_full.enc_s_tready, plain))
    await fa
    cb = cocotb.start_soon(collect(dut, dut.b_lan_txd, dut.b_lan_tx_en, dut.b_lan_tx_last, 1, "B->decode"))
    rx_b = await cb

    ok = rx_b[0] == plain
    print(f"dual A->B decode_ok={ok} got_len={len(rx_b[0])}", flush=True)
    assert ok, f"A->B mismatch got={rx_b[0][:32].hex()}"

    cip = bytes(obs)
    enc_ok = len(cip) >= 1400 and cip != plain[:len(cip)]
    assert enc_ok, "wan link not encrypted"

    fb = cocotb.start_soon(feed(dut, dut.b_lan_rxd, dut.b_lan_rx_dv, dut.b_lan_rx_last,
                                dut.u_b_full.enc_s_tready, plain))
    ca = cocotb.start_soon(collect(dut, dut.a_lan_txd, dut.a_lan_tx_en, dut.a_lan_tx_last, 1, "A->decode"))
    await fb
    rx_a = await ca
    assert rx_a[0] == plain, "B->A mismatch"
    print("dual handshake + both directions PASS", flush=True)


async def boot(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    for sig in ("a_lan_rxd", "a_lan_rx_dv", "a_lan_rx_last",
                "b_lan_rxd", "b_lan_rx_dv", "b_lan_rx_last",
                "spi_a_sck", "spi_a_mosi", "spi_b_sck", "spi_b_mosi"):
        getattr(dut, sig).value = 0
    dut.a_lan_tx_ready.value = 1
    dut.b_lan_tx_ready.value = 1
    dut.spi_a_csn.value = 1
    dut.spi_b_csn.value = 1
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    spi_a = (dut.spi_a_sck, dut.spi_a_mosi, dut.spi_a_miso, dut.spi_a_csn)
    spi_b = (dut.spi_b_sck, dut.spi_b_mosi, dut.spi_b_miso, dut.spi_b_csn)
    return spi_a, spi_b


async def pipe(dut, data, tag):
    fa = cocotb.start_soon(feed(dut, dut.a_lan_rxd, dut.a_lan_rx_dv, dut.a_lan_rx_last,
                                dut.u_a_full.enc_s_tready, data))
    cb = cocotb.start_soon(collect(dut, dut.b_lan_txd, dut.b_lan_tx_en, dut.b_lan_tx_last, 1, tag))
    await fa
    rx = await cb
    return rx[0]


@cocotb.test()
async def dual_short_hsk(dut):
    spi_a, spi_b = await boot(dut)
    await cfg_gw(dut, *spi_a, MAC_A, MAC_B, IP_A, IP_B)
    await cfg_gw(dut, *spi_b, MAC_B, MAC_A, IP_B, IP_A)
    await ClockCycles(dut.clk, 10)
    msg = bytes(range(0xA0, 0xA8))
    await hsk_send(dut, spi_a, msg)
    await hsk_recv(dut, spi_b, msg, "short")
    print("dual short hsk PASS", flush=True)


@cocotb.test()
async def dual_concurrent(dut):
    spi_a, spi_b = await boot(dut)
    await cfg_gw(dut, *spi_a, MAC_A, MAC_B, IP_A, IP_B)
    await cfg_gw(dut, *spi_b, MAC_B, MAC_A, IP_B, IP_A)
    await ClockCycles(dut.clk, 10)
    msg = bytes(range(0x40, 0x60))
    blk = bytes((j * 5 + 1) & 0xFF for j in range(1200))

    async def flood():
        for k in range(3):
            await feed(dut, dut.a_lan_rxd, dut.a_lan_rx_dv, dut.a_lan_rx_last,
                       dut.u_a_full.enc_s_tready, bytes([k]) + blk)

    f = cocotb.start_soon(flood())
    await ClockCycles(dut.clk, 40)
    await hsk_send(dut, spi_a, msg)
    await hsk_recv(dut, spi_b, msg, "conc")
    await f
    print("dual concurrent hsk+flood PASS", flush=True)


@cocotb.test()
async def dual_rekey(dut):
    spi_a, spi_b = await boot(dut)
    await cfg_gw(dut, *spi_a, MAC_A, MAC_B, IP_A, IP_B)
    await cfg_gw(dut, *spi_b, MAC_B, MAC_A, IP_B, IP_A)
    await ClockCycles(dut.clk, 10)
    with open(VEC) as f:
        vec = json.load(f)[0]
    sa = vec["initiator"]["sa"]
    await write_sa(dut, spi_a, sa, True)
    await write_sa(dut, spi_b, sa, False)
    await ClockCycles(dut.clk, 4)
    plain = bytes((j * 7 + 3) & 0xFF for j in range(200))
    rx = await pipe(dut, plain, "rekey r1")
    assert rx == plain, "rekey pre 1"
    rx = await pipe(dut, bytes([0x5A]) + plain, "rekey r2")
    assert rx == bytes([0x5A]) + plain, "rekey pre 2"
    await write_sa(dut, spi_a, sa, True)
    await write_sa(dut, spi_b, sa, False)
    await ClockCycles(dut.clk, 4)
    rx = await pipe(dut, bytes([0xA5]) + plain, "rekey post")
    assert rx == bytes([0xA5]) + plain, f"rekey post mismatch got={rx[:32].hex()}"
    print("dual rekey PASS", flush=True)

print("TB_DUAL_MARK_V5", flush=True)
