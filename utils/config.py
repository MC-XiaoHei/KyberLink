import os
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RTL = os.path.join(REPO, "hardware", "rtl")
TEST_DIR = os.path.join(REPO, "hardware", "test")
SYNTH = os.path.join(REPO, "hardware", "synth")
VECTORS = os.path.join(REPO, "vectors")
BUILD = os.path.join(REPO, "build")
LOGS = os.path.join(REPO, "logs")

WNO = [
    "--timing",
    "-Wno-WIDTH",
    "-Wno-MULTIDRIVEN",
    "-Wno-SELRANGE",
    "-Wno-PINMISSING",
    "-Wno-TIMESCALEMOD",
    "-Wno-CASEINCOMPLETE",
]


def R(*p):
    return os.path.join(RTL, *p)


def S(*p):
    return os.path.join(TEST_DIR, *p)


UNIT = ["aes", "aes_bw", "gcm", "spi", "eth", "bram"]
INTG = ["bridge", "bw", "full_single", "full_dual"]

BRIDGE_SRC = [
    R("sbox8.v"),
    R("sbox8_dist.v"),
    R("sbox16.v"),
    R("aes256_core.v"),
    R("ghash.v"),
    R("gcm_enc.v"),
    R("gcm_dec.v"),
    R("bram_128x256.v"),
    R("bridge_enc_path.v"),
    R("bridge_dec_path.v"),
    R("bridge_top.v"),
    S("gowin_dpb_sim.v"),
]
FULL_CORE = [
    R("sbox8.v"),
    R("sbox8_dist.v"),
    R("sbox16.v"),
    R("aes256_core.v"),
    R("ghash.v"),
    R("gcm_enc.v"),
    R("gcm_dec.v"),
    R("bridge_enc_path.v"),
    R("bridge_dec_path.v"),
    R("bridge_top.v"),
    R("bram_128x256.v"),
    R("bram_32x2048.v"),
    R("spi_slave.v"),
    R("spi_regs.v"),
    R("spi_top.v"),
    R("ip_udp_eth_rx.v"),
    R("ip_udp_eth_tx.v"),
    R("full_top.v"),
]
MAC = [
    R("mac/eth_mac_1g.v"),
    R("mac/eth_mac_1g_rgmii.v"),
    R("mac/eth_mac_1g_rgmii_fifo.v"),
    R("mac/axis_adapter.v"),
    R("mac/axis_async_fifo.v"),
    R("mac/axis_async_fifo_adapter.v"),
    R("mac/axis_eth_fcs.v"),
    R("mac/axis_eth_fcs_check.v"),
    R("mac/axis_eth_fcs_insert.v"),
    R("mac/axis_gmii_rx.v"),
    R("mac/axis_gmii_tx.v"),
    R("mac/iddr.v"),
    R("mac/oddr.v"),
    R("mac/rgmii_phy_if.v"),
    R("mac/lfsr.v"),
    R("mac/ssio_ddr_in.v"),
    R("mac/ssio_ddr_out.v"),
    R("mac/ssio_sdr_in.v"),
    R("mac/ssio_sdr_out.v"),
]

CONF = {
    "aes": {
        "top": "aes256_core",
        "src": [
            R("sbox8.v"),
            R("sbox8_dist.v"),
            R("sbox16.v"),
            R("aes256_core.v"),
            R("bram_128x256.v"),
            S("gowin_dpb_sim.v"),
        ],
    },
    "aes_bw": {
        "top": "aes256_core",
        "src": [
            R("sbox8.v"),
            R("sbox8_dist.v"),
            R("sbox16.v"),
            R("aes256_core.v"),
            R("bram_128x256.v"),
            S("gowin_dpb_sim.v"),
        ],
    },
    "gcm": {
        "top": "gcm_stream",
        "src": [
            R("sbox8.v"),
            R("sbox8_dist.v"),
            R("sbox16.v"),
            R("aes256_core.v"),
            R("ghash.v"),
            R("gcm_stream.v"),
            R("bram_128x256.v"),
            S("gowin_dpb_sim.v"),
        ],
    },
    "bridge": {
        "top": "bridge_top",
        "src": BRIDGE_SRC,
    },
    "bw": {
        "top": "bridge_top",
        "src": BRIDGE_SRC,
    },
    "spi": {
        "top": "spi_top",
        "src": [R("spi_slave.v"), R("spi_regs.v"), R("spi_top.v")],
    },
    "eth": {
        "top": "eth_top",
        "src": [R("ip_udp_eth_rx.v"), R("ip_udp_eth_tx.v"), R("eth_top.v")],
    },
    "bram": {
        "top": "bram_128x256",
        "src": [R("bram_128x256.v"), S("gowin_dpb_sim.v")],
    },
    "full_single": {
        "top": "full_top",
        "test_module": "tb_full",
        "src": FULL_CORE + [S("gowin_dpb_sim.v")],
    },
    "full_dual": {
        "top": "dual_top",
        "test_module": "tb_dual",
        "src": FULL_CORE + MAC + [S("gowin_dpb_sim.v"), S("dual_top.v")],
    },
}


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


def gw_sh():
    gh = os.environ.get("GOWIN_HOME", "")
    return os.path.join(gh, "IDE", "bin", "gw_sh.exe") if gh else "gw_sh"


def run_dir(suite="run"):
    ts = os.environ.get("RUN_TS", f"{time.strftime('%y%m%d')}/{time.strftime('%H%M')}")
    d = os.path.join(LOGS, ts, suite)
    os.makedirs(d, exist_ok=True)
    return d
