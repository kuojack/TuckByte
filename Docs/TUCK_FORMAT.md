# TuckByte Archive Format 1.0（experimental）

本文件描述目前實作所產生的 `.tuck` binary layout。所有整數皆為 unsigned
little-endian，除非欄位明確標示為 signed。字串使用嚴格 UTF-8 NFC。v1.0
檔案必須設定 `experimental` flag；格式尚未承諾長期相容。

## 整體排列

```text
fixed header (128 bytes)
wrapped DEK (unencrypted: 0 bytes; encrypted: 48 bytes)
chunk record 0..n
stored index
footer (96 bytes)
```

讀取器從尾端 96 bytes 找到 index；不得以搜尋 magic 取代邊界驗證。分卷
`.tuck.001`、`.002`… 是上述單一 logical byte stream 的連續切片，分卷本身
沒有額外標頭。

## Fixed header（128 bytes）

| Offset | Size | Field | v1 value / rule |
| ---: | ---: | --- | --- |
| 0 | 8 | magic | ASCII `TUCKBYTE` |
| 8 | 2 | major | `1` |
| 10 | 2 | minor | `0` |
| 12 | 4 | header size | `128` |
| 16 | 4 | flags | bit 0 encrypted; bit 31 experimental; others zero |
| 20 | 2 | default codec | `1` (Zstandard) |
| 22 | 2 | encryption | `0` or `1` (AES-256-GCM) |
| 24 | 2 | KDF | `0` or `1` (Argon2id v1.3) |
| 26 | 2 | minimum reader major | `1` |
| 28 | 4 | nominal chunk size | writer default `4,194,304` |
| 32 | 16 | archive ID | CSPRNG |
| 48 | 16 | KDF salt | encrypted: CSPRNG; otherwise zero |
| 64 | 4 | Argon2 memory KiB | encrypted default `65,536`; otherwise zero |
| 68 | 4 | Argon2 iterations | encrypted default `3`; otherwise zero |
| 72 | 4 | Argon2 lanes | encrypted default `4`; otherwise zero |
| 76 | 8 | data nonce prefix | CSPRNG |
| 84 | 12 | DEK-wrap nonce | encrypted: CSPRNG; otherwise zero |
| 96 | 4 | wrapped DEK length | encrypted `48`; otherwise `0` |
| 100 | 28 | reserved | all zero |

An encrypted archive immediately stores `AES-GCM(KEK, DEK)` as 32 bytes of
ciphertext followed by a 16-byte tag. The entire 128-byte header is AAD. KEK is
Argon2id(password UTF-8, salt, parameters) with a 32-byte output. The DEK is 32
random bytes; HKDF-SHA256 derives independent data and index keys using the
archive ID as salt and `TUCKBYTE-DATA-v1` / `TUCKBYTE-INDEX-v1` as info.

## Chunk record（24-byte header + stored bytes）

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 4 | ASCII `CHNK` |
| 4 | 2 | record version (`1`) |
| 6 | 1 | codec: Store `0`, Zstandard `1` |
| 7 | 1 | encrypted: `0` or `1` |
| 8 | 4 | sequence, range `1...0xFFFFFFFE` |
| 12 | 4 | original length |
| 16 | 4 | stored length, including GCM tag when encrypted |
| 20 | 4 | reserved zero |

Nonce is the 8-byte archive prefix followed by the little-endian sequence.
Chunk AAD is the immutable content AAD followed by the exact 24-byte chunk
header. Stored encrypted bytes are ciphertext followed by a 16-byte tag.

Immutable content AAD is, in order: magic (8), major (2), minor (2), flags (4),
chunk size (4), archive ID (16), nonce prefix (8), Zstd codec ID (2), AES-GCM
algorithm ID (2). Every index chunk descriptor also stores SHA-256 of the
uncompressed bytes. For unencrypted archives this is corruption detection, not
protection against a malicious editor.

## Plain index

The plain index begins with:

| Size | Field |
| ---: | --- |
| 4 | ASCII `TIDX` |
| 2 | index version (`1`) |
| 2 | reserved zero |
| 4 | entry count |

Each entry is:

| Size | Field |
| ---: | --- |
| 1 | kind: file `0`, directory `1` |
| 3 | reserved zero |
| 4 + n | UTF-8 path byte length and bytes |
| 8 | uncompressed size |
| 8 | signed Unix modification time in nanoseconds |
| 4 | POSIX permissions masked to `0777` |
| 4 | chunk count |

Each file chunk descriptor is:

| Size | Field |
| ---: | --- |
| 4 | sequence |
| 1 | codec |
| 3 | reserved zero |
| 8 | logical record offset |
| 4 | stored length |
| 4 | original length |
| 32 | SHA-256 of uncompressed chunk |

Directory paths end with `/`, have size and chunk count zero, and are explicit
entries so empty directories survive. File paths do not end with `/`.

Encrypted index nonce is `noncePrefix || 0xFFFFFFFF`. Index AAD is immutable
content AAD followed by ASCII `TUCKBYTE-INDEX-v1`. Stored index is ciphertext
followed by the 16-byte tag. An unencrypted index is stored as-is.

## Footer（96 bytes）

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 8 | ASCII `TUCKEND!` |
| 8 | 2 | major `1` |
| 10 | 2 | minor `0` |
| 12 | 4 | footer size `96` |
| 16 | 4 | flags, exactly equal to header flags |
| 20 | 4 | reserved zero |
| 24 | 8 | logical index offset |
| 32 | 8 | stored index length |
| 40 | 8 | plain index length |
| 48 | 12 | index nonce |
| 60 | 32 | SHA-256 of stored index |
| 92 | 4 | reserved zero |

## Canonical and rejection rules

- Path is relative UTF-8 NFC, uses `/`, contains no NUL, backslash, empty
  component, `.` or `..`, and is at most 16,384 bytes.
- Case-insensitive duplicate paths, a file used as a parent directory, duplicate
  sequence numbers, overlapping chunk ranges, unknown required bits/algorithms,
  non-zero reserved fields, trailing index bytes and inconsistent header/index
  data are rejected.
- Limits: 1,000,000 entries; 4,000,000 chunks; 64 MiB decoded chunk; 512 MiB
  index; 8 TiB per entry; 16 TiB total; compression ratio 1,000,000:1.
- Argon2 limits: at most 256 MiB memory, 20 iterations and 64 lanes. Parameters
  that violate Argon2's minimum memory rule are rejected before allocation.
- All offset/length arithmetic is checked before reads. The index must end
  immediately before the footer.
- Extraction refuses overwrite, rejects links and special files, creates a
  private destination, writes each file through a randomized partial file, and
  removes the destination tree on failure or cancellation.

## Versioning

A reader accepts major `1` and a minor not greater than its own. Unknown flags
or algorithm IDs fail explicitly. Breaking changes require a new major or new
algorithm ID. Until the experimental flag is retired, generated archives are
test artifacts and must not be promised as permanent archival storage.
