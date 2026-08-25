import os
import subprocess
import sys

from . import config
from .core import Result

NEORV32_RTL = os.path.join(config.RTL, "neorv32")
WRAPPER_SRC = os.path.join(config.SIM, "neorv32_wrapper.vhd")
FULL_WRAPPER_SRC = os.path.join(config.SIM, "neorv32_full_wrapper.vhd")
OUT_V = os.path.join(config.BUILD, "neorv32_conv", "neorv32_wrapper.v")
FULL_OUT_V = os.path.join(config.BUILD, "neorv32_conv", "neorv32_full_wrapper.v")
WORK = os.path.join(config.BUILD, "neorv32_conv", "work")
CONV = os.path.dirname(WORK)


def ghdl():
    return config.find_tool("GHDL", "ghdl")


def collect_vhdl(wrapper):
    files = [os.path.join(NEORV32_RTL, f) for f in sorted(os.listdir(NEORV32_RTL)) if f.endswith(".vhd")]
    files = [f for f in files if os.path.basename(f) != "neorv32_setup_25k.vhd"]
    files.append(wrapper)
    return files


def _convert(wrapper_src, out_v, log_path):
    env = config.verilator_env()
    env["GHDL"] = ghdl()
    entity = os.path.splitext(os.path.basename(wrapper_src))[0]
    cmd = [
        ghdl(), "-i", "--std=08", "--work=neorv32", "--workdir=" + WORK,
    ] + collect_vhdl(wrapper_src)
    with open(log_path, "w") as log:
        rc = subprocess.run(cmd, env=env, cwd=CONV, stdout=log, stderr=subprocess.STDOUT).returncode
        if rc == 0:
            rc = subprocess.run(
                [ghdl(), "-m", "--std=08", "--work=neorv32", "--workdir=" + WORK, entity],
                env=env, cwd=CONV, stdout=log, stderr=subprocess.STDOUT).returncode
        if rc == 0:
            with open(out_v, "w") as out:
                rc = subprocess.run(
                    [ghdl(), "synth", "--std=08", "--work=neorv32", "--workdir=" + WORK,
                     "--out=verilog", entity],
                    env=env, cwd=CONV, stdout=out, stderr=log).returncode
    return rc


def patch_regfile(path):
    src = open(path).read()
    marker = "reg [31:0] regfile[31:0]"
    if "syn_ramstyle" not in src and marker in src:
        src = src.replace(marker, '(* syn_ramstyle="registers" *) ' + marker)
        open(path, "w").write(src)


def convert():
    os.makedirs(os.path.dirname(OUT_V), exist_ok=True)
    os.makedirs(WORK, exist_ok=True)
    rd = config.run_dir()
    base = rd if rd else os.path.join(config.LOGS, "nrv")
    os.makedirs(base, exist_ok=True)
    rc = _convert(WRAPPER_SRC, OUT_V, os.path.join(base, "nrv_convert.log"))
    print(f"xip wrapper ghdl exit {rc}")
    if rc != 0:
        return Result("nrv", "fail", error=f"xip wrapper ghdl exit {rc}",
                      artifacts={"log": os.path.join(base, "nrv_convert.log")})
    patch_regfile(OUT_V)
    print(f"converted {OUT_V}")
    rc = _convert(FULL_WRAPPER_SRC, FULL_OUT_V, os.path.join(base, "nrv_convert_full.log"))
    print(f"full wrapper ghdl exit {rc}")
    if rc != 0:
        return Result("nrv", "fail", error=f"full wrapper ghdl exit {rc}",
                      artifacts={"log": os.path.join(base, "nrv_convert_full.log")})
    patch_regfile(FULL_OUT_V)
    print(f"converted {FULL_OUT_V}")
    return Result("nrv", artifacts={"xip": OUT_V, "full": FULL_OUT_V})
