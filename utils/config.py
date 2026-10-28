import os
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RTL = os.path.join(REPO, "hardware", "rtl")
TEST_DIR = os.path.join(REPO, "hardware", "test")
SYNTH = os.path.join(REPO, "hardware", "synth")
SELFTEST_DIR = os.path.join(REPO, "hardware", "selftest")
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

GOWIN_DPB = None


def R(*p):
    return os.path.join(RTL, *p)


def S(*p):
    return os.path.join(TEST_DIR, *p)


def ST(*p):
    return os.path.join(SELFTEST_DIR, *p)


GOWIN_DPB = S("gowin_dpb_sim.v")
GOWIN_PLL = S("gowin_pll_sim.v")


SELFTEST = [
    ST("self_test_port.v"),
    ST("self_test_regs.v"),
    ST("self_test_top.v"),
]


UNIT = ["aes_pipe", "gcm", "spi"]
INTG = ["bridge", "flow", "bw", "full", "node", "line", "gmii_rx", "diag2", "spi_big", "top", "fifo", "selftest"]
MIRI = ["kyberlink-core", "kyberlink-simnode"]

AES_CORE = [
    R("aes256_core_pipe.v"),
    R("sb_sbox16.v"),
]

GCM = [
    R("ghash.v"),
    R("gcm_stream.v"),
    R("gcm_arb.v"),
]

BRIDGE = [
    R("bram_128x16.v"),
    R("bridge_enc_path.v"),
    R("bridge_dec_path.v"),
    R("bridge_top.v"),
]

CTRL_PLANE = [
    R("bram_32x512.v"),
    R("spi_slave.v"),
    R("spi_regs.v"),
    R("spi_top.v"),
    R("ip_udp_eth_rx.v"),
    R("ip_udp_eth_tx.v"),
]

FULL_CORE = (
    AES_CORE
    + GCM
    + BRIDGE
    + CTRL_PLANE
    + [
        R("link_core.v"),
    ]
)

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
    "aes_pipe": {
        "top": "aes256_core_pipe",
        "test_module": "tb_aes_pipe",
        "src": [
            R("sb_sbox16.v"),
            R("aes256_core_pipe.v"),
            R("bram_128x16.v"),
            GOWIN_DPB,
        ],
    },
    "gcm": {
        "top": "gcm_stream",
        "src": AES_CORE + GCM + [R("bram_128x16.v"), GOWIN_DPB],
    },
    "bridge": {
        "top": "bridge_top",
        "src": AES_CORE + GCM + BRIDGE + [GOWIN_DPB],
    },
    "bw": {
        "top": "bridge_top",
        "src": AES_CORE + GCM + BRIDGE + [GOWIN_DPB],
    },
    "flow": {
        "top": "link_core",
        "test_module": "tb_flow",
        "src": FULL_CORE + [GOWIN_DPB],
    },
    "diag2": {
        "top": "bridge_top",
        "test_module": "tb_enc_maxframe",
        "src": AES_CORE + GCM + BRIDGE + [GOWIN_DPB],
    },
    "spi": {
        "top": "spi_top",
        "test_module": "tb_spi_ctrl",
        "src": [
            R("spi_slave.v"),
            R("spi_regs.v"),
            R("spi_top.v"),
            R("bram_32x512.v"),
            GOWIN_DPB,
        ],
    },
    "spi_big": {
        "top": "spi_top",
        "test_module": "tb_spi_hsk_big",
        "src": [
            R("spi_slave.v"),
            R("spi_regs.v"),
            R("spi_top.v"),
            R("bram_32x512.v"),
            GOWIN_DPB,
        ],
    },
    "full": {
        "top": "dual_node_sim",
        "test_module": "tb_full",
        "src": FULL_CORE + MAC + [GOWIN_DPB, S("dual_node_sim.v")],
    },
    "node": {
        "top": "link_core",
        "test_module": "tb_node",
        "src": FULL_CORE + [GOWIN_DPB],
    },
    "gmii_rx": {
        "top": "gmii_rx_top",
        "test_module": "tb_gmii_rx",
        "src": MAC + [S("gmii_rx_top.v")],
    },
    "line": {
        "top": "link_core",
        "test_module": "tb_line_rate",
        "src": FULL_CORE + [GOWIN_DPB],
    },
    "top": {
        "top": "kyberlink_top",
        "test_module": "tb_top",
        "src": FULL_CORE + MAC + [GOWIN_DPB, GOWIN_PLL, R("clk_pll.v"), R("kyberlink_top.v")],
    },
    "fifo": {
        "top": "axis_sync_fifo",
        "test_module": "tb_axis_fifo",
        "src": [R("kyberlink_top.v")],
    },
    "selftest": {
        "top": "selftest_sim",
        "test_module": "tb_selftest",
        "src": [
            ST("self_test_port.v"),
            ST("self_test_regs.v"),
            R("spi_slave.v"),
            S("selftest_sim.v"),
        ],
    },
}


UNIT_TEST = {
    "gcm": "tb_gcm_stream",
    "spi": "tb_spi_ctrl",
}
INTG_TEST = {
    "top": "tb_top",
    "fifo": "tb_axis_fifo",
    "bw": "tb_bridge_bw",
    "diag2": "tb_enc_maxframe",
    "spi_big": "tb_spi_hsk_big",
    "full": "tb_full",
    "node": "tb_node",
    "line": "tb_line_rate",
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
    ts = os.environ.get(
        "RUN_TS",
        f"{time.strftime('%y%m%d')}/{time.strftime('%H')}/{time.strftime('%M')}/{time.strftime('%S')}",
    )
    d = os.path.join(LOGS, ts, suite)
    os.makedirs(d, exist_ok=True)
    return d
