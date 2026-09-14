import json
import os
import random

from . import config
from .core import AppError, Result

N = 500


def cross(mode="gen"):
    if mode == "gen":
        return generate()
    if mode == "verify":
        return verify()
    raise AppError("unknown mode: %s" % mode, 2)


def _generated_dir():
    out = os.path.join(config.VECTORS, "generated")
    os.makedirs(out, exist_ok=True)
    return out


def generate():
    import oqs

    out = _generated_dir()
    rng = random.Random(0x4B21)
    kem = _gen_kem(oqs, rng)
    dsa = _gen_dsa(oqs, rng)
    json.dump(kem, open(os.path.join(out, "kem.json"), "w"))
    json.dump(dsa, open(os.path.join(out, "dsa.json"), "w"))
    print(f"generated {len(kem)} kem + {len(dsa)} dsa vectors -> {out}")
    return Result(
        "cross",
        config={"mode": "gen"},
        metrics={"kem": len(kem), "dsa": len(dsa)},
        artifacts={
            "kem": os.path.join(out, "kem.json"),
            "dsa": os.path.join(out, "dsa.json"),
        },
    )


def _gen_kem(oqs, rng):
    kem = []
    with oqs.KeyEncapsulation("ML-KEM-768") as k:
        for i in range(N):
            seed = bytes(rng.getrandbits(8) for _ in range(64))
            ek = k.generate_keypair_seed(seed)
            dk = k.export_secret_key()
            ct, ss = k.encap_secret(ek)
            kem.append(
                {
                    "index": i,
                    "seed": seed.hex(),
                    "ek": ek.hex(),
                    "dk": dk.hex(),
                    "ct": ct.hex(),
                    "ss": ss.hex(),
                }
            )
    return kem


def _gen_dsa(oqs, rng):
    dsa = []
    with oqs.Signature("ML-DSA-65") as s:
        for i in range(N):
            msg = bytes(rng.getrandbits(8) for _ in range(rng.randrange(0, 200)))
            pk = s.generate_keypair()
            sk = s.export_secret_key()
            sig = s.sign(msg)
            assert s.verify(msg, sig, pk)
            dsa.append(
                {
                    "index": i,
                    "msg": msg.hex(),
                    "pk": pk.hex(),
                    "sk": sk.hex(),
                    "sig": sig.hex(),
                }
            )
    return dsa


def verify():
    import oqs

    out = _generated_dir()
    _verify_kem(oqs, out)
    _verify_dsa(oqs, out)
    return Result("cross", config={"mode": "verify"})


def _verify_kem(oqs, out):
    kem_in = json.load(open(os.path.join(out, "kem.json")))
    with oqs.KeyEncapsulation("ML-KEM-768") as k:
        for v in json.load(open(os.path.join(out, "kem_out.json"))):
            k.generate_keypair_seed(bytes.fromhex(kem_in[v["index"]]["seed"]))
            ss = k.decap_secret(bytes.fromhex(v["ct"]))
            assert ss.hex() == v["ss"], f"kem {v['index']}"
    print("kem_out verified (rust encaps -> liboqs decaps)")


def _verify_dsa(oqs, out):
    with oqs.Signature("ML-DSA-65") as s:
        for v in json.load(open(os.path.join(out, "dsa_out.json"))):
            assert s.verify(
                bytes.fromhex(v["msg"]), bytes.fromhex(v["sig"]), bytes.fromhex(v["pk"])
            ), f"dsa {v['index']}"
    print("dsa_out verified (rust sign -> liboqs verify)")
