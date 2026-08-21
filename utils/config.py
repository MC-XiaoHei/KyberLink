import os
import shutil
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RTL = os.path.join(REPO, "hardware", "rtl")
SIM = os.path.join(REPO, "hardware", "sim")
SYNTH = os.path.join(REPO, "hardware", "synth")
BUILD = os.path.join(REPO, "build")
LOGS = os.path.join(REPO, "logs")
VECTORS = os.path.join(REPO, "vectors")
VENV_PY = os.path.join(REPO, ".venv", "bin", "python.exe")


def load_env():
    envf = os.path.join(REPO, ".env")
    if not os.path.exists(envf):
        return
    with open(envf, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, _, v = line.partition("=")
            os.environ.setdefault(k.strip(), v.strip())


def ensure_shims():
    d = os.path.join(BUILD, "bin")
    os.makedirs(d, exist_ok=True)
    if not os.path.exists(os.path.join(d, "verilator.exe")):
        v = os.environ.get("VERILATOR")
        if v and os.path.exists(v):
            shutil.copy2(v, os.path.join(d, "verilator.exe"))
    if not os.path.exists(os.path.join(d, "make.exe")):
        for p in os.environ.get("TOOLCHAIN_BIN", "").split(os.pathsep):
            cand = os.path.join(p, "mingw32-make.exe")
            if os.path.exists(cand):
                shutil.copy2(cand, os.path.join(d, "make.exe"))
                break


def ensure_py_runtime(build_dir):
    src = None
    for p in os.environ.get("TOOLCHAIN_BIN", "").split(os.pathsep):
        if os.path.exists(os.path.join(p, "libpython3.14.dll")):
            src = p
            break
    if src:
        for dll in ("libpython3.14.dll", "libgcc_s_seh-1.dll", "libstdc++-6.dll",
                    "libwinpthread-1.dll", "libssp-0.dll", "libffi-8.dll", "zlib1.dll"):
            s = os.path.join(src, dll)
            if not os.path.exists(s):
                s = os.path.join(BUILD, "bin", dll)
            if os.path.exists(s) and not os.path.exists(os.path.join(build_dir, dll)):
                shutil.copy2(s, os.path.join(build_dir, dll))


def find_tool(env, name):
    p = os.environ.get(env)
    if p and os.path.exists(p):
        return p
    w = shutil.which(name)
    if w:
        return w
    sys.exit(f"tool {name} not found: set env {env} or add to PATH")


def verilator():
    return find_tool("VERILATOR", "verilator")


def gw_sh():
    gh = os.environ.get("GOWIN_HOME")
    if gh:
        p = os.path.join(gh, "IDE", "bin", "gw_sh.exe")
        if os.path.exists(p):
            return p
    return find_tool("GW_SH", "gw_sh")


def cocotb_config():
    return os.environ.get("COCOTB_CONFIG", os.path.join(os.path.dirname(VENV_PY), "cocotb-config.exe"))


def cocotb_lib_dir():
    return subprocess.check_output([cocotb_config(), "--lib-dir"], text=True).strip()


def verilator_env():
    v = verilator()
    env = dict(os.environ)
    root = os.environ.get("VERILATOR_ROOT")
    base = os.path.dirname(os.path.dirname(v))
    if not root and os.path.exists(os.path.join(base, "share", "verilator", "include", "verilated_std.sv")):
        root = os.path.join(base, "share", "verilator")
    if root:
        env["VERILATOR_ROOT"] = root
    path = []
    for p in [os.path.join(BUILD, "bin")] + [p for p in os.environ.get("TOOLCHAIN_BIN", "").split(os.pathsep) if p]:
        if os.path.isdir(p):
            path.append(p)
    libs = os.environ.get("COCOTB_LIBS") or cocotb_lib_dir()
    if os.path.isdir(libs):
        path.append(libs)
    for seg in os.environ.get("PATH", "").split(os.pathsep):
        seg = seg.strip()
        if len(seg) >= 2 and seg[1] == ":" and seg[0].isalpha() and os.path.isdir(seg) and seg not in path:
            path.append(seg)
    env["PATH"] = os.pathsep.join(path)
    return env


R = lambda *p: os.path.join(RTL, *p)
S = lambda *p: os.path.join(SIM, *p)

MODS = {
    "aes_pipe": {
        "top": "aes256_core_pipe",
        "src": [R("aes256_core_pipe.v"), R("sb_sbox16.v"), S("gowin_dpb_sim.v"), R("sbox_combo_cf_lut.v")],
        "test": "test_aes_pipe",
    },
    "gcm_stream": {
        "top": "gcm_stream",
        "src": [R("aes256_core_pipe.v"), R("sb_sbox16.v"), S("gowin_dpb_sim.v"),
                R("sbox_combo_cf_lut.v"), R("ghash.v"), R("gcm_stream.v")],
        "test": "test_gcm_stream",
    },
    "bridge": {
        "top": "bridge_top",
        "src": [R("axis_pipe1.v"), R("aes256_core_pipe.v"), R("sb_sbox16.v"), S("gowin_dpb_sim.v"),
                R("sbox_combo_cf_lut.v"), R("ghash.v"), R("gcm_stream.v"),
                R("bridge_enc_path.v"), R("bridge_dec_path.v"), R("ip_udp_eth_rx.v"),
                R("bridge_top.v"), S("gowin_simlib.v")] +
               [os.path.join(R("mac"), f) for f in os.listdir(R("mac")) if f.endswith(".v")],
        "test": "test_bridge",
    },
    "bw": {
        "top": "bw_dual",
        "src": [R("aes256_core_pipe.v"), R("sb_sbox16.v"), S("gowin_dpb_sim.v"),
                R("sbox_combo_cf_lut.v"), R("ghash.v"), R("gcm_stream.v"), S("bw_dual.v")],
        "test": "test_bw",
    },
    "ghash": {
        "top": "ghash",
        "src": [R("ghash.v")],
        "test": "test_ghash",
    },
}

WNO = ["-Wno-fatal", "-Wno-SELRANGE", "-Wno-WIDTH", "-Wno-UNOPTFLAT"]
