import json
import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

VECDIR = os.path.join(os.path.dirname(__file__), "..", "..", "..", "vectors", "generated")
VECTORS = os.path.join(VECDIR, "mldsa_sign_mid.json")


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.start.value = 0
    await Timer(25, units="ns")
    dut.rst_n.value = 1
    await Timer(2, units="ns")


def cmp_arr(arr, ref, name):
    bad = 0
    for i in range(len(ref)):
        got = int(arr[i].value)
        exp = ref[i]
        if got != exp:
            if bad < 4:
                print(f"  {name}[{i}] got={got} exp={exp}", flush=True)
            bad += 1
    return bad


@cocotb.test()
async def cmp_sign(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    with open(VECTORS) as f:
        vecs = json.load(f)
    rng = os.environ.get("VEC_RANGE", "")
    if rng:
        sel = {int(x) for x in rng.split(",")}
        vecs = [v for v in vecs if int(v["index"]) in sel]
    v = vecs[0]
    print(f"VEC idx={v['index']} kappa={v['kappa']}", flush=True)
    sk = bytes.fromhex(v["sk"])
    mu = bytes.fromhex(v["mu_b"])

    dut.sk_in.value = int.from_bytes(sk, "big")
    dut.mu_b.value = int.from_bytes(mu, "big")
    dut.rnd_in.value = 0

    dut.start.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    dut.start.value = 0

    ncyc = 0
    last_ph = -1
    pz = pw = pc = 1
    while int(dut.done.value) != 1:
        await RisingEdge(dut.clk)
        ncyc += 1
        if ncyc > 4000000:
            print("LIMIT", flush=True)
            break
        ph = int(dut.u_dut.phase.value)
        kappa = int(dut.u_dut.kappa_r.value)
        if ph == 26 and kappa == 15 and ph != last_ph:
            print("HINT phase enter, wgt_r=%d" % int(dut.u_dut.wgt_r.value), flush=True)
        if ph == 26 and kappa == 15:
            cnt = int(dut.u_dut.cnt2.value)
            hh = int(dut.u_dut.hh_v.value)
            if hh == 1 or (cnt < 1536 and v["hh"][cnt] == 1):
                print(f"  HINT cnt2={cnt} hh={hh} h_a={int(dut.u_dut.h_a.value)} h_b={int(dut.u_dut.h_b.value)} "
                      f"wcs2={int(dut.u_dut.wcs2_arr[cnt].value)} ct0={int(dut.u_dut.ct0_arr[cnt].value)} "
                      f"exp_hh={v['hh'][cnt]}", flush=True)
        zz = int(dut.u_dut.zz_ok.value)
        ww = int(dut.u_dut.wcs2_ok.value)
        cc = int(dut.u_dut.ct0_ok.value)
        if kappa == 15:
            if pz == 1 and zz == 0:
                print(f"ZZ_FALL cyc={ncyc} ph={ph} cnt2={int(dut.u_dut.cnt2.value)} zzc={int(dut.u_dut.zz_cen.value)}", flush=True)
            if pw == 1 and ww == 0:
                ci = int(dut.u_dut.cnt2.value)
                sub = int(dut.u_dut.wcs2_sub.value)
                r0a = int(dut.u_dut.wcs2_r0a.value)
                vec = v["w_minus_cs2"][ci] if ci < len(v["w_minus_cs2"]) else -1
                print(f"W_FALL cyc={ncyc} ph={ph} cnt2={ci} sub={sub} r0a={r0a} vec={vec}", flush=True)
            if pc == 1 and cc == 0:
                print(f"C_FALL cyc={ncyc} ph={ph} cnt2={int(dut.u_dut.cnt2.value)} ct0c={int(dut.u_dut.ct0_cen.value)}", flush=True)
        pz, pw, pc = zz, ww, cc
        if kappa == 15 and ph != last_ph:
            if ph == 10:
                print("CMP ph=10 y", flush=True)
                print(f"  y bad={cmp_arr(dut.u_dut.y_arr, v['y'], 'y')}", flush=True)
            elif ph == 11:
                print("CMP ph=11 y_hat", flush=True)
                print(f"  y_hat bad={cmp_arr(dut.u_dut.y_hat, v['y_hat'], 'y_hat')}", flush=True)
            elif ph == 13:
                print("CMP ph=13 w", flush=True)
                print(f"  w bad={cmp_arr(dut.u_dut.w_arr, v['w'], 'w')}", flush=True)
            elif ph == 14:
                print("CMP ph=14 w1", flush=True)
                print(f"  w1 bad={cmp_arr(dut.u_dut.w1_arr, v['w1'], 'w1')}", flush=True)
            elif ph == 16:
                print("CMP ph=16 c", flush=True)
                print(f"  c bad={cmp_arr(dut.u_dut.c_arr, v['c'], 'c')}", flush=True)
                exp_ct = bytes.fromhex(v["c_tilde"])
                bct = 0
                for i in range(48):
                    if int(dut.u_dut.c_tilde[i].value) != exp_ct[i]:
                        if bct < 4:
                            print(f"  c_tilde[{i}] got={int(dut.u_dut.c_tilde[i].value):02x} exp={exp_ct[i]:02x}", flush=True)
                        bct += 1
                print(f"  c_tilde bad={bct}", flush=True)
            elif ph == 18:
                print("CMP ph=18 c_hat", flush=True)
                print(f"  c_hat bad={cmp_arr(dut.u_dut.c_hat, v['c_hat'], 'c_hat')}", flush=True)
            elif ph == 20:
                print("CMP ph=20 cs1", flush=True)
                print(f"  cs1 bad={cmp_arr(dut.u_dut.cs1_arr, v['cs1'], 'cs1')}", flush=True)
            elif ph == 22:
                print("CMP ph=22 cs2", flush=True)
                print(f"  cs2 bad={cmp_arr(dut.u_dut.cs2_arr, v['cs2'], 'cs2')}", flush=True)
            elif ph == 23:
                print("CMP ph=23 zz", flush=True)
                print(f"  zz bad={cmp_arr(dut.u_dut.zz_arr, v['zz'], 'zz')}", flush=True)
            elif ph == 24:
                print("CMP ph=24 wcs2", flush=True)
                print(f"  wcs2 bad={cmp_arr(dut.u_dut.wcs2_arr, v['w_minus_cs2'], 'wcs2')}", flush=True)
            elif ph == 26:
                print("CMP ph=26 ct0", flush=True)
                print(f"  ct0 bad={cmp_arr(dut.u_dut.ct0_arr, v['ct0'], 'ct0')}", flush=True)
                print(f"  wgt_r={int(dut.u_dut.wgt_r.value)}", flush=True)
                bh = 0
                cnt = int(dut.u_dut.cnt2.value)
                for i in range(0, min(1536, cnt), 64):
                    if int(dut.u_dut.hh_bool[i].value) != v["hh"][i]:
                        if bh < 4:
                            print(f"  hh[{i}] got={int(dut.u_dut.hh_bool[i].value)} exp={v['hh'][i]}", flush=True)
                        bh += 1
                print(f"  hh sampled bad={bh}", flush=True)
            elif ph == 28:
                print("CMP ph=28 OUTZ", flush=True)
                exp_ct = bytes.fromhex(v["c_tilde"])
                bct = 0
                for i in range(48):
                    if int(dut.u_dut.sig_byte[i].value) != exp_ct[i]:
                        if bct < 4:
                            print(f"  sig_byte[{i}] got={int(dut.u_dut.sig_byte[i].value):02x} exp={exp_ct[i]:02x}", flush=True)
                        bct += 1
                print(f"  c_tilde bad={bct}", flush=True)
            elif ph == 29:
                print("CMP ph=29 OUTH", flush=True)
                exp_sig = bytes.fromhex(v["sig"])
                bsg = 0
                errpos = []
                for i in range(3309):
                    if int(dut.u_dut.sig_byte[i].value) != exp_sig[i]:
                        errpos.append(i)
                        bsg += 1
                print(f"  sig_byte bad={bsg}", flush=True)
                if errpos:
                    print(f"  err_pos={errpos[:30]}", flush=True)
                ct_bad = sum(1 for i in range(48) if int(dut.u_dut.c_tilde[i].value) != exp_sig[i])
                print(f"  c_tilde arr bad={ct_bad}", flush=True)
                print(f"  sig48={int(dut.u_dut.sig_byte[48].value):02x}", flush=True)
                print(f"  sig3248={int(dut.u_dut.sig_byte[3248].value):02x}", flush=True)
                print(f"  cnt={int(dut.u_dut.cnt.value)} cnt2={int(dut.u_dut.cnt2.value)} hcut={int(dut.u_dut.hcut_pos.value)}", flush=True)
        last_ph = ph
    await Timer(1, units="ns")
    print("END", flush=True)
    exp_sig = bytes.fromhex(v["sig"])
    got = int(dut.sig_out.value).to_bytes(3309, "big")
    nmis = sum(1 for i in range(3309) if got[i] != exp_sig[i])
    print(f"DONE_SIG nmis={nmis}", flush=True)
    for i in range(3309):
        if got[i] != exp_sig[i]:
            seg = "ct" if i < 48 else ("z" if i < 3248 else "hint")
            print(f"  sig[{i}] seg={seg} got={got[i]:02x} exp={exp_sig[i]:02x}", flush=True)
            if i > 3260 and i < 3248:
                break
    bct = 0
    for i in range(48):
        if int(dut.u_dut.c_tilde[i].value) != exp_sig[i]:
            bct += 1
    print(f"DONE_CTILDE bad={bct}", flush=True)
    bsg = 0
    for i in range(3309):
        if int(dut.u_dut.sig_byte[i].value) != exp_sig[i]:
            bsg += 1
    print(f"DONE_SIGBYTE bad={bsg}", flush=True)
    for i in range(3248, 3309):
        g = int(dut.u_dut.sig_byte[i].value)
        if g != exp_sig[i]:
            print(f"  hint[{i}] got={g:02x} exp={exp_sig[i]:02x}", flush=True)
    sov = int(dut.sig_out.value)
    print(f"DONE_SIGOUT int={sov}", flush=True)
    print(f"DONE_SIGOUT hex_top={hex(sov >> (26471-63)) if sov else 'zero'}", flush=True)
    print(f"DONE_SIGBYTE0={int(dut.u_dut.sig_byte[0].value)}", flush=True)
    print(f"DONE_SIGBYTE1={int(dut.u_dut.sig_byte[1].value)}", flush=True)
