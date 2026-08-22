import datetime
import glob
import json
import os
import re
import shutil
import subprocess
import sys

from . import config

_gen_cache = None


def _gen_all():
    global _gen_cache
    if _gen_cache is not None:
        return _gen_cache
    seen = {}
    for mdiv in range(28, 57, 2):  # VCO 700-1400, clk_nrv=50 -> MDIV even
        for od0 in range(1, 128):
            for frac in range(8):
                f = 25.0 * mdiv / (od0 + frac / 8.0)
                if f < 1 or f > 1400:
                    continue
                seen[round(f, 4)] = (mdiv, od0, frac, mdiv // 2)
    _gen_cache = sorted((f, mdiv, od0, frac, od1)
                        for f, (mdiv, od0, frac, od1) in seen.items())
    return _gen_cache


def _match(target):
    best = None
    for f, mdiv, od0, frac, od1 in _gen_all():
        d = abs(f - target)
        if best is None or d < best[0]:
            best = (d, (f, mdiv, od0, frac, od1))
    return best


def list_freq(fmin=100.0, fmax=125.0):
    rows = [(f, m, o0, fr, o1) for f, m, o0, fr, o1 in _gen_all() if fmin <= f <= fmax]
    print("%-8s %4s %5s %4s %5s %7s" % ("freq", "MDIV", "ODIV0", "FRAC", "ODIV1", "VCO"))
    for f, mdiv, od0, frac, od1 in rows:
        print("%-8.4f %4d %5d %4d %5d %7d" % (f, mdiv, od0, frac, od1, 25 * mdiv))
    print("total %d (%.1f-%.1f MHz)" % (len(rows), fmin, fmax))


def _clk_ratio(mdiv, odiv0, odiv0_frac):
    num, den = 8 * mdiv, 16 * odiv0 + 2 * odiv0_frac
    for p in (2, 3, 5, 7, 11, 13):
        while num % p == 0 and den % p == 0:
            num, den = num // p, den // p
    return num, den


def _validate(freq, mdiv, odiv0, odiv0_frac, odiv1):
    vco = 25 * mdiv
    if not 700 <= vco <= 1400:
        raise ValueError("VCO %d out of range 700-1400" % vco)
    fdp = vco / (odiv0 + odiv0_frac / 8.0)
    fnrv = vco / odiv1
    if abs(fdp - freq) > 0.05:
        raise ValueError("clk_dp %.4f != GLOBAL_FREQ %.1f" % (fdp, freq))
    if abs(fnrv - 50) > 0.01:
        raise ValueError("clk_nrv %.2f != 50" % fnrv)
    if not (2 <= mdiv <= 128 and 1 <= odiv0 <= 128 and 0 <= odiv0_frac <= 7):
        raise ValueError("PLL parameter out of range: %d/%d/%d" % (mdiv, odiv0, odiv0_frac))


def pnr(dry_run=False, verify_only=False):
    gwsh = config.gw_sh()
    device = os.environ.get("DEVICE", "GW5A-LV25MG121NC1/I0")
    dev_ver = os.environ.get("DEVICE_VERSION", "A")
    place_opt = int(os.environ.get("PLACE_OPTION", "1"))
    route_opt = int(os.environ.get("ROUTE_OPTION", "2"))
    try:
        freq = float(os.environ.get("GLOBAL_FREQ", "110.0"))
    except ValueError:
        sys.exit("GLOBAL_FREQ must be numeric, got: %s" % os.environ.get("GLOBAL_FREQ"))
    err, (fact, mdiv, odiv0, odiv0_frac, odiv1) = _match(freq)
    if err > 0.1:
        sys.exit("GLOBAL_FREQ=%.3f: nearest feasible PLL config is %.4f MHz (off by %.3f); run 'run.py pnr --list-freq'"
                 % (freq, fact, err))
    try:
        _validate(fact, mdiv, odiv0, odiv0_frac, odiv1)
    except ValueError as e:
        sys.exit("GLOBAL_FREQ=%s invalid: %s" % (freq, e))
    sdc = os.path.join(config.SYNTH, "timing.sdc")
    cst = os.path.join(config.SYNTH, "full_top.cst")
    work = os.path.join(config.BUILD, "synth", "impl" + os.environ.get("PNR_WORK", ""))
    results_dir = os.path.join(config.LOGS, "pnr")

    def gen_clk_cfg():
        os.makedirs(os.path.join(config.BUILD, "synth"), exist_ok=True)
        path = os.path.join(config.BUILD, "synth", "hw_clk_cfg.v")
        with open(path, "w") as f:
            f.write("`define CLK_MDIV %d\n" % mdiv)
            f.write("`define CLK_ODIV0 %d\n" % odiv0)
            f.write("`define CLK_ODIV0_FRAC %d\n" % odiv0_frac)
            f.write("`define CLK_ODIV1 %d\n" % odiv1)
        return path

    def gen_sdc():
        num, den = _clk_ratio(mdiv, odiv0, odiv0_frac)
        out = []
        for ln in open(sdc):
            if "clk_dp" in ln and "multiply_by" in ln:
                ln = re.sub(r"-multiply_by \d+ -divide_by \d+",
                            "-multiply_by %d -divide_by %d" % (num, den), ln)
            out.append(ln)
        path = os.path.join(config.BUILD, "synth", "timing_gen.sdc")
        with open(path, "w") as f:
            f.writelines(out)
        return path

    def collect_sources():
        files = []
        for ext in ("*.v", "*.vhd"):
            files += glob.glob(os.path.join(config.RTL, "**", ext), recursive=True)
        return sorted(f.replace("\\", "/") for f in files)

    def build_tcl(cfg_path, sdc_path):
        files = collect_sources()
        lines = [
            "set_device %s -name GW5A-25 -device_version %s" % (device, dev_ver),
            "set_option -global_freq %s" % freq,
            "set_option -include_path %s" % os.path.join(config.BUILD, "synth").replace("\\", "/"),
            "set_option -top_module full_top",
            "set_option -compiler_compatible 1",
            "set_option -resolve_multiple_driver 1",
            "set_option -place_option %d" % place_opt,
            "set_option -timing_driven 1",
            "set_option -route_option %d" % route_opt,
            "set_option -use_sspi_as_gpio 1",
            "set_option -use_cpu_as_gpio 1",
            "set_option -use_mspi_as_gpio 1",
            "set_option -use_ready_as_gpio 1",
            "set_option -use_done_as_gpio 1",
        ]
        for i in range(0, len(files), 8):
            lines.append("add_file " + " ".join(files[i:i + 8]))
        lines.append("add_file " + sdc_path.replace("\\", "/"))
        if os.path.exists(cst):
            lines.append("add_file " + cst.replace("\\", "/"))
        lines.append("run all")
        return "\n".join(lines) + "\n", files

    def parse_timing(path):
        sections = []
        cur = None
        for raw in open(path, errors="replace"):
            ln = raw.strip()
            if ln == "=====":
                if cur is not None and cur.get("slack") is not None:
                    sections.append(cur)
                cur = {"type": "?", "slack": None}
            elif cur is not None:
                if ln in ("SETUP", "HOLD"):
                    cur["type"] = ln
                elif cur["slack"] is None and re.fullmatch(r"-?\d+\.\d+", ln):
                    cur["slack"] = float(ln)
        if cur is not None and cur.get("slack") is not None:
            sections.append(cur)
        return sections

    def parse_rpt(path):
        txt = open(path, errors="replace").read()
        out = {}
        m = re.search(r"--LUT,ALU,ROM16</td>\s*<td>([^<]+)</td>", txt)
        if m:
            out["lut_alu_rom16"] = m.group(1).strip()
        m = re.search(r"<td class=\"label\">Register</td>\s*<td>([^<]+)</td>", txt)
        if m:
            out["register"] = m.group(1).strip()
        m = re.search(r"<td class=\"label\">BSRAM</td>\s*<td>([^<]+)</td>", txt)
        if m:
            out["bsram"] = m.group(1).strip()
        return out

    def report(timing, rpt, save):
        if not os.path.exists(timing):
            print("timing_paths not found", file=sys.stderr)
            return False
        secs = parse_timing(timing)
        res = parse_rpt(rpt) if os.path.exists(rpt) else {}
        slacks = [s["slack"] for s in secs]
        worst = min(slacks)
        wt = [s["type"] for s in secs if s["slack"] == worst][0]
        print("paths %d" % len(secs))
        print("worst %+.3fns (%s)" % (worst, wt))
        for s in secs:
            print("%s %+.3f" % (s["type"], s["slack"]))
        for k, v in res.items():
            print("%s %s" % (k, v))
        if save:
            os.makedirs(results_dir, exist_ok=True)
            name = os.path.join(results_dir, "pnr_" +
                                datetime.datetime.now().strftime("%Y%m%d_%H%M%S") + ".json")
            payload = {
                "device": device, "device_version": dev_ver,
                "place_option": place_opt, "route_option": route_opt,
                "global_freq": freq,
                "paths": [{"type": s["type"], "slack": s["slack"]} for s in secs],
                "worst_slack": worst, "resources": res,
            }
            json.dump(payload, open(name, "w"), indent=2)
            print("saved %s" % name)
        return worst >= 0

    def force_rmtree(path):
        def onerr(func, p, exc):
            os.chmod(p, 0o666)
            func(p)
        shutil.rmtree(path, onerror=onerr)

    pnr_dir = os.path.join(work, "impl", "pnr")
    timing = os.path.join(pnr_dir, "project.timing_paths")
    rpt = os.path.join(pnr_dir, "project.rpt.html")

    if verify_only:
        return 0 if report(timing, rpt, save=False) else 1
    if not os.path.exists(gwsh):
        print("gw_sh not found: %s" % gwsh, file=sys.stderr)
        return 2

    cfg_path = gen_clk_cfg()
    sdc_path = gen_sdc()
    tcl_text, files = build_tcl(cfg_path, sdc_path)
    if dry_run:
        print("%s v%s place=%d route=%d target=%.4fMHz actual=%.4fMHz PLL=%d/%d%s/%d" %
              (device, dev_ver, place_opt, route_opt, freq, fact, mdiv, odiv0,
               "+%d/8" % odiv0_frac if odiv0_frac else "", odiv1))
        print("sources %d" % len(files))
        print("--- build.tcl ---")
        print(tcl_text)
        return 0

    if os.path.isdir(work):
        force_rmtree(work)
    os.makedirs(work)
    tcl_path = os.path.join(work, "build.tcl")
    with open(tcl_path, "w") as f:
        f.write(tcl_text)

    log_path = os.path.join(work, "pnr.log")
    with open(log_path, "w") as log:
        rc = subprocess.run([gwsh, tcl_path], cwd=work,
                            stdout=log, stderr=subprocess.STDOUT).returncode
    print("gw_sh exit %d" % rc)
    if rc != 0:
        return 1
    return 0 if report(timing, rpt, save=True) else 1
