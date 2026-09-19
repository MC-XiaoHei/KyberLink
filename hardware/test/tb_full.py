import json
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, ReadOnly

try:
    from simnode import DLL, Fsm, fingerprint

    HAVE_FFI = True
except (ImportError, OSError, AttributeError):
    DLL = ""
    HAVE_FFI = False

PAYLOAD = 1400
IDLE_CLOCKS = 5000
FFI_ITERS = 2000
MAC_A = 0xAABBCC000001
MAC_B = 0xAABBCC000002
IP_A = 0xC0A80101
IP_B = 0xC0A80202
PORT = 0x1194

VEC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..",
                   "vectors", "generated", "handshake.json")


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


HSK_ACK = 0xFFFFFFFF


async def hsk_read_blk(dut, spi):
    sck, mosi, miso, csn = spi
    st = await spi_read(dut, sck, mosi, miso, csn, 0x04)
    if not (st & 1):
        return None
    ln = await spi_read(dut, sck, mosi, miso, csn, 0x34) & 0xFFFF
    blk = bytearray()
    for _ in range((ln + 3) // 4):
        w = await spi_read(dut, sck, mosi, miso, csn, 0x38)
        blk += w.to_bytes(4, "big")
    blk = bytes(blk[:ln])
    total = int.from_bytes(blk[0:4], "big")
    ofs = int.from_bytes(blk[4:8], "big")
    return total, ofs, blk[8:]


async def hsk_read_raw(dut, spi):
    sck, mosi, miso, csn = spi
    ln = await spi_read(dut, sck, mosi, miso, csn, 0x34) & 0xFFFF
    buf = bytearray()
    for _ in range((ln + 3) // 4):
        w = await spi_read(dut, sck, mosi, miso, csn, 0x38)
        buf += w.to_bytes(4, "big")
    return bytes(buf[:ln])


async def hsk_send_ack(dut, spi, off):
    sck, mosi, miso, csn = spi
    await spi_write(dut, sck, mosi, miso, csn, 0x3C, 8)
    await spi_write(dut, sck, mosi, miso, csn, 0x40, HSK_ACK)
    await spi_write(dut, sck, mosi, miso, csn, 0x40, off)
    await spi_write(dut, sck, mosi, miso, csn, 0x00, 1 << 1)
    for _ in range(600):
        st = await spi_read(dut, sck, mosi, miso, csn, 0x04)
        if not (st & 2):
            break
        for _ in range(200):
            await ClockCycles(dut.clk, 1)


async def hsk_send_blk(dut, spi, total, off, blk):
    sck, mosi, miso, csn = spi
    words = (len(blk) + 3) // 4 + 2
    await spi_write(dut, sck, mosi, miso, csn, 0x3C, words * 4)
    await spi_write(dut, sck, mosi, miso, csn, 0x40, total)
    await spi_write(dut, sck, mosi, miso, csn, 0x40, off)
    for chunk in (blk[i:i + 4] for i in range(0, len(blk), 4)):
        w = int.from_bytes(chunk + b"\x00" * (4 - len(chunk)), "big")
        await spi_write(dut, sck, mosi, miso, csn, 0x40, w)
    await spi_write(dut, sck, mosi, miso, csn, 0x00, 1 << 1)
    for _ in range(600):
        st = await spi_read(dut, sck, mosi, miso, csn, 0x04)
        if not (st & 2):
            break
        for _ in range(200):
            await ClockCycles(dut.clk, 1)


async def hsk_send(dut, spi, data, max_retry=40):
    total = len(data)
    off = 0
    while off < len(data):
        blk = data[off:off + 1004]
        end = off + len(blk)
        acked = False
        for _ in range(max_retry):
            await hsk_send_blk(dut, spi, total, off, blk)
            for _ in range(400):
                r = await hsk_read_blk(dut, spi)
                if r is None:
                    for _ in range(100):
                        await ClockCycles(dut.clk, 1)
                    continue
                tl, ofs, _pl = r
                if tl == HSK_ACK and ofs == off:
                    acked = True
                    break
            if acked:
                break
        assert acked, f"hsk_send no ack for off={off}"
        off = end


async def hsk_recv(dut, spi, expect, tag, max_retry=40):
    got = bytearray()
    total = None
    for _ in range(max_retry * 40):
        r = await hsk_read_blk(dut, spi)
        if r is None:
            if total is not None and len(got) >= total:
                break
            for _ in range(500):
                await ClockCycles(dut.clk, 1)
            continue
        tl, ofs, pl = r
        if tl == HSK_ACK:
            continue
        if total is None:
            total = tl
        end = min(ofs + len(pl), len(expect))
        if len(got) < end:
            got.extend(b"\x00" * (end - len(got)))
        got[ofs:end] = pl[:end - ofs]
        await hsk_send_ack(dut, spi, ofs)
        if len(got) >= total:
            break
    else:
        raise TimeoutError(f"{tag} hsk recv timeout")
    got = bytes(got[:total])
    assert got == expect, f"{tag} hsk mismatch got={got[:16].hex()} exp={expect[:16].hex()}"
    return got


async def write_sa(dut, spi, sa, initiator):
    sck, mosi, miso, csn = spi
    sk_ei = bytes.fromhex(sa["sk_ei"])
    sk_er = bytes.fromhex(sa["sk_er"])
    enc_key, dec_key = (sk_ei, sk_er) if initiator else (sk_er, sk_ei)
    await spi_write(dut, sck, mosi, miso, csn, 0x08, int.from_bytes(bytes.fromhex(sa["spi_i"]), "big"))
    for i in range(8):
        await spi_write(dut, sck, mosi, miso, csn, 0x44 + i, int.from_bytes(enc_key[i * 4:i * 4 + 4], "big"))
    for i in range(8):
        await spi_write(dut, sck, mosi, miso, csn, 0x64 + i, int.from_bytes(dec_key[i * 4:i * 4 + 4], "big"))
    salt = bytes.fromhex(sa["sa_salt"])[:8]
    await spi_write(dut, sck, mosi, miso, csn, 0x0C, int.from_bytes(salt[4:8], "big"))
    await spi_write(dut, sck, mosi, miso, csn, 0x10, int.from_bytes(salt[0:4], "big"))
    await spi_write(dut, sck, mosi, miso, csn, 0x00, 1)


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


async def collect(dut, tdata, tvalid, tlast, n, tag, clock=None):
    if clock is None:
        clock = dut.clk
    frames = []
    for i in range(n):
        out = bytearray()
        waits = 0
        while True:
            if int(tvalid.value):
                out.append(int(tdata.value))
                if int(tlast.value):
                    break
            elif out:
                waits += 1
                if waits > 20000:
                    raise TimeoutError(f"{tag} frame tail timeout")
            else:
                waits += 1
                if waits > 200000:
                    raise TimeoutError(f"{tag} frame wait timeout")
            await ClockCycles(clock, 1)
        frames.append(bytes(out))
    return frames


async def boot(dut, clk_b_period=8):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    cocotb.start_soon(Clock(dut.clk_b, clk_b_period, "ns").start())
    dut.rst_n.value = 0
    for sig in ("a_lan_rxd", "a_lan_rx_dv", "a_lan_rx_last",
                "b_lan_rxd", "b_lan_rx_dv", "b_lan_rx_last",
                "spi_a_sck", "spi_a_mosi", "spi_b_sck", "spi_b_mosi"):
        getattr(dut, sig).value = 0
    dut.a_lan_tx_ready.value = 1
    dut.b_lan_tx_ready.value = 1
    dut.spi_a_csn.value = 1
    dut.spi_b_csn.value = 1
    dut.b_inject_en.value = 0
    dut.b_inject_tdata.value = 0
    dut.b_inject_tvalid.value = 0
    dut.b_inject_tlast.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    spi_a = (dut.spi_a_sck, dut.spi_a_mosi, dut.spi_a_miso, dut.spi_a_csn)
    spi_b = (dut.spi_b_sck, dut.spi_b_mosi, dut.spi_b_miso, dut.spi_b_csn)
    return spi_a, spi_b


async def ctrl_send(dut, spi, data):
    sck, mosi, miso, csn = spi
    for chunk in (data[i:i + 4] for i in range(0, len(data), 4)):
        w = int.from_bytes(chunk + b"\x00" * (4 - len(chunk)), "big")
        await spi_write(dut, sck, mosi, miso, csn, 0x41, w)
    await spi_write(dut, sck, mosi, miso, csn, 0x42, len(data))


@cocotb.test()
async def rgmii_roundtrip(dut):
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

    plain = bytes((j * 7 + 3) & 0xFF for j in range(PAYLOAD))
    fa = cocotb.start_soon(feed(dut, dut.a_lan_rxd, dut.a_lan_rx_dv, dut.a_lan_rx_last,
                                dut.u_a_node.enc_s_tready, plain))
    cb = cocotb.start_soon(collect(dut, dut.b_lan_txd, dut.b_lan_tx_en, dut.b_lan_tx_last, 1, "A->B"))

    await fa
    await ClockCycles(dut.clk, 3000)
    rx_b = await cb
    assert rx_b[0] == plain, f"A->B len {len(rx_b[0])} vs {len(plain)}"

    fb = cocotb.start_soon(feed(dut, dut.b_lan_rxd, dut.b_lan_rx_dv, dut.b_lan_rx_last,
                                dut.u_b_node.enc_s_tready, plain))
    ca = cocotb.start_soon(collect(dut, dut.a_lan_txd, dut.a_lan_tx_en, dut.a_lan_tx_last, 1, "B->A"))
    await fb
    rx_a = await ca
    assert rx_a[0] == plain, "B->A mismatch"
    print("rgmii roundtrip PASS", flush=True)


@cocotb.test()
async def rgmii_200_align(dut):
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

    n = 200
    plain = bytes((j * 11 + 7) & 0xFF for j in range(n))
    got = bytearray()

    async def b_watch():
        for _ in range(400000):
            await ClockCycles(dut.clk, 1)
            if int(dut.b_lan_tx_en.value):
                got.append(int(dut.b_lan_txd.value))
                if int(dut.b_lan_tx_last.value):
                    return
        raise AssertionError("no dec output")

    esp = bytearray()

    async def wan_watch():
        seen_low = False
        for _ in range(400000):
            await ClockCycles(dut.clk, 1)
            if not int(dut.a_tx_en.value):
                seen_low = True
                continue
            if not seen_low:
                continue
            if int(dut.a_tx_ready.value):
                esp.append(int(dut.a_txd.value))
                if int(dut.a_tx_last.value):
                    return
        raise AssertionError("no enc output")

    ww = cocotb.start_soon(wan_watch())
    fa = cocotb.start_soon(feed(dut, dut.a_lan_rxd, dut.a_lan_rx_dv, dut.a_lan_rx_last,
                                dut.u_a_node.enc_s_tready, plain))
    wb = cocotb.start_soon(b_watch())
    await fa
    await wb
    await ww
    assert bytes(got) == plain, f"align200 plain {len(got)}"
    from Crypto.Cipher import AES
    key = bytes.fromhex(sa["sk_ei"])
    nonce = bytes(esp[50:62])
    aad = bytes(esp[42:46]) + bytes(esp[46:50])
    body = bytes(esp[62:-16])
    tag = bytes(esp[-16:])
    cc = AES.new(key, AES.MODE_GCM, nonce=nonce)
    cc.update(aad)
    ppt = cc.decrypt_and_verify(body, tag)
    pad_n = (16 - ((200 + 2) & 0xF)) & 0xF
    assert ppt[:200] == plain, f"align200 oracle tail {ppt[196:208].hex()}"
    assert ppt[200:] == bytes(pad_n) + bytes([pad_n, 4]), f"align200 pad {ppt[200:].hex()}"
    print(f"align200 oracle ok esp={len(esp)}", flush=True)


@cocotb.test()
async def rgmii_min_max_frames(dut):
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

    for n in (64, 65, 66, 80, 81, 1400, 1402):
        plain = bytes((j * 11 + 7) & 0xFF for j in range(n))
        got = bytearray()

        fa = cocotb.start_soon(feed(dut, dut.a_lan_rxd, dut.a_lan_rx_dv, dut.a_lan_rx_last,
                                    dut.u_a_node.enc_s_tready, plain))
        trace = []
        async def b_watch_t():
            for _ in range(400000):
                await ClockCycles(dut.clk, 1)
                if int(dut.b_lan_tx_en.value):
                    got.append(int(dut.b_lan_txd.value))
                    trace.append((int(dut.b_lan_txd.value), int(dut.b_lan_tx_last.value)))
                    if int(dut.b_lan_tx_last.value):
                        return
            raise AssertionError("no dec output")
        wb = cocotb.start_soon(b_watch_t())
        await fa
        await wb
        print(f"TAIL{n} last6={trace[-6:]}", flush=True)
        if bytes(got) != plain:
            mem = dut.u_a_node.u_bridge.u_enc.mem
            for k in range(0, 5):
                print(f"  A mem[{k}]={int(mem[k].value):032x}", flush=True)
        assert bytes(got) == plain, f"len {n} mismatch got {len(got)}"
    print("rgmii min/max frames PASS", flush=True)

@cocotb.test()
async def fcs_ok_silent(dut):
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
    err = []

    async def watch():
        for _ in range(60000):
            await ClockCycles(dut.clk, 1)
            if int(dut.a_mac_rx_fcs_err.value) or int(dut.b_mac_rx_fcs_err.value):
                err.append(1)

    w = cocotb.start_soon(watch())
    for n in (64, 1400):
        plain = bytes((j * 11 + 7) & 0xFF for j in range(n))
        got = bytearray()
        fa = cocotb.start_soon(feed(dut, dut.a_lan_rxd, dut.a_lan_rx_dv, dut.a_lan_rx_last,
                                    dut.u_a_node.enc_s_tready, plain))

        async def b_watch():
            for _ in range(400000):
                await ClockCycles(dut.clk, 1)
                if int(dut.b_lan_tx_en.value):
                    got.append(int(dut.b_lan_txd.value))
                    if int(dut.b_lan_tx_last.value):
                        return
            raise AssertionError("no dec output")

        wb = cocotb.start_soon(b_watch())
        await fa
        await wb
        assert bytes(got) == plain, f"fcs fuzz len {n} mismatch"

        fwd = bytearray()
        fb = cocotb.start_soon(feed(dut, dut.b_lan_rxd, dut.b_lan_rx_dv, dut.b_lan_rx_last,
                                    dut.u_b_node.enc_s_tready, plain))

        async def a_watch():
            for _ in range(400000):
                await ClockCycles(dut.clk, 1)
                if int(dut.a_lan_tx_en.value):
                    fwd.append(int(dut.a_lan_txd.value))
                    if int(dut.a_lan_tx_last.value):
                        return
            raise AssertionError("no dec output reverse")

        wa = cocotb.start_soon(a_watch())
        await fb
        await wa
        assert bytes(fwd) == plain, f"fcs fuzz reverse len {n} mismatch"
    await w
    assert not err, "fcs_err asserted on clean traffic"
    print("fcs silent on clean traffic PASS", flush=True)


@cocotb.test()
async def dual_handshake(dut):
    spi_a, spi_b = await boot(dut)
    await cfg_gw(dut, *spi_a, MAC_A, MAC_B, IP_A, IP_B)
    await cfg_gw(dut, *spi_b, MAC_B, MAC_A, IP_B, IP_A)
    await ClockCycles(dut.clk, 10)

    with open(VEC) as f:
        vec = json.load(f)[0]
    ini = vec["initiator"]
    m1 = bytes.fromhex(ini["tx"][0])
    m2 = bytes.fromhex(ini["rx"][0])
    m3 = bytes.fromhex(ini["tx"][1])
    m4 = bytes.fromhex(ini["rx"][1])
    sa = ini["sa"]

    async def hsk_pair(src, src_spi, msg, dst, dst_spi, tag):
        fs = cocotb.start_soon(hsk_send(dut, src_spi, msg))
        fr = cocotb.start_soon(hsk_recv(dut, dst_spi, msg, tag))
        await fs
        await fr

    await hsk_pair("A", spi_a, m1, "B", spi_b, "B")
    await hsk_pair("B", spi_b, m2, "A", spi_a, "A")
    await hsk_pair("A", spi_a, m3, "B", spi_b, "B")
    await hsk_pair("B", spi_b, m4, "A", spi_a, "A")
    print("dual handshake m1-m4 done", flush=True)

    await write_sa(dut, spi_a, sa, True)
    await write_sa(dut, spi_b, sa, False)
    await ClockCycles(dut.clk, 4)

    ra = dut.u_a_node.u_spi.u_regs
    rb = dut.u_b_node.u_spi.u_regs
    for i in range(8):
        w = int.from_bytes(bytes.fromhex(sa["sk_ei"])[i * 4:i * 4 + 4], "big")
        assert (int(ra.r_key_enc.value) >> (224 - 32 * i)) & 0xFFFFFFFF == w, f"a key_enc[{i}]"
        assert (int(rb.r_key_dec.value) >> (224 - 32 * i)) & 0xFFFFFFFF == w, f"b key_dec[{i}]"
        w = int.from_bytes(bytes.fromhex(sa["sk_er"])[i * 4:i * 4 + 4], "big")
        assert (int(ra.r_key_dec.value) >> (224 - 32 * i)) & 0xFFFFFFFF == w, f"a key_dec[{i}]"
        assert (int(rb.r_key_enc.value) >> (224 - 32 * i)) & 0xFFFFFFFF == w, f"b key_enc[{i}]"
    print("dual SA loaded and verified", flush=True)

    plain = bytes((j * 7 + 3) & 0xFF for j in range(PAYLOAD))

    fa = cocotb.start_soon(feed(dut, dut.a_lan_rxd, dut.a_lan_rx_dv, dut.a_lan_rx_last,
                                dut.u_a_node.enc_s_tready, plain))
    await fa
    cb = cocotb.start_soon(collect(dut, dut.b_lan_txd, dut.b_lan_tx_en, dut.b_lan_tx_last, 1, "B->decode"))
    rx_b = await cb
    assert rx_b[0] == plain, f"A->B mismatch got={rx_b[0][:32].hex()}"

    fb = cocotb.start_soon(feed(dut, dut.b_lan_rxd, dut.b_lan_rx_dv, dut.b_lan_rx_last,
                                dut.u_b_node.enc_s_tready, plain))
    ca = cocotb.start_soon(collect(dut, dut.a_lan_txd, dut.a_lan_tx_en, dut.a_lan_tx_last, 1, "A->decode"))
    await fb
    rx_a = await ca
    assert rx_a[0] == plain, "B->A mismatch"
    print("dual handshake + both directions PASS", flush=True)


async def pipe(dut, data, tag):
    fa = cocotb.start_soon(feed(dut, dut.a_lan_rxd, dut.a_lan_rx_dv, dut.a_lan_rx_last,
                                dut.u_a_node.enc_s_tready, data))
    cb = cocotb.start_soon(collect(dut, dut.b_lan_txd, dut.b_lan_tx_en, dut.b_lan_tx_last, 1, tag,
                                   clock=dut.clk_b))
    await fa
    rx = await cb
    return rx[0]


@cocotb.test()
async def full_fw_roundtrip(dut):
    if not HAVE_FFI:
        raise AssertionError(
            f"simnode library missing {os.path.basename(DLL)}:"
            "cargo build -p kyberlink-simnode")
    spi_a, spi_b = await boot(dut)
    await cfg_gw(dut, *spi_a, MAC_A, MAC_B, IP_A, IP_B)
    await cfg_gw(dut, *spi_b, MAC_B, MAC_A, IP_B, IP_A)
    await ClockCycles(dut.clk, 10)

    fd = bytes(range(0x30, 0x50))
    fz = bytes(range(0x50, 0x70))
    nc = bytes(range(0x70, 0x90))
    seed_a = bytes(range(32))
    seed_b = bytes(range(64, 96))
    fp_a = fingerprint(seed_a)
    fp_b = fingerprint(seed_b)
    fsm_a = Fsm(seed_identity=seed_a, seed_peer=fp_b,
                seed_d=fd, seed_z=fz, nonce=nc)
    fsm_b = Fsm(seed_identity=seed_b, seed_peer=fp_a,
                seed_d=fd, seed_z=fz, nonce=nc)
    try:
        done = [False, False]
        nspi = [0, 0]
        nblk = [0, 0]
        last = [None, None]
        for it in range(FFI_ITERS):
            if not done[0] and fsm_a.poll() == 1:
                done[0] = True
            for addr, data in fsm_a.take_writes():
                await spi_write(dut, *spi_a, addr, data)
                nspi[0] += 1
            st = await spi_read(dut, *spi_b, 0x04)
            nspi[0] += 1
            fsm_b.set_status(st)
            if st & 1:
                blk = await hsk_read_raw(dut, spi_b)
                nspi[1] += 1 + (len(blk) + 3) // 4
                nblk[0] += 1
                last[0] = (int.from_bytes(blk[0:4], "big"),
                           int.from_bytes(blk[4:8], "big"))
                fsm_b.push_rx(blk)

            if not done[1] and fsm_b.poll() == 1:
                done[1] = True
            for addr, data in fsm_b.take_writes():
                await spi_write(dut, *spi_b, addr, data)
                nspi[1] += 1
            st = await spi_read(dut, *spi_a, 0x04)
            nspi[1] += 1
            fsm_a.set_status(st)
            if st & 1:
                blk = await hsk_read_raw(dut, spi_a)
                nspi[0] += 1 + (len(blk) + 3) // 4
                nblk[1] += 1
                last[1] = (int.from_bytes(blk[0:4], "big"),
                           int.from_bytes(blk[4:8], "big"))
                fsm_a.push_rx(blk)

            if all(done):
                break
            await ClockCycles(dut.clk, IDLE_CLOCKS)
        assert all(done), (
            f"handshake not complete via FW Fsm: it={it} done={done} "
            f"blk_to_b={nblk[0]} blk_to_a={nblk[1]} last={last} nspi={nspi}")
        assert sorted([fsm_a.role(), fsm_b.role()]) == [1, 2], (
            f"role pair {fsm_a.role()} {fsm_b.role()}")

        for f, spi in ((fsm_a, spi_a), (fsm_b, spi_b)):
            while True:
                w = f.take_writes()
                if not w:
                    break
                for addr, data in w:
                    await spi_write(dut, *spi, addr, data)

        plain = bytes((j * 7 + 3) & 0xFF for j in range(PAYLOAD))
        fa = cocotb.start_soon(feed(dut, dut.a_lan_rxd, dut.a_lan_rx_dv, dut.a_lan_rx_last,
                                    dut.u_a_node.enc_s_tready, plain))
        cb = cocotb.start_soon(collect(dut, dut.b_lan_txd, dut.b_lan_tx_en, dut.b_lan_tx_last, 1, "FW A->B"))
        await fa
        rx_b = await cb
        assert rx_b[0] == plain, f"FW A->B len {len(rx_b[0])} vs {len(plain)}"
        print("FW roundtrip A->B PASS", flush=True)

        fb = cocotb.start_soon(feed(dut, dut.b_lan_rxd, dut.b_lan_rx_dv, dut.b_lan_rx_last,
                                    dut.u_b_node.enc_s_tready, plain))
        ca = cocotb.start_soon(collect(dut, dut.a_lan_txd, dut.a_lan_tx_en, dut.a_lan_tx_last, 1, "FW B->A"))
        await fb
        rx_a = await ca
        assert rx_a[0] == plain, "FW B->A mismatch"
        print("FW roundtrip B->A PASS", flush=True)
    finally:
        fsm_a.close()
        fsm_b.close()


@cocotb.test()
async def dual_simultaneous_start(dut):
    if not HAVE_FFI:
        raise AssertionError(
            f"simnode library missing {os.path.basename(DLL)}:"
            "cargo build -p kyberlink-simnode")
    spi_a, spi_b = await boot(dut)
    await cfg_gw(dut, *spi_a, MAC_A, MAC_B, IP_A, IP_B)
    await cfg_gw(dut, *spi_b, MAC_B, MAC_A, IP_B, IP_A)
    await ClockCycles(dut.clk, 10)

    fd = bytes(range(0x30, 0x50))
    fz = bytes(range(0x50, 0x70))
    nc = bytes(range(0x70, 0x90))
    seed_a = bytes(range(32))
    seed_b = bytes(range(64, 96))
    fp_a = fingerprint(seed_a)
    fp_b = fingerprint(seed_b)
    fsm_a = Fsm(seed_identity=seed_a, seed_peer=fp_b, seed_d=fd, seed_z=fz, nonce=nc)
    fsm_b = Fsm(seed_identity=seed_b, seed_peer=fp_a, seed_d=fd, seed_z=fz, nonce=nc)
    try:
        fsm_a.poll()
        fsm_b.poll()
        assert fsm_a.role() == 1 and fsm_b.role() == 1, (
            f"both must open as initiator got {fsm_a.role()} {fsm_b.role()}")
        for addr, data in fsm_a.take_writes():
            await spi_write(dut, *spi_a, addr, data)
        for addr, data in fsm_b.take_writes():
            await spi_write(dut, *spi_b, addr, data)

        done = [False, False]
        for it in range(FFI_ITERS):
            if not done[0] and fsm_a.poll() == 1:
                done[0] = True
            for addr, data in fsm_a.take_writes():
                await spi_write(dut, *spi_a, addr, data)
            st = await spi_read(dut, *spi_b, 0x04)
            fsm_b.set_status(st)
            if st & 1:
                fsm_b.push_rx(await hsk_read_raw(dut, spi_b))

            if not done[1] and fsm_b.poll() == 1:
                done[1] = True
            for addr, data in fsm_b.take_writes():
                await spi_write(dut, *spi_b, addr, data)
            st = await spi_read(dut, *spi_a, 0x04)
            fsm_a.set_status(st)
            if st & 1:
                fsm_a.push_rx(await hsk_read_raw(dut, spi_a))

            if all(done):
                break
            await ClockCycles(dut.clk, IDLE_CLOCKS)
        assert all(done), (
            f"simultaneous start stuck: it={it} done={done} "
            f"role_a={fsm_a.role()} role_b={fsm_b.role()}")
        assert (fsm_a.role() == 1) == (fp_a < fp_b), (
            f"tie-break mismatch role_a={fsm_a.role()} role_b={fsm_b.role()} "
            f"fp_a_lt_b={fp_a < fp_b}")

        for f, spi in ((fsm_a, spi_a), (fsm_b, spi_b)):
            while True:
                w = f.take_writes()
                if not w:
                    break
                for addr, data in w:
                    await spi_write(dut, *spi, addr, data)

        plain = bytes((j * 7 + 3) & 0xFF for j in range(PAYLOAD))
        fa = cocotb.start_soon(feed(dut, dut.a_lan_rxd, dut.a_lan_rx_dv, dut.a_lan_rx_last,
                                    dut.u_a_node.enc_s_tready, plain))
        cb = cocotb.start_soon(collect(dut, dut.b_lan_txd, dut.b_lan_tx_en, dut.b_lan_tx_last, 1, "tie A->B"))
        await fa
        rx_b = await cb
        assert rx_b[0] == plain, f"tie A->B len {len(rx_b[0])} vs {len(plain)}"
        print("simultaneous start tie-break PASS", flush=True)
    finally:
        fsm_a.close()
        fsm_b.close()


@cocotb.test()
async def dual_short_hsk(dut):
    spi_a, spi_b = await boot(dut)
    await cfg_gw(dut, *spi_a, MAC_A, MAC_B, IP_A, IP_B)
    await cfg_gw(dut, *spi_b, MAC_B, MAC_A, IP_B, IP_A)
    await ClockCycles(dut.clk, 10)
    msg = bytes(range(0xA0, 0xA8))
    fs = cocotb.start_soon(hsk_send(dut, spi_a, msg))
    fr = cocotb.start_soon(hsk_recv(dut, spi_b, msg, "short"))
    await fs
    await fr
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
                       dut.u_a_node.enc_s_tready, bytes([k]) + blk)
            await ClockCycles(dut.clk, 2000)

    f = cocotb.start_soon(flood())
    await ClockCycles(dut.clk, 4000)
    fs = cocotb.start_soon(hsk_send(dut, spi_a, msg))
    fr = cocotb.start_soon(hsk_recv(dut, spi_b, msg, "conc"))
    await fs
    await fr
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
    await ClockCycles(dut.clk, 4000)
    rx = await pipe(dut, bytes([0x5A]) + plain, "rekey r2")
    assert rx == bytes([0x5A]) + plain, "rekey pre 2"
    await ClockCycles(dut.clk, 4000)
    await write_sa(dut, spi_a, sa, True)
    await write_sa(dut, spi_b, sa, False)
    await ClockCycles(dut.clk, 4)
    rx = await pipe(dut, bytes([0xA5]) + plain, "rekey post")
    assert rx == bytes([0xA5]) + plain, f"rekey post mismatch got={rx[:32].hex()}"
    print("dual rekey PASS", flush=True)


@cocotb.test()
async def soft_rst_full_roundtrip(dut):
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
    rx = await pipe(dut, plain, "soft rst pre")
    assert rx == plain, f"pre rst {len(rx)} vs {len(plain)}"

    await spi_write(dut, *spi_a, 0x00, 4)
    await ClockCycles(dut.clk, 2)
    await spi_write(dut, *spi_b, 0x00, 4)
    await ClockCycles(dut.clk, 2)

    rx = await pipe(dut, plain, "soft rst post")
    assert rx == plain, f"post rst mismatch got={rx[:32].hex()}"
    print("soft_rst_full_roundtrip PASS", flush=True)


@cocotb.test()
async def error_inject_full(dut):
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
    rx = await pipe(dut, plain, "err pre")
    assert rx == plain, "pre clean"

    esp = bytearray()
    async def wan_watch():
        for _ in range(30000):
            if int(dut.a_tx_en.value):
                esp.append(int(dut.a_txd.value))
                if int(dut.a_tx_last.value):
                    return
            await ClockCycles(dut.clk, 1)
        raise AssertionError("a wan no output")

    w = cocotb.start_soon(wan_watch())
    plain2 = bytes((j * 3 + 1) & 0xFF for j in range(200))
    await feed(dut, dut.a_lan_rxd, dut.a_lan_rx_dv, dut.a_lan_rx_last,
               dut.u_a_node.enc_s_tready, plain2)
    await w
    esp = bytes(esp)
    assert len(esp) > 58, f"esp too short {len(esp)}"
    k = esp.find(MAC_B.to_bytes(6, "big"), 0, 64)
    assert k >= 0, f"esp head not found {esp[:32].hex()}"
    esp = esp[k:]
    assert len(esp) > 58, f"esp too short {len(esp)}"

    bad = bytearray(esp)
    bad[-1] ^= 0xFF
    await ClockCycles(dut.clk, 100)

    bad = bytearray(esp)
    bad[46:50] = (0x12345678).to_bytes(4, "big")
    bad[-1] ^= 0xFF

    async def inject(frame):
        for j, b in enumerate(frame):
            dut.b_inject_tdata.value = b
            dut.b_inject_tvalid.value = 1
            dut.b_inject_tlast.value = 1 if j == len(frame) - 1 else 0
            dut.b_inject_en.value = 1
            await ClockCycles(dut.clk, 1)
        dut.b_inject_tvalid.value = 0
        dut.b_inject_tlast.value = 0
        dut.b_inject_en.value = 0
        await ClockCycles(dut.clk, 100)

    await inject(bytes(bad))
    await ClockCycles(dut.clk, 100)
    ra = dut.u_a_node.u_spi.u_regs
    a_src = {int(ra.r_src_mac_hi.value), int(ra.r_src_mac_lo.value)}
    a_dst = {int(ra.r_dst_mac_hi.value), int(ra.r_dst_mac_lo.value)}
    print(f"DIAG a_src_mac={a_src} a_dst_mac={a_dst}", flush=True)
    print(f"DIAG inj_len={len(bad)} head42={bytes(bad[:42]).hex()}", flush=True)

    async def wait_idle():
        for _ in range(200000):
            if int(dut.u_b_node.u_bridge.u_dec.ds.value) == 0 and \
               int(dut.u_b_node.u_bridge.u_dec.dec_pend.value) == 0:
                return
            await ClockCycles(dut.clk, 1)
        raise AssertionError("dec never idle")

    await wait_idle()

    st = await spi_read(dut, *spi_b, 0x50)
    assert st & 0x1, f"badtag not set {st:08x}"
    print("error_inject_full PASS (badtag set)", flush=True)


@cocotb.test()
async def async_clk_roundtrip(dut):
    spi_a, spi_b = await boot(dut, clk_b_period=8.15)
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
    rx = await pipe(dut, plain, "async clk")
    assert rx == plain, f"async clk mismatch got={rx[:32].hex()}"
    print("async_clk_roundtrip PASS", flush=True)
