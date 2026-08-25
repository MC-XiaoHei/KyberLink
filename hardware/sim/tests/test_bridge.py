import json
import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer
from Crypto.Cipher import AES


VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "..", "vectors", "generated")

SRC_MAC = bytes.fromhex("020000000101")
DST_MAC = bytes.fromhex("020000000102")
SRC_IP = bytes.fromhex("0a000001")
DST_IP = bytes.fromhex("0a000002")
SRC_PORT = 4500
DST_PORT = 4500


def crc32(data):
    crc = 0xFFFFFFFF
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ (0xEDB88320 if crc & 1 else 0)
    return (~crc) & 0xFFFFFFFF


def build_eth(payload, src_mac=SRC_MAC, dst_mac=DST_MAC):
    return dst_mac + src_mac + bytes([0x08, 0x00]) + payload


def build_esp_frame(key, iv, spi, seq, plain, aad):
    pad = (16 - ((len(plain) + 2) & 0xF)) & 0xF
    pt = plain + b"\x00" * pad + bytes([pad]) + b"\x04"
    nonce = seq + iv[:8]
    aes = AES.new(key, AES.MODE_GCM, nonce=nonce)
    aes.update(aad)
    ct_tag = aes.encrypt(pt) + aes.digest()
    ct = ct_tag[:-16]
    tag = ct_tag[-16:]
    esp = spi + seq + nonce + ct + tag
    udp_len = 8 + len(esp)
    total_len = 20 + udp_len
    udp = (SRC_PORT.to_bytes(2, "big") + DST_PORT.to_bytes(2, "big") +
           udp_len.to_bytes(2, "big") + b"\x00\x00" + esp)
    ip = bytearray(bytes([0x45, 0x00]) + total_len.to_bytes(2, "big") + b"\x00\x00" +
                   bytes([0x40, 0x00, 0x40, 0x11]) + b"\x00\x00" + SRC_IP + DST_IP)
    s = 0
    for i in range(0, len(ip), 2):
        s += (ip[i] << 8) | ip[i + 1]
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    ip[10:12] = ((~s) & 0xFFFF).to_bytes(2, "big")
    udp = bytes(udp)
    return DST_MAC + SRC_MAC + bytes([0x08, 0x00]) + bytes(ip) + udp
    udp_len = 8 + len(esp)
    total_len = 20 + udp_len
    udp = (SRC_PORT.to_bytes(2, "big") + DST_PORT.to_bytes(2, "big") +
           udp_len.to_bytes(2, "big") + b"\x00\x00" + esp)
    ip = bytearray(bytes([0x45, 0x00]) + total_len.to_bytes(2, "big") + b"\x00\x00" +
                   bytes([0x40, 0x00, 0x40, 0x11]) + b"\x00\x00" + SRC_IP + DST_IP)
    s = 0
    for i in range(0, len(ip), 2):
        s += (ip[i] << 8) | ip[i + 1]
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    ip[10:12] = ((~s) & 0xFFFF).to_bytes(2, "big")
    return DST_MAC + SRC_MAC + bytes([0x08, 0x00]) + ip + udp


def mac_ref(dut, name):
    return getattr(dut, name)


async def rgmii_drive(dut, clk_sig, rxd_sig, ctl_sig, gmii_bytes):
    for b in gmii_bytes:
        rxd_sig.value = b & 0xF
        ctl_sig.value = 1
        await RisingEdge(clk_sig)
        rxd_sig.value = (b >> 4) & 0xF
        ctl_sig.value = 1
        await FallingEdge(clk_sig)
    ctl_sig.value = 0
    await RisingEdge(clk_sig)
    ctl_sig.value = 0
    await FallingEdge(clk_sig)


async def rgmii_drive_skew(dut, clk_sig, rxd_sig, ctl_sig, gmii_bytes, skew_ns):
    period = 8.0
    await RisingEdge(clk_sig)
    rxd_sig.value = gmii_bytes[0] & 0xF
    ctl_sig.value = 1
    prev = 0.0
    for i, b in enumerate(gmii_bytes):
        if i > 0:
            hi_t = period * i - skew_ns
            await Timer(hi_t - prev, unit="ns")
            rxd_sig.value = b & 0xF
            ctl_sig.value = 1
            prev = hi_t
        lo_t = period * i + period / 2 - skew_ns
        await Timer(lo_t - prev, unit="ns")
        rxd_sig.value = (b >> 4) & 0xF
        ctl_sig.value = 1
        prev = lo_t
    await Timer(period / 2, unit="ns")
    rxd_sig.value = 0
    ctl_sig.value = 0


async def tx_collect(dut, tv, td, tl, max_cyc):
    out = bytearray()
    for _ in range(max_cyc):
        await RisingEdge(dut.clk)
        if int(tv.value):
            out.append(int(td.value))
            if int(tl.value):
                break
    return bytes(out)


async def reset_dut(dut):
    dut.rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(5):
        await RisingEdge(dut.clk)
    await Timer(1, unit="ns")



async def run_loopback(dut, skew_ns, payload_len=242):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    cocotb.start_soon(Clock(dut.gtx_clk, 8, unit="ns").start())
    cocotb.start_soon(Clock(dut.wan_rgmii_rx_clk, 8, unit="ns").start())
    cocotb.start_soon(Clock(dut.lan_rgmii_rx_clk, 8, unit="ns").start())

    async def _clk90():
        await Timer(2, unit="ns")
        while True:
            dut.gtx_clk90.value = 1
            await Timer(4, unit="ns")
            dut.gtx_clk90.value = 0
            await Timer(4, unit="ns")

    cocotb.start_soon(_clk90())
    dut.wan_rgmii_rxd.value = 0
    dut.wan_rgmii_rx_ctl.value = 0
    dut.lan_rgmii_rxd.value = 0
    dut.lan_rgmii_rx_ctl.value = 0
    await reset_dut(dut)

    with open(os.path.join(VECDIR, "esp.json")) as f:
        v = json.load(f)[0]
    key = bytes.fromhex(v["key"])
    spi = bytes.fromhex(v["spi"])
    iv = bytes.fromhex(v["iv"])
    seq = (0x11223344).to_bytes(4, "big")
    aad = spi + seq

    dut.enc_key.value = int(v["key"], 16)
    dut.dec_key.value = int(v["key"], 16)
    dut.enc_spi.value = int(v["spi"], 16)
    dut.enc_salt.value = int(v["iv"], 16)
    dut.enc_seq0.value = int.from_bytes(seq, "big")
    dut.dec_spi.value = int(v["spi"], 16)
    dut.dec_salt.value = int(v["iv"], 16)
    dut.dec_seq0.value = 0
    dut.sa_en.value = 3
    dut.cfg_src_mac.value = int.from_bytes(SRC_MAC, "big")
    dut.cfg_dst_mac.value = int.from_bytes(DST_MAC, "big")
    dut.cfg_src_ip.value = int.from_bytes(SRC_IP, "big")
    dut.cfg_dst_ip.value = int.from_bytes(DST_IP, "big")
    dut.cfg_src_port.value = SRC_PORT
    dut.cfg_dst_port.value = DST_PORT
    await RisingEdge(dut.clk)

    payload = bytes((i * 3 + 1) % 256 for i in range(payload_len))
    lan_frame = build_eth(payload)
    fcs = crc32(lan_frame).to_bytes(4, "little")
    gmii_lan = b"\x55" * 7 + b"\xd5" + lan_frame + fcs

    exp_wan = build_esp_frame(key, iv, spi, seq, lan_frame, aad)
    exp_fcs = crc32(exp_wan).to_bytes(4, "little")
    gmii_wan = b"\x55" * 7 + b"\xd5" + exp_wan + exp_fcs

    dut._log.info(f"lan_frame={len(lan_frame)}B exp_wan={len(exp_wan)}B")
    wm = dut.u_wan_mac
    lm = dut.u_lan_mac
    await rgmii_drive_skew(dut, dut.lan_rgmii_rx_clk, dut.lan_rgmii_rxd,
                           dut.lan_rgmii_rx_ctl, gmii_lan, skew_ns)
    po = bytearray()
    for _ in range(20000):
        await RisingEdge(dut.clk)
        if int(dut.u_lan_pipe.m_tvalid.value) and int(dut.u_lan_pipe.m_tready.value):
            po.append(int(dut.u_lan_pipe.m_tdata.value))
        if len(po) >= 6:
            break
    assert bytes(po) == lan_frame[:6], f"lan pipe head {po.hex()} exp {lan_frame[:6].hex()}"
    wan_body = await tx_collect(dut, dut.u_enc.m_tvalid, dut.u_enc.m_tdata, dut.u_enc.m_tlast, 40000)
    if wan_body != exp_wan:
        for i in range(min(len(wan_body), len(exp_wan))):
            if wan_body[i] != exp_wan[i]:
                dut._log.error(f'first diff @{i} got={wan_body[i]:02x} exp={exp_wan[i]:02x}')
                dut._log.error(f'got={wan_body[max(0,i-8):i+16].hex()}')
                dut._log.error(f'exp={exp_wan[max(0,i-8):i+16].hex()}')
                break
        dut._log.error(f'len got={len(wan_body)} exp={len(exp_wan)}')
        assert False, "wan enc mismatch"
    dut._log.info("wan enc OK")
    await rgmii_drive_skew(dut, dut.wan_rgmii_rx_clk, dut.wan_rgmii_rxd,
                           dut.wan_rgmii_rx_ctl, gmii_wan, skew_ns)
    di = bytearray()
    macb = bytearray()
    mac_last_at = None
    for i in range(100000):
        await RisingEdge(dut.clk)
        if int(dut.u_wan_mac.rx_axis_tvalid.value) and int(dut.u_wan_mac.rx_axis_tready.value):
            macb.append(int(dut.u_wan_mac.rx_axis_tdata.value))
            if int(dut.u_wan_mac.rx_axis_tlast.value):
                mac_last_at = len(macb)
                break
        if int(dut.u_dec.s_tvalid.value) and int(dut.u_dec.s_tready.value):
            di.append(int(dut.u_dec.s_tdata.value))
        if int(dut.u_dec.s_tlast.value):
            break
    dut._log.info(f"mac rx out {len(macb)}B last_at={mac_last_at} (frame {len(exp_wan)}B)")
    dut._log.info(f"dec input {len(di)}B (exp esp payload {len(exp_wan)-42}B)")
    lan_body = await tx_collect(dut, dut.u_dec.m_tvalid, dut.u_dec.m_tdata, dut.u_dec.m_tlast, 40000)
    dut._log.info(f"lan tx {len(lan_body)}B")
    await Timer(3000, unit="ns")
    assert int(dut.u_dec.tag_ok_r.value) == 1, "dec tag mismatch"
    dut._log.info("dec tag OK")
    assert lan_body is not None, "lan no frame"
    if lan_body != lan_frame:
        dut._log.error(f"LAN MISMATCH got={lan_body[:40].hex()} exp={lan_frame[:40].hex()}")
        assert False, "lan dec mismatch"
    dut._log.info("lan dec OK")


@cocotb.test()
async def test_bridge_loopback(dut):
    await run_loopback(dut, 0.0)


@cocotb.test()
async def test_bridge_rx_skew_15(dut):
    await run_loopback(dut, 1.5)


@cocotb.test()
async def test_bridge_rx_skew_20(dut):
    await run_loopback(dut, 2.0)


@cocotb.test()
async def test_bridge_mtu1500(dut):
    await run_loopback(dut, 0.0, 1500)
