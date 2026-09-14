import os
import sys
import xml.etree.ElementTree as ET

from . import config
from .config import INTG_TEST, UNIT_TEST
from .core import AppError


def sim(mod, testcase=None):
    cfg = config.CONF.get(mod)
    if not cfg:
        raise AppError(f"unknown mod {mod}, available: {', '.join(config.CONF)}", 2)
    config.load_env()
    from cocotb_tools.runner import get_runner

    if config.TEST_DIR not in sys.path:
        sys.path.insert(0, config.TEST_DIR)
    build_dir = os.path.join(config.BUILD, "test", mod)
    os.makedirs(build_dir, exist_ok=True)
    runner = get_runner("verilator")
    waves = bool(os.environ.get("WAVES"))

    runner.build(
        sources=cfg["src"],
        hdl_toplevel=cfg["top"],
        build_dir=build_dir,
        defines={"COCOTB_SIM": "1"},
        build_args=_build_args(waves),
        clean=True,
    )
    results_xml = os.path.join(config.run_dir("test"), mod + ".results.xml")
    runner.test(
        hdl_toplevel=cfg["top"],
        test_module=_test_module(mod, cfg),
        build_dir=build_dir,
        testcase=testcase,
        results_xml=results_xml,
        test_args=_test_args(build_dir, testcase, waves),
    )
    return results_xml


def _build_args(waves):
    args = list(config.WNO)
    if waves:
        args.append("--trace-fst")
    return args


def _test_args(build_dir, testcase, waves):
    if not waves:
        return []
    fst = os.path.join(build_dir, (testcase or "all") + ".fst")
    print("waves: " + os.path.relpath(fst, config.REPO))
    return ["--trace", "--trace-file", fst]


def _test_module(mod, cfg):
    default = UNIT_TEST.get(mod) or INTG_TEST.get(mod) or "tb_" + mod
    return os.environ.get("TEST_MODULE", cfg.get("test_module", default))


def sim_all(mods, testcase=None):
    subs = {}
    failed = []
    for mod in mods:
        try:
            xml = sim(mod, testcase)
            metrics, _ = parse_results(xml)
            subs[mod] = metrics
            print(f"{mod:<12} pass={metrics['pass']} fail={metrics['fail']} skip={metrics['skip']}")
        except AppError as e:
            subs[mod] = {"status": "fail", "error": str(e)}
            failed.append(mod)
            print(f"{mod:<12} FAIL {e}")
    ok = not failed
    return (
        {
            "total": len(mods),
            "ok": len(mods) - len(failed),
            "fail": len(failed),
            "modules": subs,
        },
        ok,
        ", ".join(failed),
    )


def parse_results(xml_path):
    root = ET.parse(xml_path).getroot()
    cases = []
    for ts in root.iter("testsuite"):
        for tc in ts.iter("testcase"):
            failed = tc.find("failure") is not None or tc.find("error") is not None
            skipped = tc.find("skipped") is not None
            status = "skip" if skipped else ("fail" if failed else "pass")
            cases.append(
                {
                    "name": tc.get("name"),
                    "time": float(tc.get("time", 0)),
                    "sim_time_ns": float(tc.get("sim_time_ns", 0)),
                    "status": status,
                }
            )
    stats = {
        "tests": len(cases),
        "pass": sum(1 for c in cases if c["status"] == "pass"),
        "fail": sum(1 for c in cases if c["status"] == "fail"),
        "skip": sum(1 for c in cases if c["status"] == "skip"),
        "testcases": cases,
    }
    return stats, cases


if __name__ == "__main__":
    sim(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
