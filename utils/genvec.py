import subprocess

from . import config
from .core import AppError, Result
from .wsl import wsl_path

MODES = ["all", "shake", "aes", "gcm", "ghash", "cipher", "esp", "handshake", "cross"]


def genvec(mode="all", n=32):
    if mode == "cross":
        from .cross import cross

        return cross("gen")
    script = (
        f"cd {wsl_path(config.REPO)}/software && cargo run -q -p kyberlink-vecgen "
        f"--target x86_64-unknown-linux-gnu -- {mode} {n}"
    )
    rc = subprocess.call(["wsl", "--", "bash", "-lc", script])
    if rc != 0:
        raise AppError(f"vecgen failed rc={rc}", rc)
    return Result("genvec", "ok", config={"mode": mode, "n": n})


def run(args, reporter):
    return genvec(args.mode, args.n)


def add_args(sub):
    p = sub.add_parser("genvec")
    p.add_argument("mode", nargs="?", default="all", choices=MODES)
    p.add_argument("n", nargs="?", type=int, default=32)
