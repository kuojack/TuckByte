# TuckByte Archive Format 開發計畫

> 狀態：experimental v1.0 已實作；安全審查與穩定格式凍結仍是公開測試 gate

## 1. 命名與識別

- 格式名稱：**TuckByte Archive Format**
- 顯示名稱：**TuckByte 壓縮檔**
- 主副檔名：**`.tuck`**
- 分割壓縮檔：**`.tuck.001`、`.tuck.002`…**
- 內部簡稱：`TBAF`
- 檔案 magic bytes：ASCII `TUCKBYTE`（8 bytes）
- macOS UTI：`com.tuckbyte.archive`
- 開發期 MIME type：`application/x-tuckbyte-archive`
- 若未來完成 IANA vendor-tree 註冊：`application/vnd.tuckbyte.archive`

### 命名理由

`.tuck` 可直接連結 TuckByte 品牌與「收納」的語意，也比三字元副檔名更容易避免衝突。
`TBA`、`TBZ`、`TBX` 不採用：`TBZ` 已常用於 tar+bzip2，`TBX` 已用於
ArcGIS Toolbox 與 TermBase eXchange；僅依賴副檔名也不夠安全，讀取時必須同時
驗證 magic bytes 與格式版本。

## 2. 核心目標

1. **快速**：支援串流、多核心、分塊與單檔隨機讀取。
2. **高壓縮率**：預設使用 Zstandard，並對已壓縮資料自動改用 Store。
3. **安全**：密碼使用 Argon2id 導出金鑰，資料使用 AES-256-GCM
   authenticated encryption，不自行發明加密演算法。
4. **可恢復**：每個 chunk 獨立驗證，單一 chunk 損壞時可準確回報。
5. **可演進**：格式有 major/minor 版本、feature flags 與可略過的選用記錄。
6. **跨平台**：檔案格式不依賴 macOS ABI，所有整數寬度、字元編碼與
   endianness 都必須在規格中固定。

## 3. 不做的事

- 不自行發明新的壓縮數學演算法。第一版的創新應放在 container、分塊、
  並行、索引與安全模型。
- 不使用 ZipCrypto、自製 cipher、無認證的 AES-CBC，也不允許重複 nonce。
- v1 不做跨壓縮檔去重、網路同步或邊壓縮邊上傳協定。
- v1 不承諾轉換或完整保留所有 macOS extended attributes、ACL 與 resource forks；
  這些應以明確 feature 加入，不可暗中丟失。

## 4. 建議的 v1 檔案結構

```text
+-------------------------------+
| Fixed Header                  | magic, version, flags, archive UUID
+-------------------------------+
| Key Slots / KDF Parameters    | salt, Argon2id params, wrapped data key
+-------------------------------+
| Entry + Chunk Records         | compressed, then optionally encrypted
+-------------------------------+
| Encrypted Archive Index       | paths, metadata, chunk locations
+-------------------------------+
| Footer                        | index offset/length, required features
+-------------------------------+
```

### Fixed Header

- 固定 little-endian。
- magic `TUCKBYTE`。
- `majorVersion`、`minorVersion`與 `minimumReaderVersion`。
- 128-bit 隨機 archive UUID。
- required/optional feature bitsets。
- codec、KDF 與 encryption algorithm ID；讀取器遇到不支援的
  required feature 必須明確失敗，不可猜測解碼。

### Entries 與 Chunks

- 路徑一律使用 UTF-8 NFC、`/` 分隔與相對路徑。
- 拒絕絕對路徑、空字節、`.`、`..` 與越界解壓。
- 每個檔案分成獨立 chunks，建議預設 4 MiB；chunk 大小可隨 profile
  改變，但受解碼器上限約束。
- 每個 chunk 記錄原始長度、壓縮後長度、codec ID、chunk sequence 與
  authentication tag/checksum。
- 同一檔案可混用 Zstd 與 Store，對 JPEG、MP4、ZIP 等資料先試壓縮，
  無實質收益就改用 Store。
- index 放在尾端，使建立檔案可串流寫入；加密模式預設加密 index，
  不洩漏檔名與目錄結構。

## 5. 壓縮設計

v1 只把 **Zstandard** 列為必備壓縮 codec，外加 Store。單一成熟 codec
可降低 attack surface 與測試矩陣，Zstd 本身已提供從高速到高壓縮率的等級。

| TuckByte profile | 預設 Zstd | 目標 |
| --- | ---: | --- |
| Fast | 1 | 即時壓縮、大檔案與 Finder 快速動作 |
| Balanced | 6 | 預設；壓縮率與 CPU 時間的平衡 |
| Maximum | 19 | 封存用；明確警告 CPU 與記憶體成本 |

實際等級只是初始值，必須用 TuckByte benchmark corpus 測試後凍結。
壓縮與解壓應支援多核心 chunk pipeline，但輸出順序必須 deterministic。

## 6. 加密與金鑰設計

### 正確的處理順序

```text
input -> compress -> authenticated encrypt -> write
read  -> authenticate/decrypt -> decompress -> output
```

### 金鑰階層

1. 每個 archive 用 CSPRNG 產生獨立 256-bit data encryption key（DEK）。
2. 使用者密碼經 Argon2id 導出 key encryption key（KEK）。
3. KEK 只用於加密／包裝 DEK；資料 chunks 都由 DEK 加密。
4. 修改密碼時只需重包 DEK，不需重新加密整個壓縮檔。
5. 格式允許多個 key slot，v1 UI 只開放一個密碼 slot，保留未來
   公鑰受者或 macOS Keychain slot。

### 預設參數

- KDF：Argon2id v1.3。
- Salt：每個 key slot 獨立 128-bit 以上隨機值。
- 開發期預設：64 MiB memory、3 iterations、4 lanes；參數必須寫入檔案。
- 發布前在最低支援 Mac 上校準，Balanced 解鎖目標約 250–500 ms，不可為
  追求即時開啟而降到不安全參數。
- AEAD：AES-256-GCM，128-bit authentication tag。
- Nonce：每個 DEK 下必須唯一；建議用隨機 archive nonce prefix +
  單調 chunk counter 組成 96-bit nonce，並為 key slot、index 與 data 使用獨立
  domain-separated subkeys。
- Header 中所有影響解碼的未加密欄位都納入 AEAD associated data。
- 密碼、DEK、KEK 與解密後資料不寫日誌、不放進 shell arguments，並在
  生命週期結束時儘可能清除記憶體。

AES-GCM 不允許 nonce reuse。格式規格與程式測試都必須把 nonce 唯一性當成
核心 invariant，而不是實作細節。

## 7. 完整性與簽章

- 加密檔：以每 chunk 的 GCM tag 驗證密文、metadata 與關鍵 header 欄位。
- 無加密檔：v1 使用每 chunk checksum 偵測傳輸或磁碟損壞；必須在 UI
  中明說 checksum 不能防止惡意篡改。
- 整個 archive 的 manifest 可於後續版本加入 Ed25519 簽章，用來證明發布者；
  簽章不與密碼加密混為同一功能。

## 8. 解壓安全基線

解壓器預設不信任任何輸入：

- 先驗證 fixed header、版本、欄位長度、index 邊界與整數溢位。
- 永遠不寫出使用者選擇目錄之外，並防止 symlink/hard-link race。
- 在建立檔案前顯示項目數、壓縮後大小、宣告解壓大小與可用空間。
- 對單項大小、總大小、項目數、路徑長度、chunk 大小、壓縮比與 KDF
  資源需求設定上限。
- 遇到驗證失敗時不保留半解密輸出，不以未驗證資料覆寫現有檔案。
- 不自動還原 setuid/setgid bits、device nodes 或其他高風險檔案類型。
- parser 必須可被 fuzz，核心格式不得依賴 shell 命令。

## 9. TuckByte 整合方式

目前 `ShellArchiveService` 同時處理 ZIP、7z 與 minizip。新格式不應繼續塞進
同一個 class，應拆成：

```text
ArchiveService (routing/facade)
├── TuckArchiveEngine      .tuck native create/read/extract
├── ZipArchiveEngine       existing ZIP/minizip behavior
└── SevenZipArchiveEngine  existing system tar behavior
```

新增的核心類型建議：

- `TuckArchiveHeader`
- `TuckArchiveEntryRecord`
- `TuckArchiveChunkRecord`
- `TuckArchiveIndex`
- `TuckArchiveWriter`
- `TuckArchiveReader`
- `TuckArchiveCrypto`
- `TuckArchiveLimits`

`ArchiveOutputFormat` 新增 `.tuck`，`ArchiveFormat` 新增 `.tuck` 與 `.splitTuck`。
舊有 ZIP、7z 與分割 ZIP 行為必須保持相容。

## 10. 開發里程碑

### Phase 0：格式規格與原型

- 凍結命名、magic、endianness、版本規則與欄位上限。
- 建立格式規格、威脅模型、測試向量與 benchmark corpus。
- 選定並固定 zstd 與 Argon2 實作版本，完成 license 審查。
- 先寫 parser 與失敗測試，再開放 UI。

**離開條件**：格式文件可以獨立解釋每個位元組與容錯規則，且至少有
一個獨立的 golden file 解碼器測試。

### Phase 1：無加密 MVP

- 串流建立與解壓 `.tuck`。
- Zstd + Store、單檔抽取、目錄瀏覽、Unicode 路徑與時間資訊。
- 中斷寫入時不留下被當成完整檔的輸出，使用暫存檔 + atomic rename。

**離開條件**：快速、平衡、最大三 profile 完成往返與損壞偵測；
現有 ZIP/7z 測試全數通過。

### Phase 2：密碼加密

- Argon2id、DEK/KEK/key-slot 結構。
- AES-256-GCM chunk encryption 與加密 index。
- 密碼變更（重包 DEK）、錯誤密碼、tamper 與 nonce-uniqueness 測試。

**離開條件**：任一密文、tag、nonce、index 或關鍵 header bit 被改動都必須
解壓失敗，且不留下部分明文。

### Phase 3：效能與分割檔

- 多核心 chunk pipeline、有上限的記憶體佇列、取消與進度。
- `.tuck.001` 分割與串流重組，不先複製出完整暫存 archive。
- 針對 Apple silicon 與 Intel Mac 做 profile 校準。

**離開條件**：持續記憶體不隨 archive 大小線性上升；分割檔缺卷、錯序與
損壞有可診斷錯誤。

### Phase 4：硬化與公開測試

- Coverage-guided fuzzing parser、index、chunk lengths 與 metadata。
- 解壓炸彈、路徑越界、symlink race、整數溢位與資源耗盡測試。
- 第三方密碼設計與 parser 審查。
- 公開 format specification、reference vectors 與壓縮檔檢查工具。

**離開條件**：fuzzer 在設定時間內無 crash/hang，所有安全 regression 測試通過，
且格式規格與實作通過獨立交叉檢查。

## 11. Benchmark 與驗收方法

### Corpus

- 程式碼與文字。
- 大量小檔。
- 應用程式與 binary。
- 資料庫、JSON/CSV 與 log。
- 已壓縮的 JPEG/PNG/MP4/PDF/ZIP。
- 1–100 GB 大檔案與混合資料夾。

### 指標

- 壓縮後大小與 ratio。
- 壓縮、解壓 MB/s。
- 峰值記憶體、CPU time 與 wall-clock time。
- 打開 index 的延遲與抽取單檔的延遲。
- 加密附加成本與密碼解鎖時間。

### Baselines

- ZIP Deflate level 1/6/9。
- Zstd 原生單檔壓縮。
- 7z LZMA2 預設與最大設定。
- Store（輸入大小與 I/O 基線）。

不使用「所有資料都最快又最小」作為不可驗證的宣傳。驗收應依 profile 分開：
Fast 優先 throughput，Balanced 優先綜合效率，Maximum 優先檔案大小，且安全基線
不因 profile 降級。

## 12. 版本與發布原則

- 格式在 1.0 前生成的檔案一律標示 experimental，不保證長期相容。
- 1.0 後同 major 版本的 reader 必須能讀早期 minor 版本。
- 需要破壞解碼相容性時提升 major version，不重用舊 algorithm ID。
- 保留一套永不刪除的 golden archives，每次 CI 都用新 reader 解碼。
- 完成規格與至少一個獨立實作後，再考慮申請 IANA media type。

## 13. 實作狀態（0.8.0）

已完成：`.tuck`／分卷命名、精確 layout 與 parser limits、Zstd 1.5.7、
Argon2 reference 20190702、Store fallback、串流 writer／reader、AES-GCM
chunk 與加密 index、DEK 重包、多核心 bounded pipeline、直接分卷 I/O、進度／
取消、golden fixture、檢查工具、mutation harness、安全 regression tests、威脅
模型、benchmark harness 與 third-party notices。

仍屬發布 gate，而非已宣稱完成的內部實作：在 Apple silicon 與最低支援 Intel
Mac 上校準、長時間 coverage-guided fuzz campaign、第三方密碼／parser 獨立審查，
以及依結果移除 experimental flag。完成這些外部驗證前不可宣稱穩定 1.0。
