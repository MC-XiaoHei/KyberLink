import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer

SRC_MAC = bytes.fromhex("020000000101")
DST_MAC = bytes.fromhex("020000000102")
SRC_IP = bytes.fromhex("0a000001")
DST_IP = bytes.fromhex("0a000002")


def build_udp(dst_mac, src_mac, payload):
    udp = (4501).to_bytes(2, "big") + (4501).to_bytes(2, "big") + \
          (8 + len(payload)).to_bytes(2, "big") + b"\x00\x00" + payload
    total = 20 + len(udp)
    ip = bytearray(bytes([0x45, 0x00]) + total.to_bytes(2, "big") + b"\x00\x00" +
                   bytes([0x40, 0x00, 0x40, 0x11]) + b"\x00\x00" + SRC_IP + DST_IP)
    s = 0
    for i in range(0, len(ip), 2):
        s += (ip[i] << 8) | ip[i + 1]
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    ip[10:12] = ((~s) & 0xFFFF).to_bytes(2, "big")
    return dst_mac + src_mac + bytes([0x08, 0x00]) + bytes(ip) + udp


def crc32(data):
    crc = 0xFFFFFFFF
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ (0xEDB88320 if crc & 1 else 0)
    return (~crc) & 0xFFFFFFFF


async def reset_dut(dut):
    dut.rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(5):
        await RisingEdge(dut.clk)


async def rgmii_drive(dut, rxd, ctl, clk_sig, frame):
    await RisingEdge(clk_sig)
    rxd.value = frame[0] & 0xF
    ctl.value = 1
    prev = 0.0
    for i, b in enumerate(frame):
        if i > 0:
            hi_t = 8.0 * i
            await Timer(hi_t - prev, unit="ns")
            rxd.value = b & 0xF
            ctl.value = 1
            prev = hi_t
        lo_t = 8.0 * i + 4.0
        await Timer(lo_t - prev, unit="ns")
        rxd.value = (b >> 4) & 0xF
        prev = lo_t
    await Timer(4.0, unit="ns")
    rxd.value = 0
    ctl.value = 0


async def xread(dut, adr):
    dut.xbus_adr_i.value = adr
    dut.xbus_we_i.value = 0
    dut.xbus_stb_i.value = 1
    dut.xbus_cyc_i.value = 1
    for _ in range(10):
        await RisingEdge(dut.clk)
        if int(dut.xbus_ack_o.value):
            v = int(dut.xbus_dat_o.value)
            dut.xbus_stb_i.value = 0
            dut.xbus_cyc_i.value = 0
            await RisingEdge(dut.clk)
            return v
    raise AssertionError("xbus read timeout")


async def xwrite(dut, adr, val):
    dut.xbus_adr_i.value = adr
    dut.xbus_we_i.value = 1
    dut.xbus_dat_o.value = val
    dut.xbus_stb_i.value = 1
    dut.xbus_cyc_i.value = 1
    for _ in range(10):
        await RisingEdge(dut.clk)
        if int(dut.xbus_ack_o.value):
            dut.xbus_stb_i.value = 0
            dut.xbus_cyc_i.value = 0
            await RisingEdge(dut.clk)
            return
    raise AssertionError("xbus write timeout")


@cocotb.test()
async def test_mgmt_echo(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    cocotb.start_soon(Clock(dut.gtx_clk, 8, unit="ns").start())
    cocotb.start_soon(Clock(dut.gtx_clk90, 8, unit="ns").start())
    cocotb.start_soon(Clock(dut.lan_rgmii_rx_clk, 8, unit="ns").start())
    cocotb.start_soon(Clock(dut.wan_rgmii_rx_clk, 8, unit="ns").start())
    dut.wan_tx_ready.value = 1
    await reset_dut(dut)
    dut.xbus_stb_i.value = 0
    dut.xbus_cyc_i.value = 0
    await RisingEdge(dut.clk)

    payload = bytes((i * 3 + 1) % 256 for i in range(64))
    req = build_udp(DST_MAC, SRC_MAC, payload)
    fcs = crc32(req).to_bytes(4, "little")
    await rgmii_drive(dut, dut.wan_rgmii_rxd, dut.wan_rgmii_rx_ctl,
                      dut.wan_rgmii_rx_clk, b"\x55" * 7 + b"\xd5" + req + fcs)

    deadline = 0
    while not int(dut.u_mbuf.req_pending.value):
        await RisingEdge(dut.clk)
        deadline += 1
        if deadline > 200000:
            raise AssertionError("req_pending never set")
    s = await xread(dut, 0xF0000200)
    len_b = (s >> 16) & 0x1fff
    dut._log.info(f"req pending len={len_b} status={s:08x}")
    assert len_b == len(payload), f"len mismatch {len_b}"

    n = len_b
    words = []
    while n >= 4:
        words.append(await xread(dut, 0xF0000204))
        n -= 4
    if n > 0:
        words.append(await xread(dut, 0xF0000204))
    dut.resp_len_w_in.value = len_b
    dut.resp_done_p_in.value = 0
    for w in words:
        for j in range(4):
            dut.resp_wen_in.value = 1
            dut.resp_waddr_in.value = (words.index(w) * 4 + j)
            dut.resp_wdata_in.value = (w >> (24 - 8 * j)) & 0xFF
            await RisingEdge(dut.clk)
    dut.resp_wen_in.value = 0
    dut.resp_done_p_in.value = 1
    await RisingEdge(dut.clk)
    dut.resp_done_p_in.value = 0
    for _ in range(8):
        await RisingEdge(dut.clk)

    out = bytearray()
    prev_d = 0
    for i in range(30000):
        await Timer(4.0, unit="ns")
        d = int(dut.wan_rgmii_txd.value)
        ct = int(dut.wan_rgmii_tx_ctl.value)
        if ct:
            if (i & 1):
                out.append((d << 4) | prev_d)
            else:
                prev_d = d
            if len(out) > 400:
                break
    dut._log.info(f"resp frame {len(out)}B")
    if len(out) < 100:
        raise AssertionError(f"no/too-short resp frame {len(out)}B")
    dut._log.info("mgmt chain OK (frame out)")