#!/usr/bin/env python3
from hashlib import sha3_256
import json

VECDIR = "/mnt/d/Projects/MC-XiaoHei/KyberLink/vectors/generated"

BLOCK = 136


def hmac(key, msg):
    if len(key) > BLOCK:
        key = sha3_256(key).digest()
    key += b"\x00" * (BLOCK - len(key))
    ipad = bytes(x ^ 0x36 for x in key)
    opad = bytes(x ^ 0x5C for x in key)
    return sha3_256(opad + sha3_256(ipad + msg).digest()).digest()


def hkdf_expand(prk, info, length):
    out = b""
    t = b""
    i = 1
    while len(out) < length:
        t = hmac(prk, t + info + bytes([i]))
        out += t
        i += 1
    return out[:length]


def main():
    vecs = json.load(open(VECDIR + "/hkdf.json"))
    bad = 0
    for v in vecs:
        salt = bytes.fromhex(v["h4"])
        ikm = bytes.fromhex(v["ss_i"]) + bytes.fromhex(v["ss_r"])
        spi_i = bytes.fromhex(v["spi_i"])
        spi_r = bytes.fromhex(v["spi_r"])
        prk = hmac(salt, ikm)
        info = b"KyberLink-v1-SA" + spi_i + spi_r
        okm = hkdf_expand(prk, info, 96)
        exp_prk = bytes.fromhex(v["prk"])
        exp_okm = bytes.fromhex(v["okm"])
        if prk != exp_prk:
            print("PRK MISMATCH idx", v.get("index"), prk.hex()[:16], exp_prk.hex()[:16])
            bad += 1
        if okm != exp_okm:
            print("OKM MISMATCH idx", v.get("index"), okm.hex()[:16], exp_okm.hex()[:16])
            bad += 1
    print("CROSSCHECK hkdf total", len(vecs), "bad", bad)
    return bad


if __name__ == "__main__":
    import sys
    sys.exit(1 if main() else 0)
