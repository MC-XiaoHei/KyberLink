#!/usr/bin/env python3
from hashlib import sha3_256, shake_256, shake_128
import json

VECDIR = "/mnt/d/Projects/MC-XiaoHei/KyberLink/vectors/generated"


def main():
    bad = 0
    vecs = json.load(open(VECDIR + "/sha3_256.json"))
    for v in vecs:
        msg = bytes.fromhex(v["msg"])
        got = sha3_256(msg).digest()
        exp = bytes.fromhex(v["hash"])
        if got != exp:
            print("SHA3-256 MISMATCH idx", v["index"], got.hex()[:16], exp[:16])
            bad += 1
    print("CROSSCHECK sha3_256 total", len(vecs), "bad", bad)

    v256 = json.load(open(VECDIR + "/shake.json"))
    for v in v256:
        msg = bytes.fromhex(v["msg"])
        got = shake_256(msg).digest(32)
        exp = bytes.fromhex(v["digest"])
        if got != exp:
            print("SHAKE256 MISMATCH idx", v["index"], got.hex()[:16], exp[:16])
            bad += 1
    print("CROSSCHECK shake256 total", len(v256), "bad", bad)

    v128 = json.load(open(VECDIR + "/shake128.json"))
    for v in v128:
        msg = bytes.fromhex(v["msg"])
        got = shake_128(msg).digest(32)
        exp = bytes.fromhex(v["digest"])
        if got != exp:
            print("SHAKE128 MISMATCH idx", v["index"], got.hex()[:16], exp[:16])
            bad += 1
    print("CROSSCHECK shake128 total", len(v128), "bad", bad)
    return bad


if __name__ == "__main__":
    import sys
    sys.exit(1 if main() else 0)
