from collections import deque

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from tb_bridge import DST_IP, DST_MAC, DST_PORT, IV, KEY, SPI, SRC_IP, SRC_MAC, SRC_PORT
from tb_node import spi_configure

RX_FIFO_DEPTH = 2048
IFG_BYTES = 12
FRAMES = 24
PAYLOAD = 1200


def ip_checksum(header):
    total = 0
    for i in range(0, len(header), 2):
        total += (header[i] << 8) | header[i + 1]
        total = (total & 0xFFFF) + (total >> 16)
    return (~total) & 0xFFFF


def inner_frame(payload):
    udp_len = 8 + len(payload)
    ip_len = 20 + udp_len
    ip = bytearray(20)
    ip[0] = 0x45
    ip[2] = ip_len >> 8
    ip[3] = ip_len & 0xFF
    ip[8] = 64
    ip[9] = 17
    ip[12:16] = SRC_IP.to_bytes(4, "big")
    ip[16:20] = DST_IP.to_bytes(4, "big")
    ip[10:12] = ip_checksum(ip).to_bytes(2, "big")
    udp = bytearray(8)
    udp[0:2] = SRC_PORT.to_bytes(2, "big")
    udp[2:4] = DST_PORT.to_bytes(2, "big")
    udp[4:6] = udp_len.to_bytes(2, "big")
    eth = DST_MAC.to_bytes(6, "big") + SRC_MAC.to_bytes(6, "big") + (0x0800).to_bytes(2, "big")
    return eth + bytes(ip) + bytes(udp) + payload


class MacSource:
    def __init__(self, count, size):
        self.pending = deque(inner_frame(bytes((i * 7 + 3) & 0xFF for i in range(size)))
                             for _ in range(count))
        self.queue = deque()
        self.current = None
        self.offset = 0
        self.ifg = 0
        self.sent = 0
        self.dropped = 0
        self.peak = 0
        self.stall = 0

    def fill(self):
        if self.current is None:
            if self.ifg:
                self.ifg -= 1
                return
            if not self.pending:
                return
            self.current = self.pending.popleft()
            self.offset = 0
        if len(self.queue) >= RX_FIFO_DEPTH:
            self.dropped += 1
            self.current = None
            self.ifg = IFG_BYTES
            return
        self.queue.append((self.current[self.offset], self.offset == len(self.current) - 1))
        self.offset += 1
        if self.offset == len(self.current):
            self.sent += 1
            self.current = None
            self.ifg = IFG_BYTES

    def idle(self):
        return self.current is None and not self.pending and not self.queue


async def drive(dut, source):
    while not source.idle():
        ready = int(dut.lan_rx_ready.value)
        if not ready and source.queue:
            source.stall += 1
        source.fill()
        if source.queue:
            byte, last = source.queue[0]
            dut.lan_rxd.value = byte
            dut.lan_rx_dv.value = 1
            dut.lan_rx_last.value = 1 if last else 0
        else:
            dut.lan_rx_dv.value = 0
            dut.lan_rx_last.value = 0
        await ClockCycles(dut.clk, 1)
        if source.queue and ready:
            source.queue.popleft()
        source.peak = max(source.peak, len(source.queue))
    dut.lan_rx_dv.value = 0
    dut.lan_rx_last.value = 0


class MacSink:
    def __init__(self, depth=2048):
        self.queue = deque()
        self.depth = depth
        self.frames = []
        self.current = bytearray()
        self.overflow = 0

    def offer(self, byte, last):
        if len(self.queue) >= self.depth:
            self.overflow += 1
            return False
        self.queue.append((byte, last))
        return True

    def step(self):
        if not self.queue:
            return
        byte, last = self.queue.popleft()
        self.current.append(byte)
        if last:
            self.frames.append(bytes(self.current))
            self.current = bytearray()


async def collect(dut, frames, sink):
    while len(sink.frames) < frames:
        dut.wan_tx_ready.value = 1 if len(sink.queue) < sink.depth else 0
        if int(dut.wan_tx_en.value) and int(dut.wan_tx_ready.value):
            if not sink.offer(int(dut.wan_txd.value), int(dut.wan_tx_last.value) == 1):
                dut.wan_tx_ready.value = 0
        sink.step()
        await ClockCycles(dut.clk, 1)
    return sink.frames


async def start(dut):
    cocotb.start_soon(Clock(dut.clk, 8, "ns").start())
    dut.rst_n.value = 0
    dut.spi_sck.value = 0
    dut.spi_mosi.value = 0
    dut.spi_csn.value = 1
    dut.lan_rxd.value = 0
    dut.lan_rx_dv.value = 0
    dut.lan_rx_last.value = 0
    dut.wan_rxd.value = 0
    dut.wan_rx_dv.value = 0
    dut.wan_rx_last.value = 0
    dut.lan_tx_ready.value = 1
    dut.wan_tx_ready.value = 1
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    await spi_configure(dut)
    await ClockCycles(dut.clk, 10)


@cocotb.test()
async def line_rate_no_loss(dut):
    await start(dut)
    source = MacSource(FRAMES, PAYLOAD)
    sink = MacSink()
    watcher = cocotb.start_soon(collect(dut, FRAMES, sink))
    await drive(dut, source)
    frames = await watcher

    dut._log.info(f"STALL={source.stall} PEAK={source.peak} TXOVER={sink.overflow}")
    assert len(sink.frames) == FRAMES
    assert source.dropped == 0, (
        f"rx fifo overflowed on {source.dropped} of {FRAMES} frames "
        f"at gigabit line rate (queue left {len(source.queue)})"
    )
    assert source.sent == FRAMES
    assert len(frames) == FRAMES, f"forwarded {len(frames)} of {FRAMES}"


@cocotb.test()
async def back_to_back_frames_preserved(dut):
    await start(dut)
    source = MacSource(4, 64)
    sink = MacSink()
    watcher = cocotb.start_soon(collect(dut, 4, sink))
    await drive(dut, source)
    frames = await watcher
    assert source.dropped == 0
    frm_len = len(inner_frame(b"\0" * 64))
    pad = (16 - ((frm_len + 2) & 0xF)) & 0xF
    expected = 42 + 20 + frm_len + 2 + pad + 16
    lengths = [len(f) for f in frames]
    assert lengths == [expected] * 4, (lengths, expected)
    for frame in frames:
        assert frame[42:46] == SPI.to_bytes(4, "big")
