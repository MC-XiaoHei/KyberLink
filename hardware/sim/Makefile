SIM ?= verilator
TOPLEVEL_LANG ?= verilog
RTL = $(PWD)/../rtl
GOWIN_SIMLIB ?= /mnt/c/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/simlib/gw5a
PYTHONPATH := $(PWD)/tests:$(PWD)/crosscheck:$(PYTHONPATH)
export PYTHONPATH

MOD ?= ntt
SIM_BUILD = sim_build/$(MOD)
.DEFAULT_GOAL = sim

TOP_aes = aes256_core
SRC_aes = $(RTL)/aes256_core.v $(RTL)/sbox_combo.v $(RTL)/sbox_combo_cf.v

TOP_bw = bw_dual
SRC_bw = $(RTL)/aes256_core_pipe.v $(RTL)/sbox_combo.v $(RTL)/sbox_combo_cf.v $(RTL)/ghash.v $(RTL)/gcm_stream.v $(PWD)/bw_dual.v

TOP_ghash = ghash
SRC_ghash = $(RTL)/ghash.v

TOP_gcm = gcm
SRC_gcm = $(RTL)/aes256_core.v $(RTL)/sbox_combo.v $(RTL)/ghash.v $(RTL)/gcm.v

TOP_gcm_stream = gcm_stream
SRC_gcm_stream = $(RTL)/aes256_core_pipe.v $(RTL)/sbox_combo.v $(RTL)/sbox_combo_cf.v $(RTL)/ghash.v $(RTL)/gcm_stream.v

TOP_bridge = bridge_top
SRC_bridge = $(RTL)/axis_pipe1.v $(RTL)/aes256_core_pipe.v $(RTL)/sbox_combo.v $(RTL)/sbox_combo_cf.v $(RTL)/ghash.v $(RTL)/gcm_stream.v $(RTL)/bridge_enc_path.v $(RTL)/bridge_dec_path.v $(RTL)/ip_udp_eth_rx.v $(RTL)/bridge_top.v $(wildcard $(RTL)/mac/*.v) $(PWD)/gowin_simlib.v
COMPILE_ARGS_bridge = -Wno-fatal

TOP_esp = esp
SRC_esp = $(RTL)/aes256_core.v $(RTL)/sbox_combo.v $(RTL)/ghash.v $(RTL)/gcm.v $(RTL)/esp.v

TOP_encap = ip_udp_eth_tx
SRC_encap = $(RTL)/ip_udp_eth_tx.v
COMPILE_ARGS_encap = -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-WIDTHCONCAT

TOP_esp_mac = esp_mac_top
SRC_esp_mac = $(RTL)/aes256_core.v $(RTL)/sbox_combo.v $(RTL)/ghash.v $(RTL)/gcm.v $(RTL)/esp.v $(RTL)/esp_rx.v $(RTL)/ip_udp_eth_tx.v $(RTL)/ip_udp_eth_rx.v $(RTL)/esp_mac_top.v $(wildcard $(RTL)/mac/*.v) $(PWD)/gowin_simlib.v
COMPILE_ARGS_esp_mac = -Wno-fatal

TOP_esp_mac_rx = esp_mac_top
SRC_esp_mac_rx = $(RTL)/aes256_core.v $(RTL)/sbox_combo.v $(RTL)/ghash.v $(RTL)/gcm.v $(RTL)/esp.v $(RTL)/esp_rx.v $(RTL)/ip_udp_eth_tx.v $(RTL)/ip_udp_eth_rx.v $(RTL)/esp_mac_top.v $(wildcard $(RTL)/mac/*.v) $(PWD)/gowin_simlib.v
COMPILE_ARGS_esp_mac_rx = -Wno-fatal

MODULE = $(MODULE_$(MOD))
ifeq ($(MODULE),)
MODULE = test_$(MOD)
endif

TOPLEVEL = $(TOP_$(MOD))
VERILOG_SOURCES = $(SRC_$(MOD))
EXTRA_ARGS = $(ARGS_$(MOD))
COMPILE_ARGS = $(COMPILE_ARGS_$(MOD))

.PHONY: clean
clean::
	rm -rf sim_build results.xml

include $(shell cocotb-config --makefiles)/Makefile.sim
