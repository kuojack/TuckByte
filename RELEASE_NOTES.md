# TuckByte 0.8.0 開發測試版

## 主要更新

- 新增 experimental `.tuck` v1 原生格式與 `.tuck.001` 直接串流分卷。
- Zstandard 1.5.7 分塊壓縮、Store fallback 與 bounded 多核心 pipeline。
- Argon2id v1.3 + AES-256-GCM、加密索引、domain-separated keys、nonce
  唯一性驗證及不重加密內容的密碼變更。
- 安全 parser limits、UTF-8 NFC 路徑、越界／碰撞／重疊防護、atomic output、
  可用空間檢查、進度與取消清理。
- App 與 Finder 流程可辨識、建立、瀏覽與解壓 `.tuck`。
- 加入 golden vector、tamper／錯誤密碼／缺卷／取消／危險路徑測試、格式
  inspection CLI、mutation fuzz smoke driver 與 benchmark harness。
- 更新 Zstandard、Argon2、minizip-ng 第三方授權通知與 App 打包資源。

## 重要限制

- `.tuck` 仍設定 experimental flag；完成長時間 coverage-guided fuzzing、最低
  支援硬體校準與獨立安全審查前，不承諾永久封存相容性。
- App 仍未使用 Developer ID 簽章或 Apple notarization。
- 7z 仍僅支援未加密的瀏覽與解壓；ZIP 舊流程仍會使用 macOS 系統工具。

完整格式與安全假設見 `Docs/TUCK_FORMAT.md` 與
`Docs/TUCK_THREAT_MODEL.md`。
