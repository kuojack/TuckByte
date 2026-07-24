# TuckByte 0.3.0 開源測試版

這是 TuckByte 第一個公開測試版本，提供 macOS ZIP 壓縮、瀏覽、解壓縮及
Finder 右鍵整合。

## 重要安全提醒

**此版本使用 ad-hoc 簽章，尚未使用 Developer ID，也未經 Apple
notarization。** macOS 可能阻擋第一次開啟。這個版本適合了解風險的技術
使用者與測試者，不建議部署在正式生產環境。

請只從本 repository 的 Releases 下載，並在安裝前驗證 SHA-256：

```sh
shasum -a 256 -c TuckByte.dmg.sha256
```

不要為了安裝 TuckByte 而停用整台 Mac 的 Gatekeeper。確認檔案來源及雜湊
後，可在 **系統設定 > 隱私權與安全性** 選擇「仍要打開」。

## 本版功能

- 拖放多個檔案或資料夾建立 ZIP
- 調整壓縮速度及壓縮等級
- 傳統 ZipCrypto 密碼保護
- 瀏覽 ZIP 內容、大小、類型與修改時間
- 解壓 ZIP 到指定位置
- 將現有 ZIP 再包成一層 ZIP
- Finder 右鍵加入壓縮清單或解壓縮至此
- Apple silicon 與 Intel Mac 通用版本

## 已知限制

- 目前只完整支援 ZIP；7z、RAR、TAR/GZ 尚未實作
- ZIP 密碼保護是傳統 ZipCrypto，不是 AES
- 密碼會短暫出現在本機 `/usr/bin/zip` 程序參數中
- Finder Extension 需要在 macOS 系統設定中手動啟用
- 目前沒有自動更新機制

## 安裝

1. 下載 `TuckByte.dmg` 與 `TuckByte.dmg.sha256`。
2. 驗證 SHA-256。
3. 開啟 DMG，將 TuckByte 拖進 Applications。
4. 第一次啟動若被 Gatekeeper 阻擋，至「隱私權與安全性」選擇「仍要打開」。
5. 在 TuckByte 設定頁開啟系統設定並啟用 Finder Extension。
