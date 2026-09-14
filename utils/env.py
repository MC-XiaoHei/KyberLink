import os
import subprocess

from . import config
from .core import Result

ENV_KEYS = (
    "GOWIN_HOME",
    "DEVICE",
    "DEVICE_VERSION",
    "HOST_TARGET",
    "RUST_TOOLCHAIN",
    "WSL_VENV",
    "WSL_VERILATOR",
)

FAIL_KEYWORDS = ("error", "missing", "absent", "not", "no such")


def env():
    items = []
    _check_windows(items)
    _check_wsl_deps(items)
    ok = all(i["ok"] for i in items)
    return Result(
        "env",
        metrics={
            "items": items,
            "total": len(items),
            "ok": sum(1 for i in items if i["ok"]),
            "fail": sum(1 for i in items if not i["ok"]),
        },
        error=None if ok else "some env checks failed",
    )


def _add(items, scope, name, ok, detail=""):
    items.append({"scope": scope, "name": name, "ok": ok, "detail": detail})
    print(f"{scope:<5} {name:<16} {'ok' if ok else 'FAIL':<4} {detail}")


def _check_windows(items):
    envf = os.path.join(config.REPO, ".env")
    _add(items, "win", ".env", os.path.exists(envf), envf)

    missing = [k for k in ENV_KEYS if not os.environ.get(k)]
    _add(items, "win", "env keys", not missing, "" if not missing else ",".join(missing))

    gw = _gw_sh_path()
    _add(items, "win", "GW_SH", bool(gw) and os.path.exists(gw), gw)

    try:
        import Crypto

        _add(items, "win", "pycryptodome", True, Crypto.__version__)
    except ImportError as e:
        _add(items, "win", "pycryptodome", False, str(e))

    _check_wsl_reachable(items)


def _gw_sh_path():
    gh = os.environ.get("GOWIN_HOME", "")
    return os.path.join(gh, "IDE", "bin", "gw_sh.exe") if gh else ""


def _check_wsl_reachable(items):
    try:
        rc = subprocess.call(
            ["wsl", "--", "bash", "-lc", "true"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        _add(items, "win", "wsl", rc == 0)
    except OSError as e:
        _add(items, "win", "wsl", False, str(e))


def _check_wsl_deps(items):
    try:
        out = subprocess.check_output(
            ["wsl", "--", "bash", "-lc", _wsl_script()], text=True, timeout=60
        )
    except (subprocess.CalledProcessError, OSError, subprocess.TimeoutExpired) as e:
        _add(items, "wsl", "deps", False, str(e))
        return
    for line in out.strip().splitlines():
        key, _, value = line.partition("=")
        ok = bool(value.strip()) and not any(w in value.lower() for w in FAIL_KEYWORDS)
        _add(items, "wsl", key, ok, value.strip())


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


def run(args, reporter):
    return env()


def add_args(sub):
    sub.add_parser("env")
