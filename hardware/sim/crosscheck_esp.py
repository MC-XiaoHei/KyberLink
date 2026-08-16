#!/usr/bin/env python3
"""OpenSSL（cryptography 库，OpenSSL 后端）对拍 ESP 帧 AES-256-GCM。
用法: source .venv/bin/activate && python crosscheck_esp.py
依赖: uv pip install cryptography
"""
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
import json

VECDIR = "/mnt/d/Projects/MC-XiaoHei/KyberLink/vectors/generated"


def build_frame(vec, ct_tag):
    spi = bytes.fromhex(vec["spi"])
    seq = bytes.fromhex(vec["seq"])
    iv = bytes.fromhex(vec["iv"])
    pt = bytes.fromhex(vec["plaintext"])
    pt_len = len(pt)
    ct = ct_tag[:pt_len]
    tag = ct_tag[pt_len:]
    f = bytearray()
    f += spi + seq + iv
    f += ct
    f += b"\x00"
    f += b"\x04"
    f += tag
    return bytes(f)


def main():
    vecs = json.load(open(VECDIR + "/esp.json"))
    bad = 0
    for v in vecs:
        key = bytes.fromhex(v["key"])
        iv = bytes.fromhex(v["iv"])
        pt = bytes.fromhex(v["plaintext"])
        aad = bytes.fromhex(v["spi"]) + bytes.fromhex(v["seq"])
        ct_tag = AESGCM(key).encrypt(iv, pt, aad)
        frame = build_frame(v, ct_tag)
        exp = bytes.fromhex(v["frame"])
        if frame != exp:
            print("FRAME MISMATCH idx", v.get("index"))
            for i in range(min(len(frame), len(exp))):
                if frame[i] != exp[i]:
                    print("  first diff byte", i, hex(frame[i]), hex(exp[i]))
                    break
            bad += 1
    print("CROSSCHECK esp total", len(vecs), "bad", bad)
    return bad


if __name__ == "__main__":
    import sys
    sys.exit(1 if main() else 0)
