import os
import subprocess

from . import config
from .core import Result

ENV_KEYS = ("GOWIN_HOME", "DEVICE", "DEVICE_VERSION", "WSL_VENV", "WSL_VERILATOR")


def _wsl_script():
    venv = os.environ.get("WSL_VENV", "$HOME/kyberlink-venv")
    ver = os.environ.get("WSL_VERILATOR", "$HOME/verilator-532/bin")
    return (
        f'export PATH="{ver}:$PATH"; '
        f'echo "VERILATOR=$({ver}/verilator --version 2>&1 | head -1)"; '
        f'echo "PYTHON=$({venv}/bin/python --version 2>&1)"; '
        f"echo \"COCOTB=$({venv}/bin/python -c 'import cocotb;print(cocotb.__version__)' 2>&1)\"; "
        f'echo "RUFF=$({venv}/bin/python -m ruff --version 2>&1)"; '
        f'echo "VERIBLE=$($HOME/verible/bin/verible-verilog-format --version 2>&1 | head -1)"; '
    )


def check():
    items = []
    fail_keywords = ("error", "missing", "absent", "not", "no such")

    def add(scope, name, ok, detail=""):
        items.append({"scope": scope, "name": name, "ok": ok, "detail": detail})
        print(f"{scope:<5} {name:<16} {'ok' if ok else 'FAIL':<4} {detail}")

    envf = os.path.join(config.REPO, ".env")
    add("win", ".env", os.path.exists(envf), envf)
    missing = [k for k in ENV_KEYS if not os.environ.get(k)]
    add("win", "env keys", not missing, "" if not missing else ",".join(missing))
    gh = os.environ.get("GOWIN_HOME", "")
    gw = os.path.join(gh, "IDE", "bin", "gw_sh.exe") if gh else ""
    add("win", "GW_SH", bool(gw) and os.path.exists(gw), gw)
    try:
        import Crypto

        add("win", "pycryptodome", True, Crypto.__version__)
    except ImportError as e:
        add("win", "pycryptodome", False, str(e))
    try:
        rc = subprocess.call(
            ["wsl", "--", "bash", "-lc", "true"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        add("win", "wsl", rc == 0)
    except OSError as e:
        add("win", "wsl", False, str(e))

    try:
        out = subprocess.check_output(
            ["wsl", "--", "bash", "-lc", _wsl_script()], text=True, timeout=60
        )
    except (subprocess.CalledProcessError, OSError, subprocess.TimeoutExpired) as e:
        add("wsl", "deps", False, str(e))
    else:
        for line in out.strip().splitlines():
            k, _, v = line.partition("=")
            ok = bool(v.strip()) and not any(w in v.lower() for w in fail_keywords)
            add("wsl", k, ok, v.strip())

    lint_detail = _lint()
    add("lint", "python+verilog", lint_detail == "", lint_detail)

    total = len(items)
    ok = all(i["ok"] for i in items)
    return Result(
        "check",
        metrics={
            "items": items,
            "total": total,
            "ok": sum(1 for i in items if i["ok"]),
            "fail": sum(1 for i in items if not i["ok"]),
        },
        error=None if ok else "some checks failed",
    )


def _lint():
    from .wsl import wsl_path

    repo = wsl_path(config.REPO)
    script = (
        f"cd {repo} && "
        f"~/kyberlink-venv/bin/python -m ruff check run.py utils/ && "
        f"find hardware/rtl -name '*.v' -print0 | xargs -0 "
        f"$HOME/verible/bin/verible-verilog-lint --rules_config_search"
    )
    r = subprocess.run(["wsl", "--", "bash", "-lc", script], capture_output=True, text=True)
    return (r.stdout + r.stderr).strip()[-400:] if r.returncode else ""


def run(args, reporter):
    return check()


def add_args(sub):
    sub.add_parser("check")
