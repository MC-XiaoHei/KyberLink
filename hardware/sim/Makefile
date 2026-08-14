SIM ?= verilator
TOPLEVEL_LANG ?= verilog
RTL = $(PWD)/../rtl

MOD ?= ntt
SIM_BUILD = sim_build/$(MOD)
.DEFAULT_GOAL = sim

CORE = $(RTL)/keccak_f1600_round.v $(RTL)/shake.v

TOP_keccak = keccak_f1600_round
SRC_keccak = $(RTL)/keccak_f1600_round.v
TOP_ntt_dsa = ntt_dsa
SRC_ntt_dsa = $(RTL)/ntt_dsa.v
TOP_invntt_dsa = invntt_dsa
SRC_invntt_dsa = $(RTL)/invntt_dsa.v
TOP_matmul_dsa = matmul_dsa
SRC_matmul_dsa = $(RTL)/matmul_dsa.v
TOP_mldsa_keygen = mldsa_keygen
SRC_mldsa_keygen = $(RTL)/keccak_f1600_round.v $(RTL)/shake.v $(RTL)/rej_ntt.v $(RTL)/rej_bounded.v $(RTL)/ntt_dsa.v $(RTL)/invntt_dsa.v $(RTL)/matmul_dsa.v $(RTL)/pack_dsa.v $(RTL)/mldsa_keygen.v
TOP_rej_ntt = rej_ntt
SRC_rej_ntt = $(CORE) $(RTL)/rej_ntt.v
TOP_rej_bounded = rej_bounded
SRC_rej_bounded = $(CORE) $(RTL)/rej_bounded.v
TOP_expand_mask = expand_mask
SRC_expand_mask = $(CORE) $(RTL)/expand_mask.v
TOP_sample_in_ball = sample_in_ball
SRC_sample_in_ball = $(CORE) $(RTL)/sample_in_ball.v
TOP_shake = shake
SRC_shake = $(CORE)
TOP_shake128 = shake
SRC_shake128 = $(CORE)
ARGS_shake128 = -GRATE_BYTES=168
COMPILE_ARGS_mldsa_keygen = --unroll-count 2048
TOP_sample_ntt = sample_ntt
SRC_sample_ntt = $(CORE) $(RTL)/sample_ntt.v
TOP_sample_cbd = sample_cbd
SRC_sample_cbd = $(CORE) $(RTL)/sample_cbd.v
TOP_sample_cbd3 = sample_cbd3
SRC_sample_cbd3 = $(CORE) $(RTL)/sample_cbd3.v
TOP_ntt = ntt
SRC_ntt = $(RTL)/ntt.v
TOP_invntt = invntt
SRC_invntt = $(RTL)/invntt.v
TOP_basemul = basemul
SRC_basemul = $(RTL)/basemul_core.v $(RTL)/gamma_rom.v $(RTL)/basemul.v
TOP_matmul = matmul
SRC_matmul = $(RTL)/basemul_core.v $(RTL)/gamma_rom.v $(RTL)/matmul.v
TOP_dotmul = dotmul
SRC_dotmul = $(RTL)/basemul_core.v $(RTL)/gamma_rom.v $(RTL)/dotmul.v
TOP_kem_keygen = kem_keygen
SRC_kem_keygen = $(RTL)/keccak_f1600_round.v $(RTL)/shake.v $(RTL)/sample_ntt.v $(RTL)/sample_cbd.v $(RTL)/ntt.v $(RTL)/basemul_core.v $(RTL)/gamma_rom.v $(RTL)/matmul.v $(RTL)/pack.v $(RTL)/kem_keygen.v
TOP_kem_encaps = kem_encaps
SRC_kem_encaps = $(RTL)/keccak_f1600_round.v $(RTL)/shake.v $(RTL)/sample_ntt.v $(RTL)/sample_cbd.v $(RTL)/ntt.v $(RTL)/invntt.v $(RTL)/basemul_core.v $(RTL)/gamma_rom.v $(RTL)/matmul.v $(RTL)/dotmul.v $(RTL)/pack.v $(RTL)/compress.v $(RTL)/kem_encaps.v
TOP_kem_decap = kem_decap
SRC_kem_decap = $(RTL)/keccak_f1600_round.v $(RTL)/shake.v $(RTL)/sample_ntt.v $(RTL)/sample_cbd.v $(RTL)/ntt.v $(RTL)/invntt.v $(RTL)/basemul_core.v $(RTL)/gamma_rom.v $(RTL)/matmul.v $(RTL)/dotmul.v $(RTL)/pack.v $(RTL)/compress.v $(RTL)/kem_decap.v
TOP_aes = aes256_core
SRC_aes = $(RTL)/aes256_core.v

TOP_ghash = ghash
SRC_ghash = $(RTL)/ghash.v

TOP_gcm = gcm
SRC_gcm = $(RTL)/aes256_core.v $(RTL)/ghash.v $(RTL)/gcm.v

TOP_esp = esp
SRC_esp = $(RTL)/aes256_core.v $(RTL)/ghash.v $(RTL)/gcm.v $(RTL)/esp.v

TOP_pack = pack
SRC_pack = $(RTL)/pack.v
TOP_pack_dsa = pack_dsa
SRC_pack_dsa = $(RTL)/pack_dsa.v

TOP_compress = compress
SRC_compress = $(RTL)/compress.v

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
COMPILE_ARGS = $(COMPILE_ARGS_$(MOD))

.PHONY: clean
clean::
	rm -rf sim_build results.xml

include $(shell cocotb-config --makefiles)/Makefile.sim
