# TuckByte

![TuckByte icon](Resources/AppIcon.png)

TuckByte 是以 SwiftUI 開發的原生 macOS 壓縮工具。除了 ZIP／7z 相容流程，
目前也提供 experimental `.tuck` 自有格式：原生 Zstandard 分塊壓縮、
Argon2id + AES-256-GCM、加密索引、單項隨機存取與直接串流分卷。

> **開發階段：0.8.0**
>
> 目前提供開源測試版與原始碼建置版本。下載版尚未使用 Developer ID
> 簽章或 Apple notarization，適合了解風險的技術使用者與測試者，不建議
> 當作正式生產環境版本。
>
> GitHub 上目前公開下載版仍為 `v0.3.0`；`0.8.0` 功能尚在開發分支，
> 未建立新的 Release。

## 下載測試版

請從 [GitHub Releases](https://github.com/kuojack/TuckByte/releases) 下載
`TuckByte.dmg`，並使用同一個 Release 提供的 SHA-256 檔案驗證下載內容。

由於測試版尚未經 Apple 公證，macOS 可能阻擋第一次開啟。確認下載來源及
SHA-256 後，可在 **系統設定 > 隱私權與安全性** 選擇「仍要打開」。請勿
為了安裝 TuckByte 而停用整台 Mac 的 Gatekeeper。

## 功能

- 壓縮與解壓縮使用獨立工作區，避免設定與內容列表混在同一畫面
- 上方分段控制可隨時切換「壓縮」與「解壓縮」模式
- 將多個檔案與資料夾拖入待壓縮清單
- 調整 ZIP 壓縮速度與壓縮等級 `0–9`
- ZIP 加密可選 AES-256（推薦）、ZipCrypto（相容模式）或無加密
- 可辨識加密 ZIP，輸入密碼後解壓全部、單一項目或拖到 Finder
- 開啟 `.tuck`、ZIP 或 7z，逐層瀏覽資料夾、名稱、路徑、大小、類型與修改時間
- 瀏覽、解壓與建立 `.zip.001`、`.002`、`.003` 連續分卷
- 可選擇將 TuckByte 設為 ZIP／7z 預設程式，雙擊時先瀏覽而不直接解壓
- 將壓縮檔中的單一檔案或資料夾拖到 Finder 解壓
- 內容項目右鍵可選擇「解壓此項目」
- 將 ZIP 或 7z 解壓到指定資料夾
- 把既有 ZIP 或 7z 再包成一層 ZIP
- Finder 右鍵「TuckByte：加入壓縮並開啟介面」
- Finder 右鍵「TuckByte：加入壓縮」使用平衡設定原地建立 ZIP
- Finder 右鍵批次「TuckByte：解壓縮至此」
- 同名壓縮及解壓目的地自動使用 `名稱 2`、`名稱 3`
- 背景壓縮及解壓完成通知
- Apple silicon 與 Intel Mac 雙架構建置
- 建立、瀏覽、完整／單項解壓 `.tuck` 與 `.tuck.001` 連續分卷
- `.tuck` 使用 Zstandard + Store、自動避免無效壓縮，並以 bounded 多核心 chunk pipeline 處理
- `.tuck` 密碼模式使用 Argon2id、AES-256-GCM、加密檔名索引與快速密碼重包
- `.tuck` 操作提供進度與取消，失敗／取消不保留可誤認為完成的輸出

## 格式支援

| 格式 | 瀏覽 | 解壓 | 建立 | 加密 |
| --- | --- | --- | --- | --- |
| ZIP | 支援 | 支援 | 支援 | AES-256、ZipCrypto |
| 分割 ZIP (`.zip.001`) | 支援 | 支援 | 支援 | AES-256、ZipCrypto |
| 7z | 支援 | 支援 | 不支援 | 不支援 |
| TuckByte (`.tuck`) | 支援 | 支援 | 支援 | Argon2id + AES-256-GCM |
| 分割 TuckByte (`.tuck.001`) | 支援 | 支援 | 支援 | Argon2id + AES-256-GCM |

建立壓縮檔的格式選單可選 ZIP 或 TuckByte。7z 使用 macOS 內建
`bsdtar/libarchive` 讀取；目前不支援加密 7z、建立 7z 或分割 7z。

`.tuck` v1 目前會設定 experimental flag，適合互通、安全與效能測試，尚未
承諾永久封存相容性。精確格式見 [Docs/TUCK_FORMAT.md](Docs/TUCK_FORMAT.md)，
安全邊界見 [Docs/TUCK_THREAT_MODEL.md](Docs/TUCK_THREAT_MODEL.md)。

AES-256 使用 WinZip AES 規格，安全性高於 ZipCrypto。Windows 建議使用
7-Zip 等支援 AES ZIP 的工具；Windows 檔案總管與 macOS 封存工具程式不保證
能解開 AES ZIP。ZipCrypto 相容性較廣，但不適合保護敏感資料。

在「壓縮」模式拖入既有壓縮檔，會將它當成一般來源，再依目前選擇封裝成
ZIP 或 `.tuck`；在「解壓縮」模式拖入 `.tuck`、ZIP 或 7z，則會開啟內容瀏覽器。

## 系統需求

- macOS 11 或更新版本
- Xcode 16 或相容的完整 Xcode 安裝
- Swift 5.3 或更新版本

## 建置與測試

```sh
swift test
swift run TuckByte
swift run tuck-inspect Archive.tuck
swift run tuck-benchmark 64
```

使用 Xcode 建置包含 Finder Extension 的 App：

```sh
xcodebuild \
  -project TuckByte.xcodeproj \
  -scheme TuckByte \
  -configuration Release \
  build
```

## 建立 App 與 DMG

```sh
Scripts/package_app.sh
Scripts/package_dmg.sh
```

輸出位於：

```text
dist/TuckByte.app
dist/TuckByte.dmg
```

打包腳本使用 ad-hoc codesign，適合本機測試。若要向一般使用者公開散佈，應改用 Developer ID Application 簽章並完成 Apple notarization。

## Finder 右鍵整合

1. 將 `TuckByte.app` 放進 `/Applications`。
2. 啟動 TuckByte。
3. 開啟 **TuckByte > 設定**。
4. 按下「開啟設定」，在 macOS Extension 管理介面啟用 **TuckByte Finder**。
5. 視需要允許完成通知。

一般檔案或資料夾會顯示：

- 「TuckByte：加入壓縮並開啟介面」：載入選取項目，讓使用者調整 ZIP 壓縮率、分卷與密碼。
- 「TuckByte：加入壓縮」：不開介面，直接使用 ZIP 等級 6、無加密在原位置壓縮。
- 「TuckByte：解壓縮至此」：所有選取項目都是 `.zip`、`.7z` 或
  `.zip.001`／`.tuck.001` 系列分卷時顯示。同時選取同組多個分卷只會解壓一次。

直接壓縮單一檔案或資料夾時使用項目名稱，多選時使用所在資料夾名稱。既有 ZIP
會建立為 `名稱-外層.zip`；目的地已存在時依序使用 `名稱 2.zip`、`名稱 3.zip`。
若多選項目來自不同資料夾，TuckByte 會改為開啟介面，避免猜測輸出位置。

## 分割 ZIP 與 TuckByte

在壓縮設定啟用「分割壓縮檔」，再選擇 `10 MB`、`100 MB`、`1 GB`、
`4 GB` 或自訂 MB 大小。ZIP 會產生 `名稱.zip.001`，TuckByte 會產生
`名稱.tuck.001`，後續皆為 `.002`、`.003` 等連續二進位分卷。ZIP 可在支援
這種切割方式的工具中重組；`.tuck` 需由相容的 TuckByte reader 讀取。

瀏覽或解壓時，所有分卷必須放在同一資料夾並保留連續編號。
在 Finder 右鍵可選取任一卷，TuckByte 會自動從 `.001` 重組；使用 App
內的「開啟」面板時請選 `.001`。若缺少中間分卷會指出缺少的檔名。
右鍵「加入壓縮」的背景快速模式仍建立普通 ZIP；要建立分卷請使用
「加入壓縮並開啟介面」。

## ZIP／7z 雙擊瀏覽

將 App 放進 `/Applications` 後，開啟 **TuckByte > 設定**，啟用
「雙擊 ZIP／7z 時先用 TuckByte 瀏覽」。macOS 可能會要求確認變更預設程式；
完成後，在 Finder 雙擊 `.zip` 或 `.7z` 會開啟 TuckByte 的內容列表。

關閉此設定時，TuckByte 會分別恢復啟用前的 ZIP 與 7z 處理程式；若原處理程式
無法取得，則恢復 macOS 的「封存工具程式」。TuckByte 只以 `Viewer` 身分宣告
支援，單純安裝 App 不會自動搶走預設程式。

瀏覽 ZIP 或 7z 時，雙擊資料夾可逐層進入，並可用上一層按鈕或路徑導覽返回。
即使壓縮檔沒有保存獨立的資料夾條目，TuckByte 也會依檔案路徑重建目錄層級。

內容列表中的單一檔案或資料夾可拖到 Finder，也可在該項目上按右鍵並選擇
「解壓此項目...」。目的地已有同名項目時不會覆蓋。

## 架構

```text
TuckByte
├── TuckByte                 SwiftUI 主程式與操作流程
├── TuckByteCore             壓縮、解壓、格式與資料模型
├── TuckByteIntegration      Finder 動作 URL 編解碼
└── TuckByteFinderSync       Finder Sync Extension
```

核心使用內嵌的 Zstandard 1.5.7、Argon2 reference 20190702、minizip-ng，
並在舊格式流程以 Foundation `Process` 呼叫 macOS 內建工具：

| 系統工具 | 用途 |
| --- | --- |
| minizip-ng 4.0.10 | 建立 AES-256／ZipCrypto ZIP、辨識加密方式與密碼解壓 |
| Zstandard 1.5.7 | `.tuck` 原生分塊壓縮與解壓 |
| Argon2 reference 20190702 | `.tuck` Argon2id v1.3 密碼金鑰導出 |
| `/usr/bin/zip` | 建立無加密 ZIP與壓縮等級 |
| `/usr/bin/zipinfo` | 讀取 ZIP 項目大小、日期與類型 |
| `/usr/bin/tar` | 取得完整路徑，並瀏覽及解壓 7z |
| `/usr/bin/ditto` | 解壓 ZIP |

`.zip.001` 分卷的切割與重組由 TuckByte 以 Foundation 串流讀寫實作。
`.tuck.001` 直接作為單一 logical stream 讀寫，不先組出完整暫存 archive。

專案沒有外部 SwiftPM 套件，也沒有內嵌 7-Zip、RAR、Keka、libarchive 或
Info-ZIP 二進位。Zstandard（BSD-3-Clause）、Argon2（vendored files 選用
CC0）與 minizip-ng（zlib License）原始碼由專案直接編譯；上述命令由使用者
的 macOS 系統提供。詳細說明請參考
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
版本來源與授權選擇的逐項查核紀錄見
[Docs/THIRD_PARTY_AUDIT.md](Docs/THIRD_PARTY_AUDIT.md)。

## 隱私與安全

- 壓縮與解壓都在本機執行。
- 分割 ZIP 瀏覽與解壓會先在系統暫存目錄重組完整 ZIP，需要足夠的可用磁碟空間，完成後會刪除。
- TuckByte 不包含分析、追蹤、廣告或網路上傳功能。
- Finder Extension 只傳送本機檔案路徑給主 App。
- AES-256 與 ZipCrypto 密碼由 App 直接傳給內嵌引擎，不會放在 shell 程序參數。
- TuckByte 不儲存密碼；關閉或重新開啟壓縮檔後需要再次輸入。
- 加密 7z 目前無法輸入密碼，因此不在支援範圍內。
- 加密 `.tuck` 不會把密碼、KEK 或 DEK 放入 shell 參數或日誌；檔名索引也會加密。
- 無加密 `.tuck` 的 SHA-256 用於損壞偵測，不提供對惡意修改者的真實性保證。
- 請謹慎處理來源不明或不受信任的壓縮檔。

## 授權

TuckByte 自有原始碼使用 [MIT License](LICENSE) 授權。

macOS、Xcode、SwiftUI、AppKit、Finder Sync 及其他 Apple 技術仍受 Apple 各自條款約束。系統工具及其授權不因本專案的 MIT License 而改變。

## 名稱與商標

TuckByte 是獨立開發專案，與 Apple、7-Zip、RARLAB、Keka 或其他壓縮軟體專案沒有隸屬、贊助或背書關係。文中產品與格式名稱僅用於描述相容性及功能。

## Roadmap

- 將既有 ZIP／7z shell 流程逐步換成原生引擎
- TAR/GZ 與更多解壓格式
- 加密 7z 的密碼輸入與解壓
- 工作佇列與跨操作排程
- `.tuck` sustained coverage-guided fuzzing、獨立安全審查與穩定格式凍結
- Developer ID 簽章與 notarization
- 正式版本更新機制

## 免責聲明

本專案按「現狀」提供，不附帶任何明示或默示保證。此 README 的授權說明不是法律意見；正式商業發佈前，仍應由合格專業人士確認授權、商標、出口管制及適用地區法規。
