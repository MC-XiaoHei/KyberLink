import subprocess

from . import config
from .core import AppError, Result
from .wsl import wsl_path


def format():
    py = [wsl_path(config.REPO) + "/run.py", wsl_path(config.REPO) + "/utils"]
    script = (
        f"cd {wsl_path(config.REPO)} && "
        f"~/kyberlink-venv/bin/python -m ruff format --silent {' '.join(py)} && "
        f"~/verible/bin/verible-verilog-format --inplace rtl/src/*.v rtl/src/mac/*.v rtl/selftest/*.v && "
        f"cd {wsl_path(config.REPO)}/software && "
        "cargo fmt --all"
    )
    rc = subprocess.call(["wsl", "--", "bash", "-lc", script])
    if rc != 0:
        raise AppError(f"format failed rc={rc}", rc)
    return Result("format")


def run(args, reporter):
    return format()


def add_args(sub):
    sub.add_parser("format")
