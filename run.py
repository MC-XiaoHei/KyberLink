#!/usr/bin/env python3
import argparse
import contextlib
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from utils import build, check, clean, config, env, flash, format, genvec, test
from utils.core import AppError, Reporter, Tee

REGISTRY = {
    "test": test,
    "genvec": genvec,
    "build": build,
    "flash": flash,
    "format": format,
    "check": check,
    "env": env,
    "clean": clean,
}


def dispatch(args, reporter):
    return REGISTRY[args.cmd].run(args, reporter)


def parse():
    ap = argparse.ArgumentParser(prog="run")
    sub = ap.add_subparsers(dest="cmd", required=True)
    for mod in REGISTRY.values():
        mod.add_args(sub)
    return ap.parse_args()


def main():
    config.load_env()
    args = parse()
    os.environ.setdefault(
        "RUN_TS",
        f"{time.strftime('%y%m%d')}/{time.strftime('%H')}/{time.strftime('%M')}/{time.strftime('%S')}",
    )
    os.environ["RUN_CMD"] = args.cmd
    reporter = Reporter(config.LOGS)
    if args.cmd == "test" and os.name == "nt":
        tee = contextlib.nullcontext()
    else:
        tee = Tee(os.path.join(config.run_dir(), f"{args.cmd}_output.log"))
    try:
        with tee:
            try:
                t0 = time.monotonic()
                result = dispatch(args, reporter)
                result.duration_s = time.monotonic() - t0
            except AppError as e:
                reporter.fail(str(e))
                sys.exit(e.code)
            except KeyboardInterrupt:
                sys.exit(130)
    finally:
        sys.stdout.flush()
        sys.stderr.flush()
    if result.status == "ok":
        reporter.ok(f"{args.cmd} done in {result.duration_s:.1f}s")
    else:
        reporter.fail(f"{args.cmd} failed in {result.duration_s:.1f}s: {result.error}")
    name = reporter.save(result)
    reporter.info(f"report {name}")
    sys.exit(0 if result.status == "ok" else 1)


if __name__ == "__main__":
    main()
