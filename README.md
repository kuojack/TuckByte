# TuckByte

![TuckByte icon](Resources/AppIcon.png)

TuckByte 是以 SwiftUI 開發的原生 macOS 壓縮工具。目前版本專注於實用的 ZIP 工作流程，包含拖放檔案、瀏覽壓縮檔內容、調整壓縮率、傳統 ZIP 密碼保護，以及 Finder 右鍵整合。

> **開發階段：0.3.0**
>
> 目前提供本機測試與原始碼建置版本，尚未使用 Developer ID 簽章或 Apple notarization，不建議直接當作正式公開下載版本。

## 功能

- 將多個檔案與資料夾拖入待壓縮清單
- 調整 ZIP 壓縮速度與壓縮等級 `0–9`
- 使用傳統 ZipCrypto 密碼保護
- 開啟 ZIP 並瀏覽名稱、路徑、大小、類型與修改時間
- 將 ZIP 解壓到指定資料夾
- 把既有 ZIP 再包成一層 ZIP
- Finder 右鍵「TuckByte：加入壓縮檔」
- Finder 右鍵批次「TuckByte：解壓縮至此」
- 同名解壓目的地自動使用 `名稱 2`、`名稱 3`
- 背景解壓完成通知
- Apple silicon 與 Intel Mac 雙架構建置

## 格式支援

| 格式 | 瀏覽 | 解壓 | 建立 | 加密 |
| --- | --- | --- | --- | --- |
| ZIP | 支援 | 支援 | 支援 | 傳統 ZipCrypto |
| 7z | 尚未支援 | 尚未支援 | 尚未支援 | 尚未支援 |
| RAR | 尚未支援 | 尚未支援 | 尚未支援 | 尚未支援 |
| TAR/GZ | 尚未支援 | 尚未支援 | 尚未支援 | 不適用 |

介面中的 7z、RAR 與 TAR 選項是後續壓縮引擎的產品預留項目，目前不會假裝建立成功。

## 系統需求

- macOS 11 或更新版本
- Xcode 16 或相容的完整 Xcode 安裝
- Swift 5.3 或更新版本

## 建置與測試

```sh
swift test
swift run TuckByte
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

一般檔案或資料夾會顯示「TuckByte：加入壓縮檔」。只有所有選取項目都是 `.zip` 時，才會另外顯示「TuckByte：解壓縮至此」。

## 架構

```text
TuckByte
├── TuckByte                 SwiftUI 主程式與操作流程
├── TuckByteCore             壓縮、解壓、格式與資料模型
├── TuckByteIntegration      Finder 動作 URL 編解碼
└── TuckByteFinderSync       Finder Sync Extension
```

核心透過 Foundation `Process` 呼叫 macOS 內建工具：

| 系統工具 | 用途 |
| --- | --- |
| `/usr/bin/zip` | 建立 ZIP、壓縮等級與 ZipCrypto |
| `/usr/bin/zipinfo` | 讀取 ZIP 項目大小、日期與類型 |
| `/usr/bin/tar` | 取得壓縮檔中的完整路徑 |
| `/usr/bin/ditto` | 解壓 ZIP |

專案沒有 SwiftPM 第三方套件，也沒有內嵌 7-Zip、RAR、Keka、libarchive 或 Info-ZIP 二進位。上述命令由使用者的 macOS 系統提供，詳細說明請參考 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 隱私與安全

- 壓縮與解壓都在本機執行。
- TuckByte 不包含分析、追蹤、廣告或網路上傳功能。
- Finder Extension 只傳送本機檔案路徑給主 App。
- 目前密碼功能使用 `/usr/bin/zip -P`，屬於較弱的傳統 ZipCrypto，不是 AES。
- 密碼會短暫出現在本機程序參數中；不要將此版本用於高度敏感資料。
- 請謹慎處理來源不明或不受信任的壓縮檔。

## 授權

TuckByte 自有原始碼使用 [MIT License](LICENSE) 授權。

macOS、Xcode、SwiftUI、AppKit、Finder Sync 及其他 Apple 技術仍受 Apple 各自條款約束。系統工具及其授權不因本專案的 MIT License 而改變。

## 名稱與商標

TuckByte 是獨立開發專案，與 Apple、7-Zip、RARLAB、Keka 或其他壓縮軟體專案沒有隸屬、贊助或背書關係。文中產品與格式名稱僅用於描述相容性及功能。

## Roadmap

- 以原生壓縮引擎取代 shell 工具
- 7z、TAR/GZ 與更多解壓格式
- AES 加密與安全密碼傳遞
- 壓縮進度、取消與工作佇列
- Developer ID 簽章與 notarization
- 正式版本更新機制

## 免責聲明

本專案按「現狀」提供，不附帶任何明示或默示保證。此 README 的授權說明不是法律意見；正式商業發佈前，仍應由合格專業人士確認授權、商標、出口管制及適用地區法規。
