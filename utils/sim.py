import os
import sys

from . import config


def sim(mod, testcase=None):
    cfg = config.MODS.get(mod)
    if not cfg:
        sys.exit(f"unknown MOD {mod}, available: {', '.join(config.MODS)}")
    build_dir = os.path.join(config.BUILD, "sim", mod)
    os.makedirs(build_dir, exist_ok=True)
    os.makedirs(os.path.join(config.LOGS, "sim", mod), exist_ok=True)
    env = config.verilator_env()
    os.environ.update(env)
    from cocotb_tools import runner as cr
    # cocotb#5476 workaround: direct verilator call, drop after cocotb 2.0.2
    _orig_build = cr.Verilator._build_command
    def _patched_build(self):
        cmds = _orig_build(self)
        return [[a for a in cmd if a != "perl"] for cmd in cmds]
    cr.Verilator._build_command = _patched_build
    from cocotb_tools.runner import get_runner
    tests_dir = os.path.join(config.SIM, "tests")
    if tests_dir not in sys.path:
        sys.path.insert(0, tests_dir)
    runner = get_runner("verilator")
    runner.build(
        verilog_sources=cfg["src"],
        hdl_toplevel=cfg["top"],
        build_dir=build_dir,
        defines={"COCOTB_SIM": "1"},
        build_args=config.WNO + ["-CFLAGS", "-O2", "-LDFLAGS", "-static-libstdc++ -l:libgpi.dll -l:libgpilog.dll -lpython3.14"],
    )
    config.ensure_py_runtime(build_dir)
    runner.test(test_module=cfg["test"], hdl_toplevel=cfg["top"],
                build_dir=build_dir, testcase=testcase,
                results_xml=os.path.join(config.LOGS, "sim", mod, "results.xml"))
