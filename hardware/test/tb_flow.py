from collections import deque

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
from cocotb.utils import get_sim_time

from tb_bridge import DST_IP, DST_MAC, DST_PORT, SPI, SRC_IP, SRC_MAC
from tb_line_rate import MacSource, drive, inner_frame
from tb_node import spi_configure

STORM = 120
PAYLOAD = 1200


def ip_checksum(header):
    total = 0
    for i in range(0, len(header), 2):
        total += (header[i] << 8) | header[i + 1]
        total = (total & 0xFFFF) + (total >> 16)
    return (~total) & 0xFFFF


def wan_frame(esp):
    udp_len = 8 + len(esp)
    ip_len = 20 + udp_len
    ip = bytearray(20)
    ip[0] = 0x45
    ip[2] = ip_len >> 8
    ip[3] = ip_len & 0xFF
    ip[8] = 64
    ip[9] = 17
    ip[12:16] = DST_IP.to_bytes(4, "big")
    ip[16:20] = SRC_IP.to_bytes(4, "big")
    ip[10:12] = ip_checksum(ip).to_bytes(2, "big")
    udp = bytearray(8)
    udp[0:2] = DST_PORT.to_bytes(2, "big")
    udp[2:4] = DST_PORT.to_bytes(2, "big")
    udp[4:6] = udp_len.to_bytes(2, "big")
    eth = SRC_MAC.to_bytes(6, "big") + DST_MAC.to_bytes(6, "big") + (0x0800).to_bytes(2, "big")
    return eth + bytes(ip) + bytes(udp) + esp


class Collector:
    def __init__(self, prefix, depth=2048):
        self.prefix = prefix
        self.depth = depth
        self.queue = deque()
        self.frames = []
        self.current = bytearray()

    def step(self):
        if self.queue:
            byte, last = self.queue.popleft()
            self.current.append(byte)
            if last:
                self.frames.append(bytes(self.current))
                self.current = bytearray()

    async def run(self, dut, stop):
        while not stop["done"]:
            ready = getattr(dut, self.prefix + "_tx_ready")
            en = getattr(dut, self.prefix + "_tx_en")
            if int(ready.value) and len(self.queue) < self.depth and int(en.value):
                self.queue.append(
                    (int(getattr(dut, self.prefix + "_txd").value),
                     int(getattr(dut, self.prefix + "_tx_last").value) == 1)
                )
            self.step()
            await ClockCycles(dut.clk, 1)


async def send_wan(dut, frame):
    idx = 0
    while idx < len(frame):
        if int(dut.wan_rx_ready.value):
            dut.wan_rxd.value = frame[idx]
            dut.wan_rx_dv.value = 1
            dut.wan_rx_last.value = 1 if idx == len(frame) - 1 else 0
            idx += 1
        await ClockCycles(dut.clk, 1)
    dut.wan_rx_dv.value = 0
    dut.wan_rx_last.value = 0


def esp_payloads(frames):
    return [f[42:] for f in frames if len(f) > 42 and f[42:46] == SPI.to_bytes(4, "big")]


async def wait_frames(dut, collector, count, limit=120000):
    for _ in range(limit):
        if len(collector.frames) >= count:
            return True
        await ClockCycles(dut.clk, 10)
    return False


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


def probe(dut, tag):
    d = dut.u_bridge.u_dec
    stamp = get_sim_time("ns")
    e = dut.u_bridge.u_enc
    print(
        f"t={stamp}ns {tag}: dir_enc={int(dut.u_bridge.dir_enc.value)} "
        f"dec[rx={int(d.rx_state.value)} ds={int(d.ds.value)} pend={int(d.dec_pend.value):02b} "
        f"avail={int(d.ct_avail.value):02b} ts={int(d.ts.value)} "
        f"tagv={int(d.tag_valid_q.value)} ok={int(d.tag_ok_q.value) if hasattr(d, 'tag_ok_q') else '-'}] "
        f"enc[es={int(e.es.value)} pend={int(e.enc_pend.value):02b} "
        f"busy={int(e.tx_busy.value):02b} "
        f"egrant={int(dut.u_bridge.enc_grant_w.value)} dgrant={int(dut.u_bridge.dec_grant_w.value)} "
        f"gbusy={int(dut.u_bridge.gcm_busy.value)} gphase={int(dut.u_bridge.u_gcm.phase.value)} "
        f"enc_req={int(dut.u_bridge.enc_req_w.value)} dec_req={int(dut.u_bridge.dec_req_w.value)} "
        f"ctr[enc={int(dut.u_bridge.enc_ct_ready.value)} dec={int(dut.u_bridge.dec_ct_ready.value)} "
        f"sel={int(dut.u_bridge.gcm_ct_ready.value)}] "
        f"ptr[enc={int(dut.u_bridge.enc_pt_ready.value)} dec={int(dut.u_bridge.dec_pt_ready.value)} "
        f"sel={int(dut.u_bridge.gcm_pt_ready.value)}] "
        f"ptvalid[enc={int(dut.u_bridge.enc_pt_valid.value)} dec={int(dut.u_bridge.dec_pt_valid.value)} "
        f"sel={int(dut.u_bridge.gcm_pt_valid_w.value)}] "
        f"gcm[pt_cnt={int(dut.u_bridge.u_gcm.pt_cnt.value)} cntr={int(dut.u_bridge.u_gcm.cntr.value)} "
        f"nct={int(dut.u_bridge.u_gcm.nct_r.value)} ghcnt={int(dut.u_bridge.u_gcm.ghcnt.value)} "
        f"ghq={int(dut.u_bridge.u_gcm.gh_qcnt.value)} out={int(dut.u_bridge.u_gcm.out_cnt.value)} "
        f"aes_done={int(dut.u_bridge.u_gcm.aes_done.value)} aes_start={int(dut.u_bridge.u_gcm.aes_start.value)} "
        f"load_rdy={int(dut.u_bridge.u_gcm.aes_load_rdy.value)} cbgap={int(dut.u_bridge.u_gcm.cb_gap.value)} "
        f"aes[busy={int(dut.u_bridge.u_gcm.aes_busy.value)} cry_rdy={int(dut.u_bridge.u_gcm.aes_crypt_rdy.value)} "
        f"blkv={int(dut.u_bridge.u_gcm.blk_valid_w.value)} subbase={int(dut.u_bridge.u_gcm.cb_submit_base.value)} "
        f"outroom={int(dut.u_bridge.u_gcm.out_room.value)} avail={int(dut.u_bridge.u_gcm.cb_avail.value)} "
        f"ghready={int(dut.u_bridge.u_gcm.gh_ready.value)} ghbusy={int(dut.u_bridge.u_gcm.gh_busy.value)}]]",
        flush=True,
    )


@cocotb.test()
async def decrypt_during_encrypt_storm(dut):
    await start(dut)
    stop = {"done": False}
    lan = Collector("lan")
    wan = Collector("wan")
    tasks = [
        cocotb.start_soon(lan.run(dut, stop)),
        cocotb.start_soon(wan.run(dut, stop)),
    ]

    warm = MacSource(3, PAYLOAD)
    await drive(dut, warm)
    assert await wait_frames(dut, wan, 3), "warmup encrypted nothing"
    warm_esps = esp_payloads(wan.frames)
    await send_wan(dut, wan_frame(warm_esps[0]))
    assert await wait_frames(dut, lan, 1), "baseline decrypt produced nothing"
    print("baseline ok", flush=True)

    ready_esp = warm_esps[1]
    before_lan = len(lan.frames)
    before_wan = len(wan.frames)

    mismatch = {"enc": 0, "dec": 0, "flip_busy": 0, "last_dir": None}

    async def guard():
        while not stop["done"]:
            await ClockCycles(dut.clk, 1)
            own = int(dut.u_bridge.dir_enc.value)
            if int(dut.u_bridge.enc_start_w.value) and own == 0:
                mismatch["enc"] += 1
            if int(dut.u_bridge.dec_start_w.value) and own == 1:
                mismatch["dec"] += 1
            if mismatch["last_dir"] is not None and own != mismatch["last_dir"]:
                if int(dut.u_bridge.gcm_busy.value):
                    mismatch["flip_busy"] += 1
            mismatch["last_dir"] = own

    guard_task = cocotb.start_soon(guard())
    events = []
    prev_sig = None

    async def sink_watch(state):
        while not stop["done"]:
            await ClockCycles(dut.clk, 1)
            if int(dut.dec_s_tvalid.value) and int(dut.dec_s_tready.value):
                state["dec_in"] = state.get("dec_in", 0) + 1
            if int(dut.wan_rx_dv.value) and not int(dut.wan_rx_ready.value):
                state["stall"] = state.get("stall", 0) + 1

    async def snoop():
        nonlocal prev_sig
        while not stop["done"]:
            await ClockCycles(dut.clk, 1)
            g = dut.u_bridge.u_gcm
            sig = (int(g.aes_start.value), int(g.blk_valid_w.value), int(g.aes_done.value),
                   int(g.aes_load_rdy.value), int(g.phase.value), int(g.cntr.value),
                   int(g.pt_cnt.value))
            if sig != prev_sig:
                prev_sig = sig
                events.append((get_sim_time("ns"), sig))
    counters = {"dec_in": 0, "stall": 0}
    snoop_task = cocotb.start_soon(snoop())
    sink_task = cocotb.start_soon(sink_watch(counters))
    storm = MacSource(STORM, PAYLOAD)
    storm_task = cocotb.start_soon(drive(dut, storm))
    assert await wait_frames(dut, wan, before_wan + 14), "storm did not produce frames"
    probe(dut, "mid storm")
    burst = esp_payloads(wan.frames)[1:13]
    for esp in burst:
        await send_wan(dut, wan_frame(esp))
    await ClockCycles(dut.clk, 4000)
    probe(dut, "after inject")
    for _ in range(6000):
        if len(lan.frames) - before_lan >= len(burst):
            break
        await ClockCycles(dut.clk, 50)
    probe(dut, "after wait")
    print(f"dec_in={counters.get('dec_in')} stall_cycles={counters.get('stall')}", flush=True)
    stop["done"] = True
    for stamp, sig in events[-40:]:
        print(f"  ev t={stamp} start,vld,done,ldrdy,phase,cntr,ptcnt={sig}", flush=True)
    await snoop_task
    await sink_task
    await guard_task
    await storm_task
    for task in tasks:
        await task

    produced = lan.frames[before_lan:]
    print(
        f"storm: lan_sent={storm.sent} wan_out={len(wan.frames) - before_wan} "
        f"lan_out={len(produced)} mismatch={mismatch}",
        flush=True,
    )
    assert not (mismatch["enc"] or mismatch["dec"] or mismatch["flip_busy"]), (
        f"key direction faulted while the decrypt path was busy: {mismatch}"
    )
    assert produced, "decrypt during encrypt storm produced nothing"


@cocotb.test()
async def corrupt_frame_does_not_wedge(dut):
    await start(dut)
    stop = {"done": False}
    lan = Collector("lan")
    wan = Collector("wan")
    tasks = [
        cocotb.start_soon(lan.run(dut, stop)),
        cocotb.start_soon(wan.run(dut, stop)),
    ]
    warm = MacSource(5, PAYLOAD)
    await drive(dut, warm)
    assert await wait_frames(dut, wan, 5), "warmup encrypted nothing"
    esps = esp_payloads(wan.frames)

    await send_wan(dut, wan_frame(esps[0]))
    assert await wait_frames(dut, lan, 1), "baseline decrypt produced nothing"
    print("baseline ok", flush=True)

    corrupt = bytearray(esps[1])
    corrupt[100] ^= 0x01
    await send_wan(dut, wan_frame(bytes(corrupt)))
    await ClockCycles(dut.clk, 400)
    print(f"corrupt frame injected, lan_out={len(lan.frames)}", flush=True)

    before = len(lan.frames)
    await send_wan(dut, wan_frame(esps[2]))
    ok = await wait_frames(dut, lan, before + 1, 40000)
    stop["done"] = True
    for task in tasks:
        await task
    assert ok, (
        f"one corrupted frame wedged the decrypt path: the following valid frame "
        f"never came out (lan frames {len(lan.frames)}, dec ds={int(dut.u_bridge.u_dec.ds.value)}, "
        f"pend={int(dut.u_bridge.u_dec.dec_pend.value):02b}, "
        f"avail={int(dut.u_bridge.u_dec.ct_avail.value):02b})"
    )


@cocotb.test()
async def sequential_direction_switch(dut):
    await start(dut)
    stop = {"done": False}
    lan = Collector("lan")
    wan = Collector("wan")
    tasks = [
        cocotb.start_soon(lan.run(dut, stop)),
        cocotb.start_soon(wan.run(dut, stop)),
    ]

    warm = MacSource(4, PAYLOAD)
    await drive(dut, warm)
    assert await wait_frames(dut, wan, 4), "warmup encrypted nothing"
    warm_esps = esp_payloads(wan.frames)
    await send_wan(dut, wan_frame(warm_esps[0]))
    assert await wait_frames(dut, lan, 1), "baseline decrypt produced nothing"
    before_lan = len(lan.frames)

    storm = MacSource(60, PAYLOAD)
    await drive(dut, storm)
    await wait_frames(dut, wan, 62)
    await ClockCycles(dut.clk, 4000)
    probe(dut, "after storm")

    esps = esp_payloads(wan.frames)[4:20]
    for esp in esps:
        await send_wan(dut, wan_frame(esp))
    ok = await wait_frames(dut, lan, before_lan + len(esps), 80000)
    stop["done"] = True
    for task in tasks:
        await task
    produced = len(lan.frames) - before_lan
    print(f"storm esps={len(esps)} decrypted={produced}", flush=True)
    assert ok, (
        f"after an encrypt storm only {produced} of {len(esps)} frames decrypted "
        f"(dec rx={int(dut.u_bridge.u_dec.rx_state.value)} "
        f"ds={int(dut.u_bridge.u_dec.ds.value)} "
        f"pend={int(dut.u_bridge.u_dec.dec_pend.value):02b} "
        f"avail={int(dut.u_bridge.u_dec.ct_avail.value):02b} "
        f"ts={int(dut.u_bridge.u_dec.ts.value)} "
        f"gbusy={int(dut.u_bridge.gcm_busy.value)} "
        f"held={int(dut.u_bridge.u_arb.held.value)})"
    )
