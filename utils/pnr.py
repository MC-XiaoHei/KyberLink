import glob
import os
import re
import shutil
import subprocess

from . import config
from .core import AppError, Result


def gen_sdc(out_dir):
    sdc_src = os.environ.get("PNR_SDC_SRC") or os.path.join(config.SYNTH, "timing.sdc")
    path = os.path.join(out_dir, "timing.sdc")
    shutil.copyfile(sdc_src, path)
    return path


def build_tcl(sdc_path, cst, device, dev_ver, place_opt, route_opt, top=None, extra=()):
    top = top or os.environ.get("PNR_TOP", "kyberlink_top")
    files = _source_files(extra)
    lines = _option_lines(sdc_path, device, dev_ver, place_opt, route_opt, top)
    lines += _file_lines(files, sdc_path, cst)
    lines.append("run all")
    return "\n".join(lines) + "\n", files


def _source_files(extra=()):
    files = []
    for ext in ("*.v", "*.vhd"):
        files += glob.glob(os.path.join(config.RTL, "**", ext), recursive=True)
    files = [f.replace("\\", "/") for f in files]
    top_src = os.environ.get("PNR_TOP_SRC")
    if top_src:
        top = os.path.join(config.RTL, "kyberlink_top.v").replace("\\", "/")
        if top in files:
            files.remove(top)
        files.append(os.path.abspath(top_src).replace("\\", "/"))
    for path in extra:
        files.append(os.path.abspath(path).replace("\\", "/"))
    return sorted(files)


def _option_lines(sdc_path, device, dev_ver, place_opt, route_opt, top):
    lines = [
        "set_device %s -name %s -device_version %s"
        % (device, os.environ.get("DEVICE_NAME", "GW5A-25"), dev_ver),
        "set_option -include_path %s" % os.path.dirname(sdc_path).replace("\\", "/"),
        "set_option -top_module %s" % top,
        "set_option -compiler_compatible 1",
        "set_option -resolve_multiple_driver 1",
        "set_option -place_option %d" % place_opt,
        "set_option -timing_driven %s" % os.environ.get("PNR_TIMING_DRIVEN", "1"),
        "set_option -route_option %d" % route_opt,
        "set_option -opt_goal %s" % os.environ.get("PNR_OPT_GOAL", "auto"),
    ]
    lines += _env_option_lines()
    if os.environ.get("PNR_RETIMING"):
        lines.append("set_option -retiming 1")
    lines += [
        "set_option -multi_boot 1",
        "set_option -multiboot_spi_flash_address 000000",
        "set_option -use_sspi_as_gpio 1",
        "set_option -use_cpu_as_gpio 1",
        "set_option -use_i2c_as_gpio 1",
    ]
    return lines


ENV_OPTIONS = (
    ("resource_sharing", "PNR_RESOURCE_SHARING"),
    ("maxfan", "PNR_MAXFAN"),
    ("route_maxfan", "PNR_ROUTE_MAXFAN"),
    ("replicate_resources", "PNR_REPLICATE"),
    ("clock_route_order", "PNR_CLOCK_ROUTE_ORDER"),
    ("fix_gated_and_generated_clocks", "PNR_FIX_GATED_CLK"),
    ("global_freq", "PNR_GLOBAL_FREQ"),
    ("bsram_simple_ce", "PNR_BSRAM_SIMPLE_CE"),
    ("convert_sdp32_36_to_sdp16_18", "PNR_CONVERT_SDP"),
    ("inc_place", "PNR_INC_PLACE"),
    ("inc_pnr", "PNR_INC_PNR"),
    ("map_option", "PNR_MAP_OPTION"),
)


def _env_option_lines():
    lines = []
    for opt, env in ENV_OPTIONS:
        value = os.environ.get(env)
        if value:
            lines.append("set_option -%s %s" % (opt, value))
    return lines


def _file_lines(files, sdc_path, cst):
    lines = []
    for i in range(0, len(files), 8):
        lines.append("add_file " + " ".join(files[i : i + 8]))
    lines.append("add_file " + sdc_path.replace("\\", "/"))
    if os.path.exists(cst):
        lines.append("add_file " + cst.replace("\\", "/"))
    return lines


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


def _archive_artifacts(work_dir):
    rd = config.run_dir()
    if not rd:
        return
    _archive(work_dir, "impl/gwsynthesis", rd, "syn_", (".html", ".xml", ".log", ".vg"), {})
    _archive(
        work_dir,
        "impl/pnr",
        rd,
        "pnr_",
        (".html", ".xml", ".log", ".txt"),
        {
            "project.rpt.html": "pnr.rpt.html",
            "project.timing_paths": "pnr.timing_paths",
        },
    )


def _archive(work_dir, sub, rd, prefix, suffixes, renames):
    src_dir = os.path.join(work_dir, *sub.split("/"))
    if not os.path.isdir(src_dir):
        return
    for name in sorted(os.listdir(src_dir)):
        path = os.path.join(src_dir, name)
        if not os.path.isfile(path):
            continue
        if name in renames:
            shutil.copy2(path, os.path.join(rd, renames[name]))
        elif name.endswith(suffixes):
            shutil.copy2(path, os.path.join(rd, prefix + name))


def pnr_run(
    target, place_opt, route_opt, device, dev_ver, work_dir, log_path, cst=None, top=None, extra=()
):
    if os.path.isdir(work_dir):
        force_rmtree(work_dir)
    os.makedirs(work_dir)
    sdc_path = gen_sdc(work_dir)
    tcl_text, files = build_tcl(sdc_path, cst, device, dev_ver, place_opt, route_opt, top, extra)
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
    run = {"req_freq": target}
    _archive_artifacts(work_dir)
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


def _log_path(work_dir):
    if os.environ.get("PNR_WORK_DIR"):
        return os.path.join(work_dir, "pnr.log")
    rd = config.run_dir()
    return os.path.join(rd or work_dir, "pnr.log")


def pnr(top=None, extra=(), work_dir=None, cmd="pnr"):
    device = os.environ.get("DEVICE", "GW5A-LV25MG121NC1/I0")
    dev_ver = os.environ.get("DEVICE_VERSION", "A")
    place_opt = int(os.environ.get("PLACE_OPTION", "1"))
    route_opt = int(os.environ.get("ROUTE_OPTION", "2"))
    target = float(os.environ.get("TARGET_FREQ", "125.0"))
    if target < 1 or target > 800:
        raise AppError("TARGET_FREQ out of range: %s" % target, 2)
    work_dir = os.path.abspath(
        work_dir or os.environ.get("PNR_WORK_DIR") or os.path.join(config.BUILD, "synth", "impl")
    )
    log_path = _log_path(work_dir)
    cst = os.path.join(config.SYNTH, "kyberlink_top.cst")
    run = pnr_run(
        target,
        place_opt,
        route_opt,
        device,
        dev_ver,
        work_dir,
        log_path,
        cst=cst,
        top=top,
        extra=extra,
    )
    cfg = {
        "target": target,
        "place": place_opt,
        "route": route_opt,
        "runs": [run],
    }
    ok = run["status"] == "ok"
    worst = run.get("worst_slack")
    return Result(
        cmd,
        "ok" if ok else "fail",
        config=cfg,
        metrics={"worst_slack": worst, "paths": run.get("paths", [])},
        artifacts={"timing": run.get("timing"), "log": run.get("log")},
        error=None if ok else "timing failed",
    ).finish()
