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
