import json
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge, ReadOnly

from tb_dual_rgmii import cfg_gw, write_sa, VEC

PAYLOAD = 200
MAC_A = 0xAABBCC000001
MAC_B = 0xAABBCC000002
IP_A = 0xC0A80101
IP_B = 0xC0A80202


def _eth_wrap(payload):
    import zlib
    body = payload
    if len(body) < 60:
        body = body + b"\x00" * (60 - len(body))
    return b"\x55" * 7 + b"\xd5" + body + zlib.crc32(body).to_bytes(4, "little")


def _eth_strip(frame):
    assert frame[:7] == b"\x55" * 7 and frame[7] == 0xD5, "no preamble"
    return frame[8:-4]


async def feed_rgmii(dut, rxd, ctl, frame):
    for _ in range(20):
        await RisingEdge(dut.clk)
    for j, b in enumerate(frame):
        await FallingEdge(dut.clk)
        ctl.value = 1
        rxd.value = b & 0xF
        await RisingEdge(dut.clk)
        rxd.value = (b >> 4) & 0xF
        ctl.value = 1
    await FallingEdge(dut.clk)
    ctl.value = 0
    rxd.value = 0
    await RisingEdge(dut.clk)


async def collect_rgmii(dut, txd, ctl, tag, nframes=1, max_idle=400000, dbg=0):
    frames = []
    out = bytearray()
    idle = 0
    pair = []
    while len(frames) < nframes:
        await FallingEdge(dut.clk)
        if int(ctl.value) == 0:
            if out:
                frames.append(bytes(out))
                out = bytearray()
                idle = 0
                continue
            idle += 1
            if idle > max_idle:
                for fi, fr in enumerate(frames):
                    print(f"ESPF{fi} len={len(fr)} head40={fr[:40].hex()} tail8={fr[-8:].hex()}", flush=True)
                try:
                    ml = dut.u_dut.u_mac_lan
                    mw = dut.u_dut.u_mac_wan
                    print(f"DBG lan_uf={int(ml.tx_error_underflow.value)} lan_of={int(ml.tx_fifo_overflow.value)} lan_rob={int(ml.rx_fifo_bad_frame.value)} "
                          f"wan_uf={int(mw.tx_error_underflow.value)} wan_of={int(mw.tx_fifo_overflow.value)} wan_rob={int(mw.rx_fifo_bad_frame.value)} "
                          f"wan_rog={int(mw.rx_fifo_good_frame.value)} lag={int(ml.tx_fifo_good_frame.value)}", flush=True)
                except Exception as e:
                    print("DBG probe fail", e, flush=True)
                raise TimeoutError(f"{tag} frame wait timeout got {len(frames)}")
            continue
        lo = int(txd.value)
        await RisingEdge(dut.clk)
        hi = int(txd.value)
        if dbg and len(out) < dbg:
            pair.append(f"{lo:x}/{hi:x}")
        out.append((hi << 4) | lo)
        idle = 0
    if dbg:
        dut._log.info(f"{tag} nibble pairs: {' '.join(pair)}")
    return frames


async def _probe_gmii(dut, n=60000):
    dv = 0
    md = 0
    ds = 0
    ok = 0
    dsl = 0
    dsr = 0
    dst = 0
    lr = 0
    le = 0
    dec = dut.u_dut.u_core.u_bridge.u_dec
    rx = dut.u_dut.u_core.u_rx_wan
    lan_bytes = []
    for _ in range(n):
        await RisingEdge(dut.clk)
        if int(dut.u_dut.lan_tx_en.value) and len(lan_bytes) < 8:
            lan_bytes.append(int(dut.u_dut.lan_txd.value))
        if int(dut.u_dut.wan_rx_dv.value):
            dv += 1
        if int(rx.m_data_tvalid.value):
            md += 1
        if int(dec.rx_state.value) != 0 or int(dec.ds.value) != 0:
            ds += 1
        if int(dec.ds.value) == 1:
            dsl += 1
        elif int(dec.ds.value) == 2:
            dsr += 1
        elif int(dec.ds.value) == 3:
            dst += 1
        if int(dut.u_dut.u_core.tag_ok.value):
            ok += 1
        if int(dut.u_dut.lan_tx_ready.value):
            lr += 1
        if int(dut.u_dut.lan_tx_en.value):
            le += 1
    print(f"PROBE lan_txd_head={[hex(b) for b in lan_bytes]}", flush=True)
    return dv, md, ds, ok, dsl, dsr, dst, lr, le


async def boot(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    dut.lan_rgmii_rxd.value = 0
    dut.lan_rgmii_rx_ctl.value = 0
    dut.wan_rgmii_rxd.value = 0
    dut.wan_rgmii_rx_ctl.value = 0
    dut.spi_sck.value = 0
    dut.spi_mosi.value = 0
    dut.spi_csn.value = 1
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    return (dut.spi_sck, dut.spi_mosi, dut.spi_miso, dut.spi_csn)


@cocotb.test()
async def kyberlink_loopback(dut):
    spi = await boot(dut)
    await cfg_gw(dut, *spi, MAC_A, MAC_A, IP_A, IP_A)
    await ClockCycles(dut.clk, 10)
    with open(VEC) as f:
        vec = json.load(f)[0]
    await write_sa(dut, spi, vec["initiator"]["sa"], True)
    await ClockCycles(dut.clk, 4)

    plain = bytes((j * 7 + 3) & 0xFF for j in range(PAYLOAD))
    feed_t = cocotb.start_soon(feed_rgmii(dut, dut.lan_rgmii_rxd, dut.lan_rgmii_rx_ctl, _eth_wrap(plain)))
    esp_frames = await collect_rgmii(dut, dut.wan_rgmii_txd, dut.wan_rgmii_tx_ctl, "esp", nframes=1, dbg=8)
    await feed_t
    esp = max(esp_frames, key=len)
    print(f"ESP0 len={len(esp_frames[0])} head32={esp_frames[0][:32].hex()} tail8={esp_frames[0][-8:].hex()}", flush=True)
    assert len(esp) > 200, f"esp too short frames={[len(f) for f in esp_frames]}"
    print(f"kyberlink enc esp_len={len(esp)} head16={esp[:16].hex()}", flush=True)
    sa = vec["initiator"]["sa"]
    import itertools
    from Crypto.Cipher import AES
    k = bytes.fromhex(sa["sk_ei"])
    seqb = int.from_bytes(esp[54:58], "big").to_bytes(4, "big")
    salt = bytes.fromhex(sa["sa_salt"])[:8]
    spib = int.from_bytes(bytes.fromhex(sa["spi_i"]), "big").to_bytes(4, "big")
    hit = None
    for off, nk, ka in itertools.product((66, 58), ("s+q", "q+s"), ("a", "n")):
        nonce = (salt + seqb) if nk == "s+q" else (seqb + salt)
        aad = (spib + seqb + b"\x00" * 8) if ka == "a" else None
        cc = AES.new(k, AES.MODE_GCM, nonce=nonce)
        if aad:
            cc.update(aad)
        try:
            ppt = cc.decrypt_and_verify(esp[off:-20], esp[-20:-4])
            hit = (off, nk, ka, len(ppt), ppt[-8:].hex())
            break
        except ValueError:
            pass
    if hit:
        print(f"PYDEC HIT off={hit[0]} n={hit[1]} aad={hit[2]} len={hit[3]} tail={hit[4]}", flush=True)
        print(f"        exp_tail={plain[-8:].hex()}", flush=True)
    else:
        print(f"PYDEC MISS esp_len={len(esp)}", flush=True)
        import os as _os
        with open(_os.path.join(_os.getcwd(), "esp_dump.txt"), "w") as ef:
            ef.write(esp.hex())
        print("  esp dumped to esp_dump.txt", flush=True)

    # 回注帧 = 对端(responder)用 sk_er 加密的同明文帧, 复用原帧 MAC/IP/UDP 壳与 FCS
    k_er = bytes.fromhex(sa["sk_er"])
    spi_rb = int.from_bytes(bytes.fromhex(sa["spi_r"]), "big").to_bytes(4, "big")
    seq_b = esp[54:58]
    ptq = plain + bytes(6) + b"\x06\x04"
    nonce12 = seq_b + salt
    cc = AES.new(k_er, AES.MODE_GCM, nonce=nonce12)
    cc.update(spi_rb + seq_b)
    payload = spi_rb + seq_b + nonce12 + cc.encrypt(ptq) + cc.digest()
    back_frame = esp[:50] + payload + esp[-4:]
    assert len(back_frame) == len(esp), f"back frame len {len(back_frame)} != {len(esp)}"
    print(f"BACK ct_tail16={payload[20+208-16:20+208].hex()} iv={nonce12.hex()} spi={spi_rb.hex()}", flush=True)

    back_t = cocotb.start_soon(feed_rgmii(dut, dut.wan_rgmii_rxd, dut.wan_rgmii_rx_ctl, back_frame))
    probe = cocotb.start_soon(_probe_gmii(dut))
    try:
        plain_frames = await collect_rgmii(dut, dut.lan_rgmii_txd, dut.lan_rgmii_tx_ctl, "plain", nframes=1, max_idle=50000, dbg=8)
    except TimeoutError:
        core = dut.u_dut.u_core
        dec = core.u_bridge.u_dec
        wandv = await probe
        dut._log.info(
            f"DIAG2 tag_ok={int(dut.tag_ok.value)} "
            f"bt={int(core.err_badtag_w.value)} bp={int(core.err_badpad_w.value)} "
            f"rp={int(core.err_replay_w.value)} drop={int(core.err_rxdrop_w.value)} "
            f"wandv={wandv} "
            f"ds={int(dec.ds.value)} ts={int(dec.ts.value)} pend={int(dec.dec_pend.value)} "
            f"req={int(dec.gcm_req.value)} grt={int(dec.gcm_grant.value)} "
            f"gp={int(core.u_bridge.u_gcm.phase.value)} gb={int(core.u_bridge.gcm_busy.value)} "
            f"de={int(core.u_bridge.dec_own.value)} mv={int(dec.m_tvalid_r.value)} "
            f"av={int(dec.ct_avail.value)} lanrdy={int(dut.u_dut.lan_tx_ready.value)} "
            f"lanen={int(dut.u_dut.lan_tx_en.value)}"
        )
        raise
    await back_t
    _f = max(plain_frames, key=len)
    print(f"RXF len={len(_f)} head24={_f[:24].hex()} tail8={_f[-8:].hex()}", flush=True)
    rxp = _eth_strip(_f)
    await probe
    assert rxp == plain, f"dec mismatch len={len(rxp)} vs {len(plain)}"
    print("kyberlink loopback PASS", flush=True)
