import os
import subprocess

from . import config, pnr
from .core import AppError, Result


def run(args, reporter):
    if args.target == "rtl":
        return pnr.pnr()
    if args.target == "selftest":
        return selftest()
    return firmware()


def selftest():
    return pnr.pnr(
        top="self_test_top",
        extra=config.SELFTEST,
        work_dir=os.path.join(config.BUILD, "synth", "selftest"),
        cmd="build selftest",
    )


def firmware():
    tc = os.environ.get("RUST_TOOLCHAIN", "nightly")
    script = f"rustup run {tc} cargo -Zbuild-std=core,alloc build -p kyberlink-firmware -p kyberlink-selftest --release"
    rc = subprocess.call(["cmd", "/c", script], cwd=os.path.join(config.REPO, "software"))
    if rc != 0:
        raise AppError(f"cargo build firmware failed rc={rc}", rc)
    return Result("build firmware")


def add_args(sub):
    p = sub.add_parser("build")
    p.add_argument("target", choices=["rtl", "firmware", "selftest"])
