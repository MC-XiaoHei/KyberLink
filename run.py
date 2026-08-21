#!/usr/bin/env python3
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from utils import config
from utils.cross import cross
from utils.pnr import pnr
from utils.sim import sim


def main():
    config.load_env()
    config.ensure_shims()
    ap = argparse.ArgumentParser(prog="run")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p_sim = sub.add_parser("sim")
    p_sim.add_argument("mod", choices=list(config.MODS))
    p_sim.add_argument("--testcase")
    p_pnr = sub.add_parser("pnr")
    p_pnr.add_argument("--dry-run", action="store_true")
    p_pnr.add_argument("--verify-only", action="store_true")
    p_cross = sub.add_parser("cross")
    p_cross.add_argument("mode", nargs="?", default="gen", choices=["gen", "verify"])
    sub.add_parser("clean")
    args = ap.parse_args()
    if args.cmd == "sim":
        sim(args.mod, args.testcase)
    elif args.cmd == "pnr":
        sys.exit(pnr(dry_run=args.dry_run, verify_only=args.verify_only))
    elif args.cmd == "cross":
        cross(args.mode)
    elif args.cmd == "clean":
        os.system("rm -rf build/sim build/synth build/probe")


if __name__ == "__main__":
    main()
