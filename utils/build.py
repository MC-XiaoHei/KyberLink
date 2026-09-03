import subprocess

from . import config, pnr
from .core import AppError, Result


def run(args, reporter):
    if args.target == "rtl":
        return pnr.pnr()
    return firmware()


def firmware():
    from .wsl import wsl_path

    script = (
        f"cd {wsl_path(config.REPO)}/software && cargo build -p kyberlink-firmware "
        f"--release --target riscv32imc-unknown-none-elf"
    )
    rc = subprocess.call(["wsl", "--", "bash", "-lc", script])
    if rc != 0:
        raise AppError(f"cargo build firmware failed rc={rc}", rc)
    return Result("build firmware")


def add_args(sub):
    p = sub.add_parser("build")
    p.add_argument("target", choices=["rtl", "firmware"])
