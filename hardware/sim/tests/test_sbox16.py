import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


def gm(a, b):
    r = 0
    while b:
        if b & 1:
            r ^= a
        b >>= 1
        a <<= 1
        if a & 0x100:
            a ^= 0x11B
    return r


def affine(b):
    r = 0
    for i in range(8):
        bit = ((b >> i) & 1) ^ ((b >> ((i + 4) % 8)) & 1) ^ ((b >> ((i + 5) % 8)) & 1) ^ ((b >> ((i + 6) % 8)) & 1) ^ ((b >> ((i + 7) % 8)) & 1) ^ ((0x63 >> i) & 1)
        r |= bit << i
    return r


def gen_sbox():
    s = [0] * 256
    for x in range(256):
        inv = 0
        if x != 0:
            for y in range(1, 256):
                if gm(x, y) == 1:
                    inv = y
                    break
        s[x] = affine(inv)
    return s


@cocotb.test()
async def test_sbox16(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    sbox = gen_sbox()
    dut.x.value = 0
    expect = []
    fails = []
    for t in range(300):
        xv = int.from_bytes(bytes((t + j) % 256 for j in range(16)), "big")
        dut.x.value = xv
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        expect.append(xv)
        if len(expect) > 0:
            x_in = expect.pop(0)
            yb = int(dut.y.value).to_bytes(16, "big")
            xb = x_in.to_bytes(16, "big")
            for j in range(16):
                if yb[j] != sbox[xb[j]]:
                    fails.append((t, j, xb[j], yb[j]))
    assert not fails, f"sbox mismatches: {fails[:20]}"
