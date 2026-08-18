SIM ?= verilator
TOPLEVEL_LANG ?= verilog
RTL = $(PWD)/../rtl
PYTHONPATH := $(PWD)/tests:$(PWD)/crosscheck:$(PYTHONPATH)
export PYTHONPATH

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

TOP_sha3_512 = shake
SRC_sha3_512 = $(CORE)
ARGS_sha3_512 = -GRATE_BYTES=72 -GDOMAIN_BYTE=0x06
MODULE_sha3_512 = test_sha3


TOP_rej_ntt = top_rej_ntt
SRC_rej_ntt = $(RTL)/keccak_f1600_round.v $(RTL)/keccak_engine.v $(RTL)/rej_ntt.v $(PWD)/wrappers/top_rej_ntt.v

TOP_rej_bounded = top_rej_bounded
SRC_rej_bounded = $(RTL)/keccak_f1600_round.v $(RTL)/keccak_engine.v $(RTL)/rej_bounded.v $(PWD)/wrappers/top_rej_bounded.v

TOP_expand_mask = top_expand_mask
SRC_expand_mask = $(RTL)/keccak_f1600_round.v $(RTL)/keccak_engine.v $(RTL)/expand_mask.v $(PWD)/wrappers/top_expand_mask.v

TOP_sample_in_ball = top_sample_in_ball
SRC_sample_in_ball = $(RTL)/keccak_f1600_round.v $(RTL)/keccak_engine.v $(RTL)/sample_in_ball.v $(PWD)/wrappers/top_sample_in_ball.v

TOP_sample_ntt = top_sample_ntt
SRC_sample_ntt = $(RTL)/keccak_f1600_round.v $(RTL)/keccak_engine.v $(RTL)/sample_ntt.v $(PWD)/wrappers/top_sample_ntt.v

TOP_sample_cbd = top_sample_cbd
SRC_sample_cbd = $(RTL)/keccak_f1600_round.v $(RTL)/keccak_engine.v $(RTL)/sample_cbd.v $(PWD)/wrappers/top_sample_cbd.v

TOP_sample_cbd3 = top_sample_cbd3
SRC_sample_cbd3 = $(RTL)/keccak_f1600_round.v $(RTL)/keccak_engine.v $(RTL)/sample_cbd3.v $(PWD)/wrappers/top_sample_cbd3.v


TOP_sha3_256 = top_sha3_256
SRC_sha3_256 = $(RTL)/keccak_f1600_round.v $(RTL)/keccak_engine.v $(RTL)/engine_client.v $(RTL)/sha3_256.v $(PWD)/wrappers/top_sha3_256.v

TOP_hkdf_sha3_256 = top_hkdf_sha3_256
SRC_hkdf_sha3_256 = $(RTL)/keccak_f1600_round.v $(RTL)/keccak_engine.v $(RTL)/engine_client.v $(RTL)/sha3_256.v $(RTL)/hkdf_sha3_256.v $(PWD)/wrappers/top_hkdf_sha3_256.v


TOP_ntt_dsa = ntt_dsa
SRC_ntt_dsa = $(RTL)/ntt_dsa.v

TOP_invntt_dsa = invntt_dsa
SRC_invntt_dsa = $(RTL)/invntt_dsa.v

TOP_matmul_dsa = matmul_dsa
SRC_matmul_dsa = $(RTL)/matmul_dsa.v

TOP_pack_dsa = pack_dsa
SRC_pack_dsa = $(RTL)/pack_dsa.v

TOP_mldsa_keygen = top_mldsa_keygen
SRC_mldsa_keygen = $(RTL)/keccak_f1600_round.v $(RTL)/keccak_engine.v $(RTL)/engine_client.v $(RTL)/rej_ntt.v $(RTL)/rej_bounded.v $(RTL)/ntt_dsa.v $(RTL)/invntt_dsa.v $(RTL)/matmul_dsa.v $(RTL)/pack_dsa.v $(RTL)/mldsa_keygen.v $(PWD)/wrappers/top_mldsa_keygen.v

TOP_mldsa_verify = top_mldsa_verify
SRC_mldsa_verify = $(RTL)/keccak_f1600_round.v $(RTL)/keccak_engine.v $(RTL)/engine_client.v $(RTL)/rej_ntt.v $(RTL)/sample_in_ball.v $(RTL)/ntt_dsa.v $(RTL)/invntt_dsa.v $(RTL)/matmul_dsa.v $(RTL)/pack_dsa.v $(RTL)/mldsa_verify.v $(PWD)/wrappers/top_mldsa_verify.v

TOP_mldsa_sign = top_mldsa_sign
SRC_mldsa_sign = $(RTL)/keccak_f1600_round.v $(RTL)/keccak_engine.v $(RTL)/engine_client.v $(RTL)/rej_ntt.v $(RTL)/sample_in_ball.v $(RTL)/expand_mask.v $(RTL)/ntt_dsa.v $(RTL)/invntt_dsa.v $(RTL)/matmul_dsa.v $(RTL)/pack_dsa.v $(RTL)/mldsa_sign.v $(PWD)/wrappers/top_mldsa_sign.v

COMPILE_ARGS_mldsa_keygen = --unroll-count 2048 -O3
COMPILE_ARGS_mldsa_verify = --unroll-count 4096 -O3
COMPILE_ARGS_mldsa_sign = --unroll-count 2048 -O3 --public-flat-rw


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

TOP_pack = pack
SRC_pack = $(RTL)/pack.v

TOP_compress = compress
SRC_compress = $(RTL)/compress.v

TOP_kem_keygen = top_kem_keygen
SRC_kem_keygen = $(RTL)/keccak_f1600_round.v $(RTL)/keccak_engine.v $(RTL)/engine_client.v $(RTL)/sample_ntt.v $(RTL)/sample_cbd.v $(RTL)/ntt.v $(RTL)/basemul_core.v $(RTL)/gamma_rom.v $(RTL)/matmul.v $(RTL)/pack.v $(RTL)/kem_keygen.v $(PWD)/wrappers/top_kem_keygen.v

TOP_kem_encaps = top_kem_encaps
SRC_kem_encaps = $(RTL)/keccak_f1600_round.v $(RTL)/keccak_engine.v $(RTL)/engine_client.v $(RTL)/sample_ntt.v $(RTL)/sample_cbd.v $(RTL)/ntt.v $(RTL)/invntt.v $(RTL)/basemul_core.v $(RTL)/gamma_rom.v $(RTL)/matmul.v $(RTL)/dotmul.v $(RTL)/pack.v $(RTL)/compress.v $(RTL)/kem_encaps.v $(PWD)/wrappers/top_kem_encaps.v

TOP_kem_decap = top_kem_decap
SRC_kem_decap = $(RTL)/keccak_f1600_round.v $(RTL)/keccak_engine.v $(RTL)/engine_client.v $(RTL)/sample_ntt.v $(RTL)/sample_cbd.v $(RTL)/ntt.v $(RTL)/invntt.v $(RTL)/basemul_core.v $(RTL)/gamma_rom.v $(RTL)/matmul.v $(RTL)/dotmul.v $(RTL)/pack.v $(RTL)/compress.v $(RTL)/kem_decap.v $(PWD)/wrappers/top_kem_decap.v


TOP_aes = aes256_core
SRC_aes = $(RTL)/aes256_core.v

TOP_ghash = ghash
SRC_ghash = $(RTL)/ghash.v

TOP_mulpoly = top_mulpoly
SRC_mulpoly = $(RTL)/mul_poly.v $(PWD)/wrappers/top_mulpoly.v

TOP_gcm = gcm
SRC_gcm = $(RTL)/aes256_core.v $(RTL)/ghash.v $(RTL)/gcm.v

TOP_esp = esp
SRC_esp = $(RTL)/aes256_core.v $(RTL)/ghash.v $(RTL)/gcm.v $(RTL)/esp.v

TOP_encap = ip_udp_eth_tx
SRC_encap = $(RTL)/ip_udp_eth_tx.v
COMPILE_ARGS_encap = -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-WIDTHCONCAT

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