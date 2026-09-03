import json
import os
import random

from . import config
from .core import AppError, Result

N = 500


def cross(mode="gen"):
    import oqs

    out = os.path.join(config.VECTORS, "generated")
    os.makedirs(out, exist_ok=True)
    rng = random.Random(0x4B21)

    if mode == "gen":
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
        with open(os.path.join(out, "kem.json"), "w") as f:
            json.dump(kem, f)

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
        with open(os.path.join(out, "dsa.json"), "w") as f:
            json.dump(dsa, f)
        print(f"generated {len(kem)} kem + {len(dsa)} dsa vectors -> {out}")
        return Result(
            "cross",
            config={"mode": mode},
            metrics={"kem": len(kem), "dsa": len(dsa)},
            artifacts={"kem": os.path.join(out, "kem.json"), "dsa": os.path.join(out, "dsa.json")},
        )

    if mode == "verify":
        kem_in = json.load(open(os.path.join(out, "kem.json")))
        with oqs.KeyEncapsulation("ML-KEM-768") as k:
            for v in json.load(open(os.path.join(out, "kem_out.json"))):
                seed = bytes.fromhex(kem_in[v["index"]]["seed"])
                k.generate_keypair_seed(seed)
                ss = k.decap_secret(bytes.fromhex(v["ct"]))
                assert ss.hex() == v["ss"], f"kem {v['index']}"
        print("kem_out verified (rust encaps -> liboqs decaps)")

        with oqs.Signature("ML-DSA-65") as s:
            for v in json.load(open(os.path.join(out, "dsa_out.json"))):
                assert s.verify(
                    bytes.fromhex(v["msg"]), bytes.fromhex(v["sig"]), bytes.fromhex(v["pk"])
                ), f"dsa {v['index']}"
        print("dsa_out verified (rust sign -> liboqs verify)")
        return Result("cross", config={"mode": mode})

    raise AppError("unknown mode: %s" % mode, 2)
