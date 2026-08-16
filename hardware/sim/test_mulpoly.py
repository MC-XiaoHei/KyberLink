import json
import cocotb
from cocotb.triggers import Timer


@cocotb.test()
async def test_mp(dut):
    v = json.load(open('/mnt/d/Projects/MC-XiaoHei/KyberLink/vectors/generated/ghash.json'))[0]
    h = int(v['h'], 16)
    blk = int(v['blocks'][0], 16)

    def rev(x):
        return int(f'{x:0128b}'[::-1], 2)

    a = rev(blk)
    b = rev(h)
    dut.a.value = a
    dut.b.value = b
    await Timer(1, units="ns")
    got = int(dut.p.value)
    print(f"P got={got:064x}")
