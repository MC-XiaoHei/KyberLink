import json
import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "..", "vectors", "generated")
VECTORS = os.path.join(VECDIR, "mldsa_sign_mid.json")

PH_NAMES = {}


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.start.value = 0
    await Timer(25, units="ns")
    dut.rst_n.value = 1
    await Timer(2, units="ns")


@cocotb.test()
async def test_sign_vectors(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    with open(VECTORS) as f:
        vecs = json.load(f)

    rng = os.environ.get("VEC_RANGE", "")
    if rng:
        if "-" in rng:
            a, b = rng.split("-")
            vecs = vecs[int(a):int(b) + 1]
        else:
            sel = {int(x) for x in rng.split(",")}
            vecs = [v for v in vecs if int(v["index"]) in sel]

    for v in vecs:
        sk = bytes.fromhex(v["sk"])
        mu = bytes.fromhex(v["mu_b"])
        exp_sig = bytes.fromhex(v["sig"])

        dut.sk_in.value = int.from_bytes(sk, "big")
        dut.mu_b.value = int.from_bytes(mu, "big")
        dut.rnd_in.value = 0

        dut.start.value = 1
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        dut.start.value = 0

        ncyc = 0
        nlast = 0
        while int(dut.done.value) != 1:
            await RisingEdge(dut.clk)
            ncyc += 1
            if ncyc - nlast >= 50000:
                nlast = ncyc
                try:
                    ph = int(dut.u_dut.phase.value)
                except Exception:
                    ph = -1
                try:
                    kappa = int(dut.u_dut.kappa_r.value)
                except Exception:
                    kappa = -1
                print(f"PROG idx={v['index']} cyc={ncyc} phase={ph} kappa={kappa}", flush=True)
        await Timer(1, units="ns")

        got = bytes(int(dut.u_dut.sig_byte[i].value) for i in range(3309))
        nmis = sum(1 for i in range(3309) if got[i] != exp_sig[i])
        print(f"idx={v['index']} cyc={ncyc} nmis={nmis}")
        if nmis == 0:
            print(f"  IDX{v['index']} SIG MATCH")
        else:
            for i in range(3309):
                if got[i] != exp_sig[i]:
                    print(f"  byte[{i}] got={got[i]:02x} exp={exp_sig[i]:02x}")
                    if i > 60:
                        break
        assert nmis == 0, f"idx={v['index']} sig mismatch"
