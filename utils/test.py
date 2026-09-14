import os
import subprocess

from . import config
from .core import AppError, Result


def run(args, reporter):
    if args.level == "unit":
        return unit(args.name, args.testcase)
    return intg(args.name, args.testcase)


def _cargo_test():
    host = os.environ.get("HOST_TARGET", "x86_64-pc-windows-msvc")
    tc = os.environ.get("RUST_TOOLCHAIN", "nightly")
    script = (
        f"rustup run {tc} cargo test --workspace "
        f"--target {host} "
        "--features kyberlink-crypto/std,kyberlink-core/std"
    )
    rc = subprocess.call(["cmd", "/c", script], cwd=os.path.join(config.REPO, "software"))
    if rc != 0:
        raise AppError(f"cargo test failed rc={rc}", rc)
    script = (
        f"rustup run {tc} cargo build -p kyberlink-simnode "
        f"--target {host}"
    )
    rc = subprocess.call(["cmd", "/c", script], cwd=os.path.join(config.REPO, "software"))
    if rc != 0:
        raise AppError(f"cargo build simnode failed rc={rc}", rc)


def _cross_verify():
    from .cross import cross

    cross("verify")


def _test_group(mods, testcase=None):
    from .test_sim import sim_all

    if os.name == "nt":
        from .wsl import wsl_sim

        for mod in mods:
            rc = wsl_sim(mod, testcase)
            if rc != 0:
                raise AppError(f"test {mod} failed rc={rc}", rc)
        return
    _, ok, failed = sim_all(mods, testcase)
    if not ok:
        raise AppError(f"test failed: {failed}", 1)


def unit(name=None, testcase=None):
    if name is None:
        _cargo_test()
        _cross_verify()
        _test_group(config.UNIT, testcase)
        return Result("test unit", metrics={"cargo": "ok", "cross": "ok", "test": config.UNIT})
    if name not in config.UNIT:
        raise AppError(f"{name} not in test unit: {', '.join(config.UNIT)}", 2)
    _test_group([name], testcase)
    return Result("test unit", metrics={"test": [name]})


def intg(name=None, testcase=None):
    mods = [name] if name else config.INTG
    if name and name not in config.INTG:
        raise AppError(f"{name} not in test intg: {', '.join(config.INTG)}", 2)
    _test_group(mods, testcase)
    return Result("test intg", metrics={"test": mods})


def add_args(sub):
    p = sub.add_parser("test")
    p.add_argument("level", choices=["unit", "intg"])
    p.add_argument("name", nargs="?", default=None)
    p.add_argument("--testcase", "-t", default=None)
