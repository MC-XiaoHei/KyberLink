import os
import sys

from . import config
from .core import AppError, Result


def sim(mod, testcase=None, results_name="sim_results.xml"):
    cfg = config.MODS.get(mod)
    if not cfg:
        raise AppError("unknown MOD %s, available: %s" % (mod, ", ".join(config.MODS)), 2)
    build_dir = os.path.join(config.BUILD, "sim", mod)
    os.makedirs(build_dir, exist_ok=True)
    env = config.verilator_env()
    os.environ.update(env)
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
        build_args=list(config.WNO),
    )
    rd = config.run_dir()
    results_xml = os.path.join(rd, results_name) if rd else \
        os.path.join(config.LOGS, "sim", mod, "results.xml")
    try:
        runner.test(test_module=cfg["test"], hdl_toplevel=cfg["top"],
                    build_dir=build_dir, testcase=testcase,
                    results_xml=results_xml)
    except Exception as e:
        raise AppError("sim %s failed: %s" % (mod, e))
    metrics, cases = _parse_results(results_xml)
    return Result("sim", config={"mod": mod, "testcase": testcase},
                  metrics=metrics, artifacts={"results": results_xml})


def sim_all(testcase=None):
    mods = list(config.MODS)
    rd = config.run_dir()
    subs = {}
    failed = []
    for mod in mods:
        xml = os.path.join(rd, "_%s_results.xml" % mod)
        try:
            r = sim(mod, testcase, results_name=os.path.basename(xml)).finish()
            subs[mod] = {"status": r.status, "tests": r.metrics.get("tests"),
                         "pass": r.metrics.get("pass"), "fail": r.metrics.get("fail"),
                         "skip": r.metrics.get("skip"), "testcases": r.metrics.get("testcases")}
            print("%-12s %s" % (mod, r.status))
        except AppError as e:
            subs[mod] = {"status": "fail", "error": str(e)}
            failed.append(mod)
            print("%-12s FAIL %s" % (mod, e))
        finally:
            if os.path.exists(xml):
                os.remove(xml)
    ok = not failed
    return Result("sim", config={"testcase": testcase}, metrics={
        "total": len(mods), "ok": len(mods) - len(failed), "fail": len(failed),
        "modules": subs}, error=None if ok else "failed: %s" % ", ".join(failed))


def _parse_results(xml_path):
    import xml.etree.ElementTree as ET
    root = ET.parse(xml_path).getroot()
    cases = []
    for ts in root.iter("testsuite"):
        for tc in ts.iter("testcase"):
            failed = tc.find("failure") is not None or tc.find("error") is not None
            skipped = tc.find("skipped") is not None
            status = "skip" if skipped else ("fail" if failed else "pass")
            cases.append({
                "name": tc.get("name"),
                "time": float(tc.get("time", 0)),
                "sim_time_ns": float(tc.get("sim_time_ns", 0)),
                "status": status,
            })
    stats = {
        "tests": len(cases),
        "pass": sum(1 for c in cases if c["status"] == "pass"),
        "fail": sum(1 for c in cases if c["status"] == "fail"),
        "skip": sum(1 for c in cases if c["status"] == "skip"),
    }
    stats["testcases"] = cases
    return stats, cases
