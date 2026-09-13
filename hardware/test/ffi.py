import ctypes
import os
import sys

DLL = os.path.abspath(os.path.join(
    __file__, "..", "..", "..", "software", "target"))

if sys.platform.startswith("win"):
    DLL = os.path.join(DLL, "x86_64-pc-windows-msvc", "debug",
                       "kyberlink_core.dll")
else:
    DLL = os.path.join(DLL, "x86_64-unknown-linux-gnu", "debug",
                       "libkyberlink_core.so")


def _load():
    lib = ctypes.CDLL(DLL)
    lib.kyb_fsm_new.restype = ctypes.c_void_p
    lib.kyb_fsm_new.argtypes = [
        ctypes.c_uint32,
        ctypes.POINTER(ctypes.c_uint8),
        ctypes.POINTER(ctypes.c_uint8),
        ctypes.POINTER(ctypes.c_uint8),
        ctypes.POINTER(ctypes.c_uint8),
        ctypes.POINTER(ctypes.c_uint8),
    ]
    lib.kyb_fsm_free.argtypes = [ctypes.c_void_p]
    lib.kyb_fsm_poll.restype = ctypes.c_uint32
    lib.kyb_fsm_poll.argtypes = [ctypes.c_void_p]
    lib.kyb_qbus_tick.restype = None
    lib.kyb_qbus_tick.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    lib.kyb_fsm_take_writes.restype = ctypes.c_uint32
    lib.kyb_fsm_take_writes.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_uint64),
        ctypes.c_uint32,
    ]
    lib.kyb_fsm_push_rx.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_uint8),
        ctypes.c_uint32,
    ]
    lib.kyb_fsm_fingerprint.argtypes = [
        ctypes.POINTER(ctypes.c_uint8),
        ctypes.POINTER(ctypes.c_uint8),
    ]
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

    def tick(self, n: int) -> None:
        _LIB.kyb_qbus_tick(self.h, n)

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
