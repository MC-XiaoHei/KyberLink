import os
import subprocess

from . import config
from .core import Result

ENV_KEYS = ("BOOT_FREQ", "TARGET_FREQ", "VERILATOR", "TOOLCHAIN_BIN", "GOWIN_HOME", "DEVICE", "DEVICE_VERSION")


def _wsl_script():
    venv = os.environ.get("WSL_VENV", "$HOME/kyberlink-venv")
    ver = os.environ.get("WSL_VERILATOR", "$HOME/verilator-532/bin")
    return (
        'export PATH="%s:$PATH"; '
        'echo "VER=$(%s/verilator --version 2>&1 | head -1)"; '
        'echo "PY=$(%s/bin/python --version 2>&1)"; '
        'echo "COCOTB=$(%s/bin/python -c \'import cocotb;print(cocotb.__version__)\' 2>&1)"; '
        'echo "SIMLINK=$(readlink build/sim 2>/dev/null || echo MISSING)"; '
        'echo "SIMDIR=$(test -d build/sim && echo present || echo absent)"'
        % (ver, ver, venv, venv)
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
    add("win", "gw_sh", bool(gw) and os.path.exists(gw), gw)
    try:
        import Crypto
        add("win", "pycryptodome", True, Crypto.__version__)
    except ImportError as e:
        add("win", "pycryptodome", False, str(e))
    try:
        rc = subprocess.call(["wsl", "--", "bash", "-lc", "true"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        add("win", "wsl", rc == 0)
    except OSError as e:
        add("win", "wsl", False, str(e))

    try:
        out = subprocess.check_output(["wsl", "--", "bash", "-lc", _wsl_script()],
                                      text=True, timeout=60)
    except (subprocess.CalledProcessError, OSError, subprocess.TimeoutExpired) as e:
        add("wsl", "deps", False, str(e))
    else:
        for line in out.strip().splitlines():
            k, _, v = line.partition("=")
            ok = bool(v.strip()) and not any(w in v.lower() for w in fail_keywords)
            add("wsl", k.lower(), ok, v.strip())

    total = len(items)
    ok = all(i["ok"] for i in items)
    return Result("check", metrics={"items": items, "total": total,
                                    "ok": sum(1 for i in items if i["ok"]),
                                    "fail": sum(1 for i in items if not i["ok"])},
                  error=None if ok else "some checks failed")