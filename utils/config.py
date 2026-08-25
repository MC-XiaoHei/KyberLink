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


def run_dir():
    ts = os.environ.get("RUN_TS")
    if ts:
        d = os.path.join(LOGS, os.environ.get("RUN_CMD", "run"), ts)
        os.makedirs(d, exist_ok=True)
        return d
    return None


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
    exe = "cocotb-config" + (".exe" if os.name == "nt" else "")
    return os.environ.get("COCOTB_CONFIG", os.path.join(os.path.dirname(sys.executable), exe))


def cocotb_lib_dir():
    return subprocess.check_output([cocotb_config(), "--lib-dir"], text=True).strip()


def verilator_env():
    v = verilator()
    env = dict(os.environ)
    os.environ.pop("VERILATOR_ROOT", None)
    env.pop("VERILATOR_ROOT", None)
    root = os.environ.get("VERILATOR_ROOT")
    if root and not os.path.exists(os.path.join(root, "bin", "verilator_bin")):
        root = None
    base = os.path.dirname(os.path.dirname(v))
    if not root:
        for cand in (os.path.join(base, "share", "verilator"), base):
            if os.path.exists(os.path.join(cand, "bin", "verilator_bin")):
                root = cand
                break
    if root and os.path.exists(os.path.join(root, "include", "verilated_std.sv")):
        env["VERILATOR_ROOT"] = root
        os.environ["VERILATOR_ROOT"] = root
    path = []
    for p in [os.path.join(BUILD, "bin")] + [p for p in os.environ.get("TOOLCHAIN_BIN", "").split(os.pathsep) if p]:
        if os.path.isdir(p):
            path.append(p)
    libs = os.environ.get("COCOTB_LIBS") or cocotb_lib_dir()
    if os.path.isdir(libs):
        path.append(libs)
    for seg in os.environ.get("PATH", "").split(os.pathsep):
        seg = seg.strip()
        if seg and os.path.isdir(seg) and seg not in path:
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
                R("sbox_combo_cf_lut.v"), R("ghash.v"), R("gcm_stream.v"), R("gcm_arb.v"),
                R("bridge_enc_path.v"), R("bridge_dec_path.v"), R("ip_udp_eth_rx.v"),
                R("lan_rx_mux.v"), R("bridge_top.v"), S("gowin_simlib.v")] +
               [os.path.join(R("mac"), f) for f in os.listdir(R("mac")) if f.endswith(".v")],
        "test": "test_bridge",
    },
    "bw": {
        "top": "bw_dual",
        "src": [R("aes256_core_pipe.v"), R("sb_sbox16.v"), S("gowin_dpb_sim.v"),
                R("sbox_combo_cf_lut.v"), R("ghash.v"), R("gcm_stream.v"), S("bw_dual.v")],
        "test": "test_bw",
    },
    "bw_enc": {
        "top": "bw_enc",
        "src": [R("axis_pipe1.v"), R("aes256_core_pipe.v"), R("sb_sbox16.v"), S("gowin_dpb_sim.v"),
                R("sbox_combo_cf_lut.v"), R("ghash.v"), R("gcm_stream.v"), R("gcm_arb.v"),
                R("bridge_enc_path.v"), S("bw_enc.v")],
        "test": "test_bw_enc",
    },
    "bw_dec": {
        "top": "bw_dec",
        "src": [R("axis_pipe1.v"), R("aes256_core_pipe.v"), R("sb_sbox16.v"), S("gowin_dpb_sim.v"),
                R("sbox_combo_cf_lut.v"), R("ghash.v"), R("gcm_stream.v"), R("gcm_arb.v"),
                R("bridge_dec_path.v"), S("bw_dec.v")],
        "test": "test_bw_dec",
    },
    "bw_mux": {
        "top": "bw_mux",
        "src": [R("lan_rx_mux.v"), S("bw_mux.v")],
        "test": "test_bw_mux",
    },
    "bw_mgmt": {
        "top": "bw_mgmt",
        "src": [R("axis_pipe1.v"), R("aes256_core_pipe.v"), R("sb_sbox16.v"), S("gowin_dpb_sim.v"),
                R("sbox_combo_cf_lut.v"), R("ghash.v"), R("gcm_stream.v"), R("gcm_arb.v"),
                R("bridge_enc_path.v"), R("bridge_dec_path.v"), R("ip_udp_eth_rx.v"),
                R("lan_rx_mux.v"), R("mgmt_buf.v"), R("hs_rx.v"), R("hs_tx.v"), R("mgmt_ctrl.v"),
                R("bridge_top.v"), S("gowin_simlib.v")] +
               [os.path.join(R("mac"), f) for f in sorted(os.listdir(R("mac"))) if f.endswith(".v")] +
               [S("bw_mgmt.v")],
        "test": "test_bw_mgmt",
    },
    "ghash": {
        "top": "ghash",
        "src": [R("ghash.v")],
        "test": "test_ghash",
    },
    "nrv_xip": {
        "top": "nrv_xip_top",
        "src": [os.path.join(BUILD, "neorv32_conv", "neorv32_wrapper.v"),
                S("nrv_xip_top.v"), S("w25q64_model.v")],
        "test": "test_nrv_xip",
    },
    "full_sim": {
        "top": "full_top_sim",
        "src": [R("axis_pipe1.v"), R("aes256_core_pipe.v"), R("sb_sbox16.v"), S("gowin_dpb_sim.v"),
                R("sbox_combo_cf_lut.v"), R("ghash.v"), R("gcm_stream.v"), R("gcm_arb.v"),
R("bridge_enc_path.v"), R("bridge_dec_path.v"), R("ip_udp_eth_rx.v"),
                R("lan_rx_mux.v"), R("mgmt_buf.v"), R("hs_rx.v"), R("hs_tx.v"), R("mgmt_ctrl.v"),
                R("bridge_top.v"), S("gowin_simlib.v")] +
               [os.path.join(R("mac"), f) for f in os.listdir(R("mac")) if f.endswith(".v")] +
              [os.path.join(BUILD, "neorv32_conv", "neorv32_full_wrapper.v"),
                 R("neorv32", "bridge_ctrl.v"), S("w25q64_model.v"), S("full_top_sim.v")],
        "test": "test_full_sim",
    },
    "dual": {
        "top": "dual_full_top_sim",
        "src": [R("axis_pipe1.v"), R("aes256_core_pipe.v"), R("sb_sbox16.v"), S("gowin_dpb_sim.v"),
                R("sbox_combo_cf_lut.v"), R("ghash.v"), R("gcm_stream.v"), R("gcm_arb.v"),
R("bridge_enc_path.v"), R("bridge_dec_path.v"), R("ip_udp_eth_rx.v"),
                R("lan_rx_mux.v"), R("mgmt_buf.v"), R("hs_rx.v"), R("hs_tx.v"), R("mgmt_ctrl.v"),
                R("bridge_top.v"), S("gowin_simlib.v")] +
               [os.path.join(R("mac"), f) for f in os.listdir(R("mac")) if f.endswith(".v")] +
              [os.path.join(BUILD, "neorv32_conv", "neorv32_full_wrapper.v"),
                 R("neorv32", "bridge_ctrl.v"), S("w25q64_model.v"),
                 S("full_top_sim.v"), S("dual_full_top_sim.v")],
        "test": "test_dual_stub",
    },
}

WNO = ["--timing", "-Wno-fatal", "-Wno-SELRANGE", "-Wno-WIDTH", "-Wno-UNOPTFLAT"]
