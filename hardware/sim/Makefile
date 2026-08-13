SIM ?= verilator
TOPLEVEL_LANG ?= verilog
RTL = $(PWD)/../rtl

MOD ?= ntt
MODULE = test_$(MOD)
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

TOPLEVEL = $(TOP_$(MOD))
VERILOG_SOURCES = $(SRC_$(MOD))
EXTRA_ARGS = $(ARGS_$(MOD))

.PHONY: clean
clean::
	rm -rf sim_build results.xml

include $(shell cocotb-config --makefiles)/Makefile.sim
