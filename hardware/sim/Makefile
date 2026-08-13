SIM ?= verilator
TOPLEVEL_LANG ?= verilog
RTL = $(PWD)/../rtl

MOD ?= ntt
SIM_BUILD = sim_build/$(MOD)
.DEFAULT_GOAL = sim

CORE = $(RTL)/keccak_f1600_round.v $(RTL)/shake.v

TOP_keccak = keccak_f1600_round
SRC_keccak = $(RTL)/keccak_f1600_round.v
TOP_shake = shake
SRC_shake = $(CORE)
TOP_shake128 = shake
SRC_shake128 = $(CORE)
ARGS_shake128 = -GRATE_BYTES=168
TOP_sample_ntt = sample_ntt
SRC_sample_ntt = $(CORE) $(RTL)/sample_ntt.v
TOP_sample_cbd = sample_cbd
SRC_sample_cbd = $(CORE) $(RTL)/sample_cbd.v
TOP_ntt = ntt
SRC_ntt = $(RTL)/ntt.v
TOP_invntt = invntt
SRC_invntt = $(RTL)/invntt.v
TOP_basemul = basemul
SRC_basemul = $(RTL)/basemul.v
TOP_aes = aes256_core
SRC_aes = $(RTL)/aes256_core.v

TOP_ghash = ghash
SRC_ghash = $(RTL)/ghash.v

TOP_gcm = gcm
SRC_gcm = $(RTL)/aes256_core.v $(RTL)/ghash.v $(RTL)/gcm.v

TOP_esp = esp
SRC_esp = $(RTL)/aes256_core.v $(RTL)/ghash.v $(RTL)/gcm.v $(RTL)/esp.v

TOP_sha3_256 = shake
SRC_sha3_256 = $(CORE)
ARGS_sha3_256 = -GRATE_BYTES=136 -GDOMAIN_BYTE=0x06
MODULE_sha3_256 = test_sha3

TOP_sha3_512 = shake
SRC_sha3_512 = $(CORE)
ARGS_sha3_512 = -GRATE_BYTES=72 -GDOMAIN_BYTE=0x06
MODULE_sha3_512 = test_sha3

MODULE = $(MODULE_$(MOD))
ifeq ($(MODULE),)
MODULE = test_$(MOD)
endif

TOPLEVEL = $(TOP_$(MOD))
VERILOG_SOURCES = $(SRC_$(MOD))
EXTRA_ARGS = $(ARGS_$(MOD))

.PHONY: clean
clean::
	rm -rf sim_build results.xml

include $(shell cocotb-config --makefiles)/Makefile.sim
