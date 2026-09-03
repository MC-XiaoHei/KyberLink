import os
import shutil
import subprocess

from . import config


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
    rc = _wsl(script)
    results = os.path.join(config.BUILD, "test", mod, "results.xml")
    if os.path.exists(results):
        shutil.copy2(results, os.path.join(rd, mod + ".results.xml"))
    print("log: " + os.path.relpath(log, config.REPO))
    return rc
