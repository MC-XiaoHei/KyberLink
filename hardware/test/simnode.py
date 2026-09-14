import ctypes
import os
import sys

DLL = os.path.abspath(os.path.join(
    __file__, "..", "..", "..", "software", "target"))

if sys.platform.startswith("win"):
    DLL = os.path.join(DLL, "x86_64-pc-windows-msvc", "debug",
                       "kyberlink_simnode.dll")
else:
    DLL = os.path.join(DLL, "x86_64-unknown-linux-gnu", "debug",
                       "libkyberlink_simnode.so")


_U8P = ctypes.POINTER(ctypes.c_uint8)

SIGNATURES = {
    "kyb_fsm_new": (ctypes.c_void_p, [ctypes.c_uint32] + [_U8P] * 5),
    "kyb_fsm_free": (None, [ctypes.c_void_p]),
    "kyb_fsm_poll": (ctypes.c_uint32, [ctypes.c_void_p]),
    "kyb_simnode_set_status": (None, [ctypes.c_void_p, ctypes.c_uint32]),
    "kyb_fsm_take_writes": (
        ctypes.c_uint32,
        [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint64), ctypes.c_uint32],
    ),
    "kyb_fsm_push_rx": (None, [ctypes.c_void_p, _U8P, ctypes.c_uint32]),
    "kyb_fsm_fingerprint": (None, [_U8P, _U8P]),
}


def _load():
    lib = ctypes.CDLL(DLL)
    for name, (restype, argtypes) in SIGNATURES.items():
        fn = getattr(lib, name)
        fn.restype = restype
        fn.argtypes = argtypes
    return lib


_LIB = _load()


class Fsm:
    def __init__(self, seed_identity: bytes, seed_peer: bytes = b"", role: int = 0,
                 seed_d: bytes = b"", seed_z: bytes = b"", nonce: bytes = b""):
        self.h = _LIB.kyb_fsm_new(
            role,
            (ctypes.c_uint8 * 32).from_buffer_copy(_pad32(seed_peer)),
            (ctypes.c_uint8 * 32).from_buffer_copy(_pad32(seed_identity)),
            (ctypes.c_uint8 * 32).from_buffer_copy(_pad32(seed_d)),
            (ctypes.c_uint8 * 32).from_buffer_copy(_pad32(seed_z)),
            (ctypes.c_uint8 * 32).from_buffer_copy(_pad32(nonce)),
        )
        if not self.h:
            raise RuntimeError("kyb_fsm_new failed")

    def poll(self) -> int:
        return int(_LIB.kyb_fsm_poll(self.h))

    def set_status(self, value: int) -> None:
        _LIB.kyb_simnode_set_status(self.h, value)

    def take_writes(self):
        n = 4096
        buf = (ctypes.c_uint64 * n)()
        got = _LIB.kyb_fsm_take_writes(self.h, buf, n)
        out = []
        for i in range(got):
            v = buf[i]
            out.append((v & 0xFF, (v >> 32) & 0xFFFFFFFF))
        return out

    def push_rx(self, data: bytes):
        buf = (ctypes.c_uint8 * len(data)).from_buffer_copy(data)
        _LIB.kyb_fsm_push_rx(self.h, buf, len(data))

    def close(self):
        _LIB.kyb_fsm_free(self.h)


def fingerprint(seed_identity: bytes) -> bytes:
    out = (ctypes.c_uint8 * 32)()
    _LIB.kyb_fsm_fingerprint(
        (ctypes.c_uint8 * 32).from_buffer_copy(_pad32(seed_identity)), out)
    return bytes(out)


def _pad32(b: bytes) -> bytes:
    b = bytes(b)
    if len(b) < 32:
        b = b + b"\x00" * (32 - len(b))
    return b[:32]
