import json
import os
import sys
import threading
import time
from datetime import datetime

from . import config


class Tee:
    def __init__(self, path):
        self.f = open(path, "w", encoding="utf-8", errors="replace")
        self.orig = os.dup(1)
        r, w = os.pipe()
        os.dup2(w, 1)
        os.dup2(w, 2)
        threading.Thread(target=self._pump, args=(r,), daemon=True).start()

    def _pump(self, r):
        while True:
            try:
                data = os.read(r, 8192)
            except OSError:
                break
            if not data:
                break
            os.write(self.orig, data)
            self.f.write(data.decode("utf-8", errors="replace"))
            self.f.flush()


class AppError(Exception):
    def __init__(self, msg, code=1):
        super().__init__(msg)
        self.code = code


class Result:
    def __init__(self, cmd, status="ok", config=None, metrics=None, artifacts=None, error=None):
        self.cmd = cmd
        self.status = status
        self.config = config or {}
        self.metrics = metrics or {}
        self.artifacts = artifacts or {}
        self.error = error
        self.duration_s = 0.0
        self.started = time.monotonic()

    def finish(self):
        self.duration_s = time.monotonic() - self.started
        return self

    def to_dict(self):
        return {
            "cmd": self.cmd,
            "status": self.status,
            "config": self.config,
            "metrics": self.metrics,
            "artifacts": self.artifacts,
            "error": self.error,
            "duration_s": round(self.duration_s, 2),
        }


class Reporter:
    def __init__(self, logs_dir):
        self.logs_dir = logs_dir

    def info(self, msg):
        print(msg)

    def ok(self, msg):
        print("[ok] %s" % msg)

    def fail(self, msg):
        print("[fail] %s" % msg, file=sys.stderr)

    def save(self, result):
        d = config.run_dir()
        if d:
            name = os.path.join(d, "%s_report.json" % result.cmd)
        else:
            os.makedirs(self.logs_dir, exist_ok=True)
            name = os.path.join(self.logs_dir,
                                "%s_report_%s.json" % (result.cmd, datetime.now().strftime("%Y%m%d_%H%M%S")))
        json.dump(result.to_dict(), open(name, "w"), indent=2)
        return name
