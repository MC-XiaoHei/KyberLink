import json
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, ReadOnly, Timer

PAYLOAD = 1400
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


async def hsk_send(dut, spi, data):
    sck, mosi, miso, csn = spi
    await spi_write(dut, sck, mosi, miso, csn, 0x3C, len(data))
    for chunk in (data[i:i + 4] for i in range(0, len(data), 4)):
        w = int.from_bytes(chunk + b"\x00" * (4 - len(chunk)), "big")
        await spi_write(dut, sck, mosi, miso, csn, 0x40, w)
    await spi_write(dut, sck, mosi, miso, csn, 0x00, 1 << 1)


async def hsk_recv(dut, spi, expect, tag):
    sck, mosi, miso, csn = spi
    got = bytearray()
    for _ in range(600):
        st = await spi_read(dut, sck, mosi, miso, csn, 0x04)
        if st & 1:
            break
        for _ in range(200):
            await ClockCycles(dut.clk, 1)
    else:
        raise TimeoutError(f"{tag} hsk recv timeout")
    ln = await spi_read(dut, sck, mosi, miso, csn, 0x34) & 0xFFFF
    for _ in range((ln + 3) // 4):
        w = await spi_read(dut, sck, mosi, miso, csn, 0x38)
        got += w.to_bytes(4, "big")
    got = bytes(got[:ln])
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
            elif out:
                waits += 1
                if waits > 20000:
                    raise TimeoutError(f"{tag} frame tail timeout")
            else:
                waits += 1
                if waits > 200000:
                    raise TimeoutError(f"{tag} frame wait timeout")
            await ClockCycles(dut.clk, 1)
        frames.append(bytes(out))
    return frames


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
        for _ in range(400000):
            await ClockCycles(dut.clk, 1)
            if int(dut.a_tx_en.value):
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
    print(f"ALIGN200 ok={bytes(got) == plain}", flush=True)
    print(f"ESP len={len(esp)} spi={esp[42:46].hex()} seq={esp[46:50].hex()}", flush=True)
    from Crypto.Cipher import AES
    key = bytes.fromhex(sa["sk_ei"])
    seq = int.from_bytes(esp[46:50], "big")
    salt = bytes.fromhex(sa["sa_salt"])[:8]
    nonce = salt + seq.to_bytes(4, "big")
    aad = int.from_bytes(bytes.fromhex(sa["spi_i"]), "big").to_bytes(4, "big") + seq.to_bytes(4, "big") + b"\x00" * 8
    body = esp[58:-16]
    tag = esp[-16:]
    seqb = seq.to_bytes(4, "big")
    saltb = salt
    import itertools
    for kn, nb, kb, ab in itertools.product(
            ("e",), 
            ("s+q","q+s","s8q"), 
            ("ei","er"), 
            ("std",)):
        k = bytes.fromhex(sa["sk_ei"]) if kb=="ei" else bytes.fromhex(sa["sk_er"])
        if nb == "s+q": n2 = saltb + seqb
        elif nb == "q+s": n2 = seqb + saltb
        else: n2 = seqb + saltb[:8]
        a2 = int.from_bytes(bytes.fromhex(sa["spi_i"]), "big").to_bytes(4, "big") + seqb + b"\x00" * 8
        try:
            cc = AES.new(k, AES.MODE_GCM, nonce=n2)
            cc.update(a2)
            ppt = cc.decrypt_and_verify(body, tag)
            print(f"PYDEC HIT k={kb} n={nb} aad={ab} len={len(ppt)} tail={ppt[-8:].hex()}", flush=True)
            print(f"        exp tail={plain[-8:].hex()}", flush=True)
            break
        except ValueError:
            pass
    else:
        print(f"PYDEC all fail len={len(esp)} bodylen={len(body)}", flush=True)
        print(f"  head58={bytes(esp[:58]).hex()}", flush=True)


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

    await hsk_send(dut, spi_a, m1)
    await hsk_recv(dut, spi_b, m1, "B")
    await hsk_send(dut, spi_b, m2)
    await hsk_recv(dut, spi_a, m2, "A")
    await hsk_send(dut, spi_a, m3)
    await hsk_recv(dut, spi_b, m3, "B")
    await hsk_send(dut, spi_b, m4)
    await hsk_recv(dut, spi_a, m4, "A")
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
                       dut.u_a_node.enc_s_tready, bytes([k]) + blk)
            await ClockCycles(dut.clk, 2000)

    f = cocotb.start_soon(flood())
    await ClockCycles(dut.clk, 4000)
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
