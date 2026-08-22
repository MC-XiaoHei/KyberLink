import os
import shutil

from . import config
from .core import Result


def clean():
    for d in ("sim", "synth", "probe"):
        p = os.path.join(config.BUILD, d)
        if os.path.islink(p):
            os.unlink(p)
        elif os.path.isdir(p):
            shutil.rmtree(p, ignore_errors=True)
    return Result("clean")
