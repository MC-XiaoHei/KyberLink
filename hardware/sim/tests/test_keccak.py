import random

import cocotb
from cocotb.triggers import Timer

RC = [0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
      0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
      0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
      0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
      0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
      0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008]
R = [[0, 36, 3, 41, 18], [1, 44, 10, 45, 2], [62, 6, 43, 15, 61], [28, 55, 25, 21, 56], [27, 20, 39, 8, 14]]
M = (1 << 64) - 1


def rol(x, n):
    n %= 64
    return ((x << n) | (x >> (64 - n))) & M


def keccak_round(a, rc):
    c = [a[x] ^ a[x + 5] ^ a[x + 10] ^ a[x + 15] ^ a[x + 20] for x in range(5)]
    d = [c[(x + 4) % 5] ^ rol(c[(x + 1) % 5], 1) for x in range(5)]
    b = [0] * 25
    for x in range(5):
        for y in range(5):
            b[y + 5 * ((2 * x + 3 * y) % 5)] = rol(a[x + 5 * y] ^ d[x], R[x][y])
    out = [0] * 25
    for x in range(5):
        for y in range(5):
            out[x + 5 * y] = b[x + 5 * y] ^ ((~b[(x + 1) % 5 + 5 * y]) & b[(x + 2) % 5 + 5 * y])
    out[0] ^= rc
    return out


@cocotb.test
async def test_random_states(dut):
    rng = random.Random(0x5EED)
    for trial in range(10):
        state = 0
        ref = [rng.getrandbits(64) for _ in range(25)]
        for l in range(25):
            state |= ref[l] << (64 * l)
        for r in range(24):
            dut.state_in.value = state
            dut.round.value = r
            await Timer(1, units="ns")
            got = int(dut.state_out.value)
            ref = keccak_round(ref, RC[r])
            expect = 0
            for l in range(25):
                expect |= ref[l] << (64 * l)
            if got != expect:
                bad = [l for l in range(25) if ((got >> (64 * l)) & M) != ref[l]]
                raise AssertionError(
                    f"trial={trial} round={r} mismatch lanes={bad[:10]} "
                    f"lane0_got={got & M:016x} lane0_exp={ref[0]:016x}")
            state = got
