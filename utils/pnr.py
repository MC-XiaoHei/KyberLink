import datetime
import glob
import json
import os
import re
import shutil
import subprocess
import sys

from . import config


def pnr(dry_run=False, verify_only=False):
    gwsh = config.gw_sh()
    device = os.environ.get("DEVICE", "GW5A-LV25MG121NC1/I0")
    dev_ver = os.environ.get("DEVICE_VERSION", "A")
    place_opt = int(os.environ.get("PLACE_OPTION", "1"))
    route_opt = int(os.environ.get("ROUTE_OPTION", "2"))
    freq = int(os.environ.get("GLOBAL_FREQ", "120"))
    sdc = os.path.join(config.SYNTH, "timing.sdc")
    cst = os.path.join(config.SYNTH, "full_top.cst")
    work = os.path.join(config.BUILD, "synth", "impl" + os.environ.get("PNR_WORK", ""))
    results_dir = os.path.join(config.LOGS, "pnr")

    def collect_sources():
        files = []
        for ext in ("*.v", "*.vhd"):
            files += glob.glob(os.path.join(config.RTL, "**", ext), recursive=True)
        return sorted(f.replace("\\", "/") for f in files)

    def build_tcl():
        files = collect_sources()
        lines = [
            "set_device %s -name GW5A-25 -device_version %s" % (device, dev_ver),
            "set_option -global_freq %d" % freq,
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
        lines.append("add_file " + sdc.replace("\\", "/"))
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

    tcl_text, files = build_tcl()
    if dry_run:
        print("%s v%s place=%d freq=%dMHz" % (device, dev_ver, place_opt, freq))
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
