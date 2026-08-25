#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from utils import config
from utils.core import AppError, Result, Reporter, Tee


def wsl_path(win):
    drive, rest = os.path.splitdrive(win)
    return "/mnt/" + drive[0].lower() + rest.replace("\\", "/")


def wsl_run(args_list):
    import subprocess
    venv = os.environ.get("WSL_VENV", "$HOME/kyberlink-venv")
    ver = os.environ.get("WSL_VERILATOR", "$HOME/verilator-532/bin")
    script = ("export PATH=\"%s:$PATH\"; cd %s; exec %s/bin/python run.py %s" %
              (ver, wsl_path(config.REPO), venv, " ".join(args_list)))
    rc = subprocess.call(["wsl", "--", "bash", "-lc", script])
    raise SystemExit(rc)


def wsl_sim(args):
    wsl_run(["sim", args.mod] + (["--testcase", args.testcase] if args.testcase else []))


def dispatch(args, reporter):
    if args.cmd == "sim":
        if os.name == "nt":
            return wsl_sim(args)
        from utils.sim import sim, sim_all
        if args.mod == "all":
            return sim_all(args.testcase)
        return sim(args.mod, args.testcase)
    if args.cmd == "pnr":
        from utils.pnr import pnr, pnr_multi, analyze
        if args.analyze:
            return analyze()
        if args.freqs:
            freqs = [float(x) for x in args.freqs.split(",")]
            return pnr_multi(freqs, args.jobs, dry_run=args.dry_run)
        return pnr(dry_run=args.dry_run, verify_only=args.verify_only)
    if args.cmd == "cross":
        from utils.cross import cross
        return cross(args.mode)
    if args.cmd == "nrv":
        from utils.nrv import convert
        return convert()
    if args.cmd == "clean":
        from utils.clean import clean
        return clean()
    if args.cmd == "check":
        from utils.check import check
        return check()
    if args.cmd == "report":
        from utils.report import report
        return report()
    raise AppError("unknown command: %s" % args.cmd)


def parse():
    ap = argparse.ArgumentParser(prog="run")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p_sim = sub.add_parser("sim")
    p_sim.add_argument("mod", choices=list(config.MODS) + ["all"])
    p_sim.add_argument("--testcase")
    p_pnr = sub.add_parser("pnr")
    p_pnr.add_argument("--dry-run", action="store_true")
    p_pnr.add_argument("--verify-only", action="store_true")
    p_pnr.add_argument("--analyze", action="store_true")
    p_pnr.add_argument("--freqs",
                       help="comma list of BOOT_FREQ values, e.g. 110,112,122 (parallel runs)")
    p_pnr.add_argument("--jobs", type=int, help="parallel worker count (default: all freqs)")
    p_cross = sub.add_parser("cross")
    p_cross.add_argument("mode", nargs="?", default="gen", choices=["gen", "verify"])
    sub.add_parser("nrv")
    sub.add_parser("clean")
    sub.add_parser("check")
    sub.add_parser("report")
    return ap.parse_args()


def main():
    config.load_env()
    args = parse()
    os.environ.setdefault("RUN_TS", time.strftime("%Y%m%d_%H%M%S"))
    os.environ["RUN_CMD"] = args.cmd
    reporter = Reporter(config.LOGS)
    if not (args.cmd == "sim" and os.name == "nt"):
        rd = config.run_dir()
        if rd:
            Tee(os.path.join(rd, "%s_output.log" % args.cmd))
    try:
        t0 = time.monotonic()
        result = dispatch(args, reporter).finish()
        result.duration_s = time.monotonic() - t0
    except AppError as e:
        reporter.fail(str(e))
        sys.exit(e.code)
    except KeyboardInterrupt:
        sys.exit(130)
    if result.config.get("dry"):
        sys.exit(0 if result.status == "ok" else 1)
    if result.status == "ok":
        reporter.ok(f"{result.cmd} done in {result.duration_s:.1f}s")
    else:
        reporter.fail(f"{result.cmd} failed in {result.duration_s:.1f}s: {result.error}")
    name = reporter.save(result)
    reporter.info(f"report {name}")
    sys.exit(0 if result.status == "ok" else 1)


if __name__ == "__main__":
    main()
