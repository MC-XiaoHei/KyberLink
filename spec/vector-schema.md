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
