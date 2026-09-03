import subprocess

from . import config
from .core import Result


def _lint():
    from .wsl import wsl_path

    repo = wsl_path(config.REPO)
    script = (
        f"cd {repo} && "
        f"~/kyberlink-venv/bin/python -m ruff check run.py utils/ && "
        f"find hardware/rtl -name '*.v' -print0 | xargs -0 "
        f"$HOME/verible/bin/verible-verilog-lint --rules_config_search && "
        f"cd {repo}/software && cargo clippy -p kyberlink-crypto --all-targets "
        f"--target x86_64-unknown-linux-gnu --features kyberlink-crypto/std -- -D warnings && "
        f"cargo clippy -p kyberlink-firmware "
        f"--target riscv32imc-unknown-none-elf -- -D warnings"
    )
    r = subprocess.run(["wsl", "--", "bash", "-lc", script], capture_output=True, text=True)
    return (r.stdout + r.stderr).strip()[-400:] if r.returncode else ""


def check():
    lint_detail = _lint()
    ok = lint_detail == ""
    print(f"{'lint':<5} {'python+verilog+rust':<16} {'ok' if ok else 'FAIL':<4} {'' if ok else lint_detail}")
    return Result(
        "check",
        metrics={"lint": "ok" if ok else "fail"},
        error=None if ok else lint_detail,
    )


def run(args, reporter):
    return check()


def add_args(sub):
    sub.add_parser("check")
