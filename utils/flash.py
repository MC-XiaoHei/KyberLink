import os
import shlex
import subprocess
import sys
import time

from . import config
from .core import AppError, Result

PROGRAMMER_CLI = os.environ.get("GW_PROGRAMMER_CLI") or os.path.join(
    r"C:\Gowin\Gowin_V1.9.12.03_x64", "Programmer", "bin", "programmer_cli.exe"
)
OPENOCD = os.environ.get("WCH_OPENOCD") or os.path.join(
    r"C:\MounRiver\MounRiver_Studio2\resources\app\resources\win32\components",
    "WCH",
    "OpenOCD",
    "OpenOCD",
    "bin",
    "openocd.exe",
)
OPENOCD_CFG = os.path.join(os.path.dirname(OPENOCD), "wch-riscv.cfg")

MSPI_ADDRESS = "0x000000"
FPGA_RUN_SRAM = "4"
FPGA_RUN_FLASH = "9"


def bitstream(target):
    work = "selftest" if target == "selftest" else "impl"
    return os.path.join(config.BUILD, "synth", work, "impl", "pnr", "project.fs")


def firmware(target):
    name = "kyberlink-selftest" if target == "selftest" else "kyberlink-firmware"
    return os.path.join(
        config.REPO, "software", "target", "riscv32imc-unknown-none-elf", "release", name
    )


def device_name():
    return os.environ.get("DEVICE_NAME", "GW5A-25") + os.environ.get("DEVICE_VERSION", "A")


def mcu_cmd(elf, tail):
    path = elf.replace("\\", "/")
    steps = ["init", "program {%s} verify" % path, tail, "exit"]
    return [OPENOCD, "-f", OPENOCD_CFG, "-c", "; ".join(steps)]


def fpga_cmd(fs, flash, log):
    cmd = [
        PROGRAMMER_CLI,
        "--device",
        device_name(),
        "--run",
        FPGA_RUN_FLASH if flash else FPGA_RUN_SRAM,
        "-f",
        fs,
    ]
    if flash:
        cmd += ["--spiaddr", MSPI_ADDRESS]
    cmd += ["-o", log]
    return cmd


def steps_for(args, fs, elf, log):
    if args.mcu_only:
        return [("mcu", mcu_cmd(elf, "reset run"))]
    if args.fpga_only:
        return [("fpga", fpga_cmd(fs, args.flash, log))]
    return [
        ("mcu-halt", mcu_cmd(elf, "reset halt")),
        ("fpga", fpga_cmd(fs, args.flash, log)),
        ("mcu-run", mcu_cmd(elf, "reset run")),
    ]


def run(args, reporter):
    if not sys.platform.startswith("win"):
        raise AppError("flash runs on Windows only; USB is unreachable from WSL", 1)
    fs = bitstream(args.target)
    elf = firmware(args.target)
    if not args.mcu_only and not os.path.exists(fs):
        raise AppError("bitstream missing, run `run.py build %s` first" % args.target, 1)
    if not args.fpga_only and not os.path.exists(elf):
        raise AppError("firmware missing, run `run.py build firmware` first", 1)
    log = os.path.join(config.run_dir() or config.BUILD, "flash_%s.log" % args.target)
    steps = steps_for(args, fs, elf, log)
    metrics = {"bitstream": fs, "firmware": elf, "flash": "flash" if args.flash else "sram"}
    for name, cmd in steps:
        reporter.info(shlex.join(cmd))
        if args.dry_run:
            continue
        started = time.monotonic()
        rc = subprocess.call(cmd)
        metrics[name + "_s"] = round(time.monotonic() - started, 2)
        if rc != 0:
            raise AppError("%s failed rc=%d" % (name, rc), rc)
    return Result("flash %s" % args.target, config={"dry_run": args.dry_run}, metrics=metrics)


def add_args(sub):
    p = sub.add_parser("flash")
    p.add_argument("target", choices=["rtl", "selftest"])
    p.add_argument("--fpga-only", action="store_true")
    p.add_argument("--mcu-only", action="store_true")
    p.add_argument("--flash", action="store_true", help="write the bitstream into the config flash")
    p.add_argument("--dry-run", action="store_true")
