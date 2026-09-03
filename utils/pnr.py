import glob
import os
import re
import shutil
import subprocess

from . import config
from .core import AppError, Result

_gen_cache = None


def _gen_all():
    global _gen_cache
    if _gen_cache is not None:
        return _gen_cache
    seen = {}
    for mdiv in range(28, 57, 2):
        for od0 in range(1, 128):
            for frac in range(8):
                f = 25.0 * mdiv / (od0 + frac / 8.0)
                if f < 1 or f > 1400:
                    continue
                seen[round(f, 4)] = (mdiv, od0, frac, mdiv // 2)
    _gen_cache = sorted((f, mdiv, od0, frac, od1) for f, (mdiv, od0, frac, od1) in seen.items())
    return _gen_cache


def _match(target):
    best = None
    for f, mdiv, od0, frac, od1 in _gen_all():
        d = abs(f - target)
        if best is None or d < best[0]:
            best = (d, (f, mdiv, od0, frac, od1))
    return best


def _match_info(req):
    dist, (f, mdiv, od0, frac, od1) = _match(req)
    return {
        "req_freq": req,
        "freq": f,
        "mdiv": mdiv,
        "odiv0": od0,
        "odiv0_frac": frac,
        "freq_error": abs(f - req),
    }


def _freq_id(f):
    return ("%.1f" % f).replace(".", "_")


def _ratio_simple(freq):
    num, den = round(freq * 1000), 50000
    g = _gcd(num, den)
    return num // g, den // g


def _gcd(a, b):
    while b:
        a, b = b, a % b
    return a


def gen_clk_cfg(boot, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "hw_clk_cfg.v")
    cpu_boot = float(os.environ.get("CPU_FREQ", "75.0"))
    mac_f = 125.0
    _, (cf, cm, co0, cfr, co1) = _match(cpu_boot)
    _, (mf, mm, mo0, mfr, mo1) = _match(mac_f)
    dm, do0, dfr = (
        _match_info(boot)["mdiv"],
        _match_info(boot)["odiv0"],
        _match_info(boot)["odiv0_frac"],
    )
    with open(path, "w") as f:
        f.write("`define CPU_CLOCK_HZ %d\n" % int(cpu_boot * 1e6))
        f.write("`define DATA_MDIV %d\n" % dm)
        f.write("`define DATA_ODIV0 %d\n" % do0)
        f.write("`define DATA_ODIV0_FRAC %d\n" % dfr)
        f.write("`define DATA_ODIV1 %d\n" % do0)
        f.write("`define CLK_MDIV %d\n" % dm)
        f.write("`define CLK_ODIV0 %d\n" % do0)
        f.write("`define CLK_ODIV0_FRAC %d\n" % dfr)
        f.write("`define CLK_ODIV1 %d\n" % (dm // 2))
        for pfx, (pm, po0, pfr, po1) in (
            ("CPU", (cm, co0, cfr, co1)),
            ("MAC", (mm, mo0, mfr, mo1)),
        ):
            f.write("`define %s_MDIV %d\n" % (pfx, pm))
            f.write("`define %s_ODIV0 %d\n" % (pfx, po0))
            f.write("`define %s_ODIV0_FRAC %d\n" % (pfx, pfr))
            f.write("`define %s_ODIV1 %d\n" % (pfx, po1))
    return path


def gen_sdc(target, out_dir):
    sdc_src = os.environ.get("PNR_SDC_SRC") or os.path.join(config.SYNTH, "timing.sdc")
    out = []
    num, den = _ratio_simple(target)
    cpu_freq = float(os.environ.get("CPU_FREQ", "75.0"))
    cn, cd = _ratio_simple(cpu_freq)
    for ln in open(sdc_src):
        if "clk_dp" in ln and "create_generated_clock" in ln:
            ln = re.sub(r"-multiply_by \d+", "-multiply_by %d" % num, ln)
            ln = re.sub(r"-divide_by \d+", "-divide_by %d" % den, ln)
        elif "clk_nrv" in ln and "create_generated_clock" in ln:
            ln = re.sub(r"-multiply_by \d+", "-multiply_by %d" % cn, ln)
            ln = re.sub(r"-divide_by \d+", "-divide_by %d" % cd, ln)
        out.append(ln)
    path = os.path.join(out_dir, "timing_gen.sdc")
    with open(path, "w") as f:
        f.writelines(out)
    return path


def build_tcl(cfg_path, sdc_path, cst, target, device, dev_ver, place_opt, route_opt):
    top_src = os.environ.get("PNR_TOP_SRC")
    files = []
    for ext in ("*.v", "*.vhd"):
        files += glob.glob(os.path.join(config.RTL, "**", ext), recursive=True)
    files = [f.replace("\\", "/") for f in files]
    if top_src:
        file_top = os.path.join(config.RTL, "full_top.v").replace("\\", "/")
        if file_top in files:
            files.remove(file_top)
        files.append(os.path.abspath(top_src).replace("\\", "/"))
    files = sorted(files)
    lines = [
        "set_device %s -name %s -device_version %s"
        % (device, os.environ.get("DEVICE_NAME", "GW5A-25"), dev_ver),
        "set_option -global_freq %s" % target,
        "set_option -include_path %s" % os.path.dirname(cfg_path).replace("\\", "/"),
        "set_option -top_module full_top",
        "set_option -compiler_compatible 1",
        "set_option -resolve_multiple_driver 1",
        "set_option -place_option %d" % place_opt,
        "set_option -timing_driven 1",
        "set_option -route_option %d" % route_opt,
    ]
    if os.environ.get("PNR_RETIMING"):
        lines.append("set_option -retiming 1")
    lines += [
        "set_option -use_sspi_as_gpio 1",
        "set_option -use_cpu_as_gpio 1",
        "set_option -use_mspi_as_gpio 1",
        "set_option -use_ready_as_gpio 1",
        "set_option -use_done_as_gpio 1",
    ]
    for i in range(0, len(files), 8):
        lines.append("add_file " + " ".join(files[i : i + 8]))
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


def report(timing, rpt):
    if not os.path.exists(timing):
        return False, {}, None, []
    secs = parse_timing(timing)
    res = parse_rpt(rpt) if os.path.exists(rpt) else {}
    slacks = [s["slack"] for s in secs]
    worst = min(slacks)
    wt = [s["type"] for s in secs if s["slack"] == worst][0]
    print(f"paths {len(secs)}")
    print(f"worst {worst:+.3f}ns ({wt})")
    for s in secs:
        print(f"{s['type']} {s['slack']:+.3f}")
    for k, v in res.items():
        print(f"{k} {v}")
    return worst >= 0, res, worst, [{"type": s["type"], "slack": s["slack"]} for s in secs]


def force_rmtree(path):
    def onerr(func, p, exc):
        os.chmod(p, 0o666)
        func(p)

    shutil.rmtree(path, onerror=onerr)


def _archive_artifacts(work_dir, fid):
    rd = config.run_dir()
    if not rd:
        return
    gws = os.path.join(work_dir, "impl", "gwsynthesis")
    if os.path.isdir(gws):
        for nm in sorted(os.listdir(gws)):
            p = os.path.join(gws, nm)
            if os.path.isfile(p) and nm.endswith((".html", ".xml", ".log", ".vg")):
                shutil.copy2(p, os.path.join(rd, "syn_%s_%s" % (fid, nm)))
    pnr_dir = os.path.join(work_dir, "impl", "pnr")
    if os.path.isdir(pnr_dir):
        for nm in sorted(os.listdir(pnr_dir)):
            p = os.path.join(pnr_dir, nm)
            if not os.path.isfile(p):
                continue
            if nm == "project.rpt.html":
                shutil.copy2(p, os.path.join(rd, "pnr_%s.rpt.html" % fid))
            elif nm == "project.timing_paths":
                shutil.copy2(p, os.path.join(rd, "pnr_%s.timing_paths" % fid))
            elif nm.endswith((".html", ".xml", ".log", ".txt")):
                shutil.copy2(p, os.path.join(rd, "pnr_%s_%s" % (fid, nm)))


def pnr_run(freq, target, place_opt, route_opt, device, dev_ver, work_dir, log_path, cst=None):
    mi = _match_info(freq)
    if os.path.isdir(work_dir):
        force_rmtree(work_dir)
    os.makedirs(work_dir)
    cfg_path = gen_clk_cfg(mi["freq"], work_dir)
    sdc_path = gen_sdc(target, work_dir)
    tcl_text, files = build_tcl(
        cfg_path, sdc_path, cst, target, device, dev_ver, place_opt, route_opt
    )
    tcl_path = os.path.join(work_dir, "build.tcl")
    with open(tcl_path, "w") as f:
        f.write(tcl_text)
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    with open(log_path, "w") as log:
        rc = subprocess.run(
            [config.gw_sh(), tcl_path], cwd=work_dir, stdout=log, stderr=subprocess.STDOUT
        ).returncode
    pnr_dir = os.path.join(work_dir, "impl", "pnr")
    timing = os.path.join(pnr_dir, "project.timing_paths")
    rpt = os.path.join(pnr_dir, "project.rpt.html")
    run = dict(mi)
    _archive_artifacts(work_dir, _freq_id(freq))
    if rc != 0:
        run.update({"status": "fail", "worst_slack": None, "paths": [], "log": log_path})
        return run
    ok, res, worst, paths = report(timing, rpt)
    run.update(
        {
            "status": "ok" if ok else "fail",
            "worst_slack": worst,
            "paths": paths,
            "timing": timing,
            "log": log_path,
        }
    )
    if worst is not None:
        run["d_max_ns"] = round(1000.0 / target - worst, 4)
    return run


def pnr():
    device = os.environ.get("DEVICE", "GW5A-LV25MG121NC1/I0")
    dev_ver = os.environ.get("DEVICE_VERSION", "A")
    place_opt = int(os.environ.get("PLACE_OPTION", "1"))
    route_opt = int(os.environ.get("ROUTE_OPTION", "2"))
    target = float(os.environ.get("TARGET_FREQ", "125.0"))
    boot = float(os.environ.get("BOOT_FREQ", "100.0"))
    if target < 1 or target > 800:
        raise AppError("TARGET_FREQ out of range: %s" % target, 2)
    if boot < 1 or boot > 1400:
        raise AppError("BOOT_FREQ out of range: %s" % boot, 2)
    work_dir = os.path.abspath(
        os.environ.get("PNR_WORK_DIR")
        or os.path.join(config.BUILD, "synth", "impl_" + _freq_id(boot))
    )
    log_path = (
        os.path.join(work_dir, "pnr.log")
        if os.environ.get("PNR_WORK_DIR")
        else (
            os.path.join(config.run_dir(), "pnr_%s.log" % _freq_id(boot))
            if config.run_dir()
            else os.path.join(work_dir, "pnr.log")
        )
    )
    cst = os.path.join(config.SYNTH, "full_top.cst")
    run = pnr_run(boot, target, place_opt, route_opt, device, dev_ver, work_dir, log_path, cst=cst)
    cfg = {
        "target": target,
        "boot": boot,
        "mode": "single",
        "place": place_opt,
        "route": route_opt,
        "runs": [run],
    }
    ok = run["status"] == "ok"
    worst = run.get("worst_slack")
    return Result(
        "pnr",
        "ok" if ok else "fail",
        config=cfg,
        metrics={"worst_slack": worst, "paths": run.get("paths", [])},
        artifacts={"timing": run.get("timing"), "log": run.get("log")},
        error=None if ok else "timing failed",
    ).finish()
