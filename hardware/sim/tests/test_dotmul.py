import json
import os
import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "vectors", "generated")
VECTORS = os.path.join(VECDIR, "kem_encaps_mid.json")

Q = 3329


def bitrev7(i):
    r = 0
    for _ in range(7):
        r = (r << 1) | (i & 1)
        i >>= 1
    return r


GAMMAS = [pow(17, 2 * bitrev7(i) + 1, Q) for i in range(128)]


def basemul(a0, a1, b0, b1, gamma):
    c0 = (a0 * b0 + a1 * b1 * gamma) % Q
    c1 = (a0 * b1 + a1 * b0) % Q
    return c0, c1


def dot3(a, b):
    c = [0] * 256
    for k in range(128):
        acc0 = 0
        acc1 = 0
        for j in range(3):
            x0, x1 = basemul(a[j][2 * k], a[j][2 * k + 1], b[j][2 * k], b[j][2 * k + 1], GAMMAS[k])
            acc0 = (acc0 + x0) % Q
            acc1 = (acc1 + x1) % Q
        c[2 * k] = acc0
        c[2 * k + 1] = acc1
    return c


@cocotb.test()
async def test_dotmul_vectors(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await Timer(25, units="ns")
    dut.rst_n.value = 0
    await Timer(2, units="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await Timer(2, units="ns")

    with open(VECTORS) as f:
        vecs = json.load(f)

    for v in vecs:
        th = v["th"]
        yh = v["yh"]
        a = [[th[256 * j + k] for k in range(256)] for j in range(3)]
        b = [[yh[256 * j + k] for k in range(256)] for j in range(3)]
        want = dot3(a, b)

        dut.a_in.value = sum(a[j][k] << (12 * (256 * j + k)) for j in range(3) for k in range(256))
        dut.b_in.value = sum(b[j][k] << (12 * (256 * j + k)) for j in range(3) for k in range(256))
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0

        while not dut.done.value:
            await RisingEdge(dut.clk)
        await Timer(1, units="ns")

        got = [int(dut.c_arr[k].value) for k in range(256)]
        for k in range(256):
            assert got[k] == want[k], f"idx={v['index']} k={k} got {got[k]} want {want[k]}"
    dut._log.info(f"dotmul {len(vecs)} vectors PASS")
