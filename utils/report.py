import glob
import json
import os

from . import config
from .core import Result


def _load_reports():
    files = sorted(glob.glob(os.path.join(config.LOGS, "*", "*", "*_report.json")))
    out = []
    for f in files:
        try:
            out.append(json.load(open(f)))
        except (ValueError, OSError):
            continue
    return out


def report():
    rows = _load_reports()
    if not rows:
        return Result("report", error=f"no reports in {config.LOGS}", status="fail")
    by_cmd = {}
    for r in rows:
        by_cmd.setdefault(r["cmd"], []).append(r)
    metrics = {}
    for cmd, runs in sorted(by_cmd.items()):
        last = runs[-1]
        print(f"{cmd:<8} {len(runs):2d} runs  last={last['status']}  {last.get('error') or ''}")
        metrics[cmd] = {"runs": len(runs), "last": last["status"]}
        for r in runs[-3:]:
            extra = []
            if r["config"]:
                extra.append("cfg=%s" % ",".join(
                    "%s=%s" % (k, v) for k, v in sorted(r["config"].items())))
            if r["metrics"]:
                extra.append("m=%s" % ",".join(
                    "%s=%s" % (k, v) for k, v in sorted(r["metrics"].items())))
            arts = ",".join(sorted(r.get("artifacts") or {}))
            if arts:
                extra.append(f"art={arts}")
            print(f"    {r['cmd']} {r['status']:<5} {r['duration_s']:5.1f}s  {'  '.join(extra)}")
    return Result("report", metrics=metrics)
