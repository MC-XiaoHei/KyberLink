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
