# vector-schema

向量由 software/crates/kyberlink-crypto/src/bin/vector_gen.rs 生成，输出到 vectors/generated/。派生方式为 SHAKE256(seed, label, index)。

## kem.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index | u64 | 序号 |
| seed  | hex | 64B，d 在前 z 在后 |
| pk    | hex | 1184B 封装密钥 |
| ct    | hex | 1088B 密文 |
| ss    | hex | 32B 共享密钥 |

## sign.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index | u64 | 序号 |
| seed  | hex | 32B 签名种子 |
| pk    | hex | 1952B 验证密钥 |
| msg   | hex | 64B 消息 |
| sig   | hex | 3309B 签名 |

## cipher.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index | u64 | 序号 |
| key   | hex | 32B AES-256 密钥 |
| nonce | hex | 12B |
| aad   | hex | 16B |
| plaintext | hex | 128B 明文 |
| ciphertext_tag | hex | 144B，密文与 16B ICV 拼接 |

## sample_ntt.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index  | u64 | 序号 |
| seed   | hex | 34B，前 32B 为 rho，后 2B 为 (i, j) |
| coeffs | int[] | 256 个，SampleNTT 拒绝采样结果，均小于 3329 |

## sample_cbd.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index  | u64 | 序号 |
| seed   | hex | 33B，前 32B 为 rho，末 1B 为 i |
| coeffs | int[] | 256 个，CBD2 采样结果，范围 −2..2 |

## sample_cbd3.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index  | u64 | 序号 |
| seed   | hex | 33B，前 32B 为 rho，末 1B 为 i |
| coeffs | int[] | 256 个，CBD3 采样结果（192B SHAKE256 展开，每 3B 小端拼 24 位、4 个 6 位段、popcount 低 3 位减高 3 位），范围 −3..3 |

## ntt.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index      | u64 | 序号 |
| coeffs_in  | int[] | 256 个标准序系数，均小于 3329 |
| coeffs_out | int[] | 256 个 NTT 结果系数（bitreversed 序），均小于 3329 |

## invntt.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index      | u64 | 序号 |
| coeffs_in  | int[] | 256 个 NTT 域系数（bitreversed 序），均小于 3329 |
| coeffs_out | int[] | 256 个逆 NTT 结果系数（标准序），均小于 3329 |

## basemul.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index      | u64 | 序号 |
| coeffs_a   | int[] | 256 个系数（NTT 域，bitreversed 序），均小于 3329 |
| coeffs_b   | int[] | 256 个系数（NTT 域，bitreversed 序），均小于 3329 |
| coeffs_out | int[] | 256 个乘积系数，第 2k/2k+1 个为第 k 对系数按 γ_k 的 BaseCaseMultiply 结果 |

## matmul.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index     | u64 | 序号 |
| transpose | bool | 是否转置（true 时 C[i]=Σ_j A[j,i]∘B[j]） |
| coeffs_a  | int[] | 2304 个系数（9 多项式×256，NTT 域 bitreversed 序），均小于 3329 |
| coeffs_b  | int[] | 768 个系数（3 多项式×256），均小于 3329 |
| coeffs_c  | int[] | 768 个乘积系数（3 多项式×256），第 i 个多项式为 C[i]=Σ_j A[i,j]∘B[j]（MultiplyNTTs 逐对 BaseCaseMultiply 累加） |

## aes.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index      | u64 | 序号 |
| key        | hex | 32B AES-256 密钥 |
| block      | hex | 16B 明文块 |
| ciphertext | hex | 16B 加密结果 |

## ghash.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index  | u64 | 序号 |
| h      | hex | 16B 子密钥 H |
| blocks | hex[] | 若干 16B 输入块序列 |
| tag    | hex | 16B GHASH 累乘结果 |

## esp.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index     | u64 | 序号 |
| key       | hex | 32B AES-256 密钥 |
| spi       | hex | 4B SPI 字段 |
| seq       | hex | 4B 序号字段 |
| iv        | hex | 12B 初始向量 |
| plaintext_len | u64 | 明文字节数（0..255，覆盖 0/1/15/16/17/127/128/255 边界） |
| plaintext | hex | 动态长度明文（IP 包） |
| frame     | hex | 38+len 字节 ESP 帧 = SPI(4)\|Seq(4)\|IV(12)\|CT(len)\|PadLen(1)\|NextHeader(1)\|ICV(16)，AAD=SPI\|Seq |

## sha3_256.json / sha3_512.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index   | u64  | 序号 |
| msg_len | u64  | 消息字节数（sha3_256 覆盖 0/1/32/33/64/135/136/137/255/512/1184；sha3_512 覆盖 0/1/32/33/63/64/71/72/73/136，含满块/边界） |
| msg     | hex  | 消息（右补零，长度=msg_len） |
| hash    | hex  | 32B(SHA3-256)/64B(SHA3-512) 摘要 |

## pack.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index   | u64  | 序号 |
| mode    | str  | encode / decode |
| d       | u64  | 1/4/10/12 |
| coeffs  | int[] | 256 个 d 位系数（decode 时是输出，d=12 时 <3329） |
| bytes   | hex  | 32d 字节打包结果（encode 输出 / decode 输入） |

## compress.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index   | u64  | 序号 |
| mode    | str  | compress / decompress |
| d       | u64  | 1/4/10 |
| coeffs_in  | int[] | 256 个输入系数（compress：<3329；decompress：<2^d） |
| coeffs_out | int[] | 256 个输出系数（compress：<2^d；decompress：<3329） |

## kem_keygen.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index | u64 | 序号 |
| d | hex | 32B 随机种子（K-PKE.KeyGen 输入） |
| z | hex | 32B 随机种子（dk 展开用） |
| ek | hex | 1184B 封装密钥 = encode12(t̂)×3 \|\| rho |
| dk | hex | 2400B 解封装密钥 = dkPKE \|\| ekPKE \|\| H(ekPKE) \|\| z |

## kem_encaps.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index | u64 | 序号 |
| ek | hex | 1184B 封装密钥 |
| m | hex | 32B 随机消息 |
| c | hex | 1088B 密文 = encode10(compress10(u))×3 \|\| encode4(compress4(v)) |
| K | hex | 32B 会话密钥（G(m\|\|H(ek)) 前 32B） |

## kem_decap.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index | u64 | 序号 |
| dk | hex | 2400B 解封装密钥 |
| c | hex | 1088B 密文 |
| K | hex | 32B 会话密钥（与 kem_encaps 同 index 一致） |

## ntt_dsa.json / invntt_dsa.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index | u64 | 序号 |
| coeffs_in | int[] | 256 个 <8380417（标准序） |
| coeffs_out | int[] | 256 个，NTT（bitreversed 序）/ INTT（标准序）结果 |

## rej_ntt.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index | u64 | 序号 |
| seed | hex | 34B = rho(32)\|\|s\|r，SHAKE128 每 3 字节 1 个 23 位系数（b2'=b2−128，z<q 接受） |
| coeffs | int[] | 256 个 <8380417 |

## rej_bounded.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index | u64 | 序号 |
| seed | hex | 66B = rho'(64)\|\|r_le16，SHAKE256 每字节 2 半字节（<9 接受，η=4） |
| coeffs | int[] | 256 个 ∈ {0..4, Q−4..Q−1} |

## expand_mask.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index | u64 | 序号 |
| seed | hex | 66B = rho''(64)\|\|mu_le16，SHAKE256 640B 每系数 20 位 LSB-first |
| coeffs | int[] | 256 个 y=γ1−w'（模 q） |

## sample_in_ball.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index | u64 | 序号 |
| seed | hex | 48B c~（SHAKE256 先 8B 符号位，后 τ 轮拒绝采样） |
| coeffs | int[] | 256 个 ∈ {0,1,Q−1}，汉明重量恰为 τ=49 |

## mldsa_keygen_mid.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index | u64 | 序号 |
| seed | hex | 32B（H(seed‖[K]‖[L])→rho‖rho2‖kk） |
| rho/rho2/kk | hex | 32B/64B/32B（A 矩阵/expand_s 种子） |
| a_hat | int[] | 30 多项式×256 NTT 域（K×L 矩阵，ρ‖j‖i 逐行） |
| s1/s2 | int[] | 5/6 多项式×256（CBD η=4） |
| s1_hat | int[] | 5×256 NTT 域 |
| t_std | int[] | 6×256（INTT(A·ŝ1)+s2，标准域） |
| t1/t0 | int[] | 6×256（power2round(t)） |
| tr | hex | 64B H(vk) |
| vk | hex | 1952B = rho‖encode_t1(t1) |
| sk | hex | 4032B = rho‖kk‖tr‖s1‖s2‖t0 |

## mldsa_sign_mid.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index | u64 | 序号 |
| sk | hex | 4032B |
| mu_b | hex | 64B μ |
| rho/kk | hex | 32B 各 |
| s1/s2/t0 | int[] | 解码自 sk |
| s1_hat/s2_hat/t0_hat | int[] | NTT 域 |
| a_hat | int[] | 30×256 |
| rhopp | hex | 64B（H(kk‖rnd‖μ)，rnd=0） |
| kappa | u64 | 成功轮起始 |
| y/y_hat | int[] | 5×256（ExpandMask 输出/NTT） |
| w/w1 | int[] | 6×256（INTT(A·ŷ)、HighBits） |
| w1_tilde | hex | 编码 w1 |
| c_tilde | hex | 48B（H(μ‖w1_tilde)） |
| c/c_hat | int[] | 256（SampleInBall/NTT） |
| cs1/cs2 | int[] | 5/6×256 标准域（INTT(c·ŝ)） |
| zz | int[] | 5×256（z=y+cs1） |
| r0/w_minus_cs2 | int[] | 6×256 |
| ct0 | int[] | 6×256（INTT(c·t̂0)） |
| hh | int[] | 6×256（0/1 hint 布尔矩阵） |
| sig | hex | 3309B |

## mldsa_verify_mid.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index | u64 | 序号 |
| vk | hex | 1952B |
| mu_b/sig | hex | 64B/3309B |
| rho | hex | 32B |
| t1 | int[] | 6×256（解码自 vk） |
| a_hat | int[] | 30×256 |
| t1_2d_hat | int[] | 6×256（NTT(2^13·t1)） |
| c_tilde | hex | 48B（sig 前段） |
| c/c_hat | int[] | 256（SampleInBall/NTT） |
| z_hat | int[] | 5×256（NTT(z)） |
| w_hat | int[] | 6×256（A·z_hat − c⊙t1_2d NTT 域） |
| w_approx | int[] | 6×256（INTT(w_hat)） |
| w1 | int[] | 6×256（UseHint） |
| ctil | hex | 48B（H(μ‖w1_tilde)） |
| ok | bool | ctil==c_tilde |

## pack_dsa.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index | u64 | 序号 |
| mode | str | encode / decode |
| d | u64 | 13 / 20 |
| coeffs | int[] | 256 个 d 位系数（decode 时是输出，值 <2^d） |
| bytes | hex | 32d 字节打包结果（encode 输出 / decode 输入） |

## kem_keygen_mid.json

中间量向量，供硬件核逐阶段比对。同一 index 下 d/z/m 与 kem_keygen/kem_encaps/kem_decap 一致。

| 字段 | 类型 | 说明 |
|------|------|------|
| index | u64 | 序号 |
| d, z | hex | 32B 种子（与 kem_keygen 一致） |
| rho | hex | 32B，G(d\|\|0x03) 前 32B |
| sigma | hex | 32B，G(d\|\|0x03) 后 32B |
| a | int[] | 2304 = 9 多项式 × 256 系数（Â，NTT 域 bitreversed） |
| s, e | int[] | 768 = 3 × 256 系数（多项式域，±2..0 经 mod q） |
| sh, eh | int[] | 768，NTT(s)/NTT(e) |
| th | int[] | 768，Â∘ŝ + ê（NTT 域） |
| ek | hex | 1184B 封装密钥 |
| dk | hex | 2400B 解封装密钥 |

## kem_encaps_mid.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index | u64 | 序号 |
| ek | hex | 1184B |
| m | hex | 32B 消息（与 kem_encaps 一致） |
| hek | hex | 32B，H(ek) |
| K, r | hex | 32B，G(m\|\|hek) 前/后 32B |
| th | int[] | 768，ek 解包（decode12） |
| rho | hex | 32B，ek 尾部 |
| a | int[] | 2304，Â 再生 |
| y, e1, e2 | int[] | 768/768/256 系数（e2 单多项式） |
| yh | int[] | 768，NTT(y) |
| u | int[] | 768，NTT⁻¹(Âᵀ∘ŷ)+e1（多项式域） |
| mu | int[] | 256，Decompress1(Decode1(m)) |
| v | int[] | 256，NTT⁻¹(t̂ᵀ∘ŷ)+e2+μ |
| c | hex | 1088B 密文 |

## kem_decap_mid.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index | u64 | 序号 |
| dk, c | hex | 2400B/1088B |
| m_prime | hex | 32B，K-PKE.Decrypt 结果 |
| u | int[] | 768，Decompress10(Decode10(c1)) |
| v | int[] | 256，Decompress4(Decode4(c2)) |
| sh | int[] | 768，dk 前 1152B 解包（decode12） |
| uh | int[] | 768，NTT(u) |
| w | int[] | 256，v' − NTT⁻¹(ŝᵀ∘NTT(u')) |
| Kp, rp | hex | 32B，G(m'\|\|h_ek) 前/后 32B |
| kbar | hex | 32B，J(z\|\|c) |
| cp | hex | 1088B，重加密密文 |
| K | hex | 32B，cp==c ? Kp : kbar |

## ntt_dsa.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index | u64 | 序号 |
| coeffs_in | int[] | 256 个系数 <8380417（标准序输入，shake 派生 3B 小端 mod q） |
| coeffs_out | int[] | 256 个 NTT 结果（ML-DSA 域，ZETA=1753、Barrett） |

## invntt_dsa.json

| 字段 | 类型 | 说明 |
|------|------|------|
| index | u64 | 序号 |
| coeffs_in | int[] | 256 个 NTT 域系数 |
| coeffs_out | int[] | 256 个逆 NTT 结果（末乘 256⁻¹=8347681） |
