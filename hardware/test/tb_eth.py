import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

SRC_MAC = 0x001122334455
DST_MAC = 0x66778899aabb
SRC_IP = 0xc0a80101
DST_IP = 0xc0a80102


def build_frame(payload, dport):
    eth = SRC_MAC.to_bytes(6, "big") + DST_MAC.to_bytes(6, "big") + b"\x08\x00"
    total = 20 + 8 + len(payload)
    ip = bytes([0x45, 0x00]) + total.to_bytes(2, "big") + b"\x00\x00\x40\x00\x40\x11\x00\x00" + SRC_IP.to_bytes(4, "big") + DST_IP.to_bytes(4, "big")
    udp = (4500).to_bytes(2, "big") + dport.to_bytes(2, "big") + (8 + len(payload)).to_bytes(2, "big") + b"\x00\x00"
    return eth + ip + udp + payload


def setup(dut):
    dut.cfg_src_mac.value = SRC_MAC
    dut.cfg_dst_mac.value = DST_MAC
    dut.cfg_src_ip.value = SRC_IP
    dut.cfg_dst_ip.value = DST_IP
    dut.s_esp_tdata.value = 0
    dut.s_esp_tvalid.value = 0
    dut.s_esp_tlast.value = 0
    dut.s_hsk_tdata.value = 0
    dut.s_hsk_tvalid.value = 0
    dut.hsk_len_in.value = 0
    dut.m_data_tready.value = 1
    dut.hsk_ready.value = 1
    dut.hsk_room.value = 512
    dut.arp_read.value = 0
    dut.ctrl_data.value = 0
    dut.ctrl_valid.value = 0
    dut.ctrl_last.value = 0
    dut.m_tready.value = 1


async def inject(dut, frame):
    for j, b in enumerate(frame):
        dut.s_tdata.value = b
        dut.s_tvalid.value = 1
        dut.s_tlast.value = 1 if j == len(frame) - 1 else 0
        await ClockCycles(dut.clk, 1)
    dut.s_tvalid.value = 0
    dut.s_tlast.value = 0
    await ClockCycles(dut.clk, 2)


@cocotb.test()
async def rx_split(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    setup(dut)
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    payload = bytes((i * 3 + 1) & 0xFF for i in range(64))
    out = bytearray()

    async def collect():
        for _ in range(1000):
            if int(dut.m_data_tvalid.value):
                out.append(int(dut.m_data_tdata.value))
            await ClockCycles(dut.clk, 1)

    c = cocotb.start_soon(collect())
    await inject(dut, build_frame(payload, 4500))
    await c
    assert bytes(out) == payload, f"data path: got {bytes(out).hex()} exp {payload.hex()}"

    hsk_payload = b"\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f"
    got = []

    async def collect_hsk():
        for _ in range(1000):
            if int(dut.hsk_wr.value):
                got.append(int(dut.hsk_data.value))
            if int(dut.hsk_last.value):
                got.append(-1)
            await ClockCycles(dut.clk, 1)

    c = cocotb.start_soon(collect_hsk())
    await inject(dut, build_frame(hsk_payload, 4501))
    await c
    assert -1 in got, "hsk_last never seen"
    assert got[0] == 0x01020304 and got[1] == 0x05060708 and got[2] == 0x090a0b0c and got[3] == 0x0d0e0f00, f"hsk words {got}"
    assert int(dut.hsk_len.value) == len(hsk_payload), f"hsk len {int(dut.hsk_len.value)}"


@cocotb.test()
async def tx_hsk_wrap(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    setup(dut)
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    payload = bytes(range(1, 17))
    words = [int.from_bytes(payload[i:i+4], "big") for i in range(0, 16, 4)]
    out = bytearray()

    async def drive():
        i = 0
        dut.s_hsk_tvalid.value = 1
        dut.hsk_len_in.value = len(payload)
        dut.s_hsk_tdata.value = words[0]
        for _ in range(200):
            if int(dut.s_hsk_tready.value):
                i += 1
                await ClockCycles(dut.clk, 1)
                if i < len(words):
                    dut.s_hsk_tdata.value = words[i]
            else:
                await ClockCycles(dut.clk, 1)
        dut.s_hsk_tvalid.value = 0
        await ClockCycles(dut.clk, 20)

    async def collect():
        for _ in range(2000):
            if int(dut.m_tvalid.value):
                out.append(int(dut.m_tdata.value))
                if int(dut.m_tlast.value):
                    return
            await ClockCycles(dut.clk, 1)

    c = cocotb.start_soon(collect())
    await drive()
    await c
    assert len(out) == 42 + len(payload), f"frame len {len(out)}"
    assert out[:6] == DST_MAC.to_bytes(6, "big"), f"dst mac {out[:6].hex()}"
    assert out[6:12] == SRC_MAC.to_bytes(6, "big")
    assert out[12:14] == b"\x08\x00"
    assert out[14] == 0x45
    assert out[23] == 0x11
    assert out[34:36] == b"\x11\x95", f"src port {out[34:36].hex()}"
    assert out[36:38] == b"\x11\x95", f"dst port {out[36:38].hex()}"
    assert out[38:40] == (8 + len(payload)).to_bytes(2, "big"), f"udp len {out[38:40].hex()}"
    assert bytes(out[42:]) == payload, f"payload {bytes(out[42:]).hex()}"


@cocotb.test()
async def tx_esp_passthrough(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    setup(dut)
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    frame = bytes((i * 7 + 3) & 0xFF for i in range(100))
    out = bytearray()

    async def drive():
        for j, b in enumerate(frame):
            dut.s_esp_tdata.value = b
            dut.s_esp_tvalid.value = 1
            dut.s_esp_tlast.value = 1 if j == len(frame) - 1 else 0
            await ClockCycles(dut.clk, 1)
        dut.s_esp_tvalid.value = 0
        dut.s_esp_tlast.value = 0
        await ClockCycles(dut.clk, 5)

    async def collect():
        for _ in range(2000):
            if int(dut.m_tvalid.value):
                out.append(int(dut.m_tdata.value))
                if int(dut.m_tlast.value):
                    return
            await ClockCycles(dut.clk, 1)

    c = cocotb.start_soon(collect())
    await drive()
    await c
    assert bytes(out) == frame, f"esp passthrough {len(out)} bytes"


def build_arp_request(spa, tpa, sha=SRC_MAC):
    eth = b"\xff" * 6 + SRC_MAC.to_bytes(6, "big") + b"\x08\x06"
    arp = bytes([0, 1, 8, 0, 6, 4, 0, 1]) + sha.to_bytes(6, "big") + spa.to_bytes(4, "big") + b"\x00" * 6 + tpa.to_bytes(4, "big")
    return eth + arp


def build_arp_reply(sha, spa):
    eth = sha.to_bytes(6, "big") + SRC_MAC.to_bytes(6, "big") + b"\x08\x06"
    arp = bytes([0, 1, 8, 0, 6, 4, 0, 2]) + SRC_MAC.to_bytes(6, "big") + SRC_IP.to_bytes(4, "big") + sha.to_bytes(6, "big") + spa.to_bytes(4, "big")
    return eth + arp


def build_garp():
    eth = b"\xff" * 6 + SRC_MAC.to_bytes(6, "big") + b"\x08\x06"
    arp = bytes([0, 1, 8, 0, 6, 4, 0, 1]) + SRC_MAC.to_bytes(6, "big") + SRC_IP.to_bytes(4, "big") + b"\x00" * 6 + SRC_IP.to_bytes(4, "big")
    return eth + arp


async def drive_ctrl(dut, frame):
    for j, b in enumerate(frame):
        dut.ctrl_data.value = b
        dut.ctrl_valid.value = 1
        dut.ctrl_last.value = 1 if j == len(frame) - 1 else 0
        await ClockCycles(dut.clk, 1)
    dut.ctrl_valid.value = 0
    dut.ctrl_last.value = 0


async def wait_arp(dut):
    for _ in range(200):
        if int(dut.arp_pending.value):
            return int(dut.arp_capture.value)
        await ClockCycles(dut.clk, 1)
    raise AssertionError("arp pending timeout")


@cocotb.test()
async def arp_reply(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    setup(dut)
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    req = build_arp_request(SRC_IP, SRC_IP)
    out = bytearray()

    async def collect():
        for _ in range(2000):
            if int(dut.m_tvalid.value):
                out.append(int(dut.m_tdata.value))
                if int(dut.m_tlast.value):
                    return
            await ClockCycles(dut.clk, 1)

    async def drive():
        for j, b in enumerate(req):
            dut.s_tdata.value = b
            dut.s_tvalid.value = 1
            dut.s_tlast.value = 1 if j == len(req) - 1 else 0
            await ClockCycles(dut.clk, 1)
        dut.s_tvalid.value = 0
        dut.s_tlast.value = 0

    c = cocotb.start_soon(collect())
    await drive()

    cap = await wait_arp(dut)
    sha = (cap >> 32) & 0xFFFFFFFFFFFF
    spa = cap & 0xFFFFFFFF
    assert sha == SRC_MAC, f"capture sha {sha:012x}"
    assert spa == SRC_IP, f"capture spa {spa:08x}"
    dut.arp_read.value = 1
    await ClockCycles(dut.clk, 2)
    dut.arp_read.value = 0
    assert int(dut.arp_pending.value) == 0, "arp pending not cleared"

    await drive_ctrl(dut, build_arp_reply(sha, spa))
    await c

    assert len(out) == 42, f"arp reply len {len(out)}"
    assert out[:6] == SRC_MAC.to_bytes(6, "big"), f"dst mac {out[:6].hex()}"
    assert out[6:12] == SRC_MAC.to_bytes(6, "big")
    assert out[12:14] == b"\x08\x06"
    assert out[14:17] == b"\x00\x01\x08", f"hw type {out[14:17].hex()}"
    assert out[20] == 0x00 and out[21] == 0x02, f"opcode {out[20:22].hex()}"
    assert out[22:28] == SRC_MAC.to_bytes(6, "big"), f"sha {out[22:28].hex()}"
    assert out[28:32] == SRC_IP.to_bytes(4, "big"), f"spa {out[28:32].hex()}"
    assert out[32:38] == SRC_MAC.to_bytes(6, "big"), f"tha {out[32:38].hex()}"
    assert out[38:42] == SRC_IP.to_bytes(4, "big"), f"tpa {out[38:42].hex()}"


@cocotb.test()
async def garp_on_key_load(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    setup(dut)
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    out = bytearray()

    async def collect():
        for _ in range(2000):
            if int(dut.m_tvalid.value):
                out.append(int(dut.m_tdata.value))
                if int(dut.m_tlast.value):
                    return
            await ClockCycles(dut.clk, 1)

    c = cocotb.start_soon(collect())
    await drive_ctrl(dut, build_garp())
    await c

    assert len(out) == 42, f"garp len {len(out)}"
    assert out[:6] == b"\xff" * 6, f"garp dst {out[:6].hex()}"
    assert out[12:14] == b"\x08\x06"
    assert out[20:22] == b"\x00\x01", f"garp opcode {out[20:22].hex()}"
    assert out[22:28] == SRC_MAC.to_bytes(6, "big")
    assert out[28:32] == SRC_IP.to_bytes(4, "big"), f"garp spa {out[28:32].hex()}"
    assert out[32:38] == b"\x00" * 6, f"garp tha {out[32:38].hex()}"
    assert out[38:42] == SRC_IP.to_bytes(4, "big"), f"garp tpa {out[38:42].hex()}"

@cocotb.test()
async def dport_whitelist(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    setup(dut)
    dut.cfg_dport.value = 0x1234
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    payload = bytes((i * 5 + 2) & 0xFF for i in range(32))

    async def data_collect():
        out = bytearray()
        for _ in range(600):
            if int(dut.m_data_tvalid.value):
                out.append(int(dut.m_data_tdata.value))
                if int(dut.m_data_tlast.value):
                    return bytes(out)
            await ClockCycles(dut.clk, 1)
        raise AssertionError(f"data frame not received, got {len(out)} bytes")

    c = cocotb.start_soon(data_collect())
    await inject(dut, build_frame(payload, 0x1234))
    got = await c
    assert got == payload, f"cfg port frame: got {got.hex()} exp {payload.hex()}"

    got = []
    async def hsk_collect():
        for _ in range(600):
            if int(dut.hsk_wr.value):
                got.append(int(dut.hsk_data.value))
            if int(dut.hsk_last.value):
                got.append(-1)
            await ClockCycles(dut.clk, 1)

    c = cocotb.start_soon(hsk_collect())
    await inject(dut, build_frame(payload, 4501))
    await c
    assert -1 in got and got[0] == int.from_bytes(payload[:4], "big"), f"hsk via 4501 failed {got}"

    seen = []
    async def probe():
        for _ in range(500):
            if int(dut.m_data_tvalid.value) or int(dut.hsk_wr.value):
                seen.append(1)
            await ClockCycles(dut.clk, 1)

    p = cocotb.start_soon(probe())
    await inject(dut, build_frame(payload, 0x9999))
    await p
    assert not seen, "foreign dport leaked"


@cocotb.test()
async def ip_pathology(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    setup(dut)
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    payload = bytes((i * 3 + 1) & 0xFF for i in range(48))

    def mk(ip_ver, flags_frag, cksum):
        eth = SRC_MAC.to_bytes(6, "big") + DST_MAC.to_bytes(6, "big") + b"\x08\x00"
        total = 20 + 8 + len(payload)
        ip = bytes([ip_ver, 0x00]) + total.to_bytes(2, "big") + b"\x00\x00" + flags_frag + bytes([0x40, 0x11]) + cksum + SRC_IP.to_bytes(4, "big") + DST_IP.to_bytes(4, "big")
        udp = (4500).to_bytes(2, "big") + (4500).to_bytes(2, "big") + (8 + len(payload)).to_bytes(2, "big") + b"\x00\x00"
        return eth + ip + udp + payload

    async def collect():
        out = bytearray()
        for _ in range(600):
            if int(dut.m_data_tvalid.value):
                out.append(int(dut.m_data_tdata.value))
                if int(dut.m_data_tlast.value):
                    return bytes(out)
            await ClockCycles(dut.clk, 1)
        raise AssertionError("frame not received")

    c = cocotb.start_soon(collect())
    await inject(dut, mk(0x45, b"\x00\x01", b"\x00\x00"))
    got = await c
    assert got == payload, f"fragmented frame must pass: {got[:8].hex()}"

    c = cocotb.start_soon(collect())
    await inject(dut, mk(0x45, b"\x00\x00", b"\x12\x34"))
    got = await c
    assert got == payload, "bad ip checksum must pass (not checked)"

    seen = []
    async def probe():
        for _ in range(500):
            if int(dut.m_data_tvalid.value) or int(dut.hsk_wr.value):
                seen.append(1)
            await ClockCycles(dut.clk, 1)

    p = cocotb.start_soon(probe())
    await inject(dut, mk(0x46, b"\x00\x00", b"\x00\x00"))
    await p
    assert not seen, "IHL 6 frame must be dropped"
