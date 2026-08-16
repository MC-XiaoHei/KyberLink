#!/usr/bin/env python3
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
import json

VECDIR = "/mnt/d/Projects/MC-XiaoHei/KyberLink/vectors/generated"


def main():
    vecs = json.load(open(VECDIR + "/cipher.json"))
    bad = 0
    for v in vecs:
        key = bytes.fromhex(v["key"])
        nonce = bytes.fromhex(v["nonce"])
        pt = bytes.fromhex(v["plaintext"])
        aad = bytes.fromhex(v["aad"])
        ct_tag = AESGCM(key).encrypt(nonce, pt, aad)
        exp = bytes.fromhex(v["ciphertext_tag"])
        if ct_tag != exp:
            print("GCM MISMATCH idx", v.get("index"))
            for i in range(min(len(ct_tag), len(exp))):
                if ct_tag[i] != exp[i]:
                    print("  first diff byte", i, hex(ct_tag[i]), hex(exp[i]))
                    break
            bad += 1
    print("CROSSCHECK gcm total", len(vecs), "bad", bad)
    return bad


if __name__ == "__main__":
    import sys
    sys.exit(1 if main() else 0)
