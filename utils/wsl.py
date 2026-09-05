import os
import subprocess

from . import config
from .core import AppError


def wsl_path(win):
    drive, rest = os.path.splitdrive(win)
    return "/mnt/" + drive[0].lower() + rest.replace("\\", "/")


def _wsl(cmd):
    return subprocess.call(["wsl", "--", "bash", "-lc", cmd])


def wsl_sim(mod, testcase=None):
    venv = os.environ.get("WSL_VENV", "$HOME/kyberlink-venv")
    rd = config.run_dir("test")
    log = os.path.join(rd, mod + ".log")
    ver = os.environ.get("WSL_VERILATOR", "$HOME/verilator-532/bin")
    tc = f" {testcase}" if testcase else ""
    tm = (
        f'export TEST_MODULE="{os.environ["TEST_MODULE"]}" && '
        if "TEST_MODULE" in os.environ
        else ""
    )
    ts = os.environ.get("RUN_TS", "")
    tr = f'export RUN_TS="{ts}" && ' if ts else ""
    script = (
        tm
        + tr
        + (f'export WAVES="{os.environ["WAVES"]}" && ' if "WAVES" in os.environ else "")
        + f'export PATH="{ver}:$PATH" && '
        f"cd {wsl_path(config.REPO)} && "
        f"PYTHONPATH={wsl_path(config.REPO)} {venv}/bin/python -m utils.test_sim {mod}{tc} > {wsl_path(log)} 2>&1"
    )
    _wsl(script)
    results = os.path.join(rd, mod + ".results.xml")
    if not os.path.exists(results):
        raise AppError(f"test {mod} produced no results.xml", 1)
    from .test_sim import parse_results

    metrics, _ = parse_results(results)
    if metrics["fail"] > 0 or metrics["tests"] == 0:
        failed = [c["name"] for c in metrics["testcases"] if c["status"] == "fail"]
        raise AppError(
            f"test {mod} failed {metrics['fail']}/{metrics['tests']}: {', '.join(failed)}", 1
        )
    print(
        f"{mod:<12} pass={metrics['pass']} fail={metrics['fail']} skip={metrics['skip']}"
    )
    print("log: " + os.path.relpath(log, config.REPO))
    return 0
