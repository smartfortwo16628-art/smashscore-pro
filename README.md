# Badminton AI Coach

免費、離線、繁體中文／廣東話羽毛球訓練助手。Flutter 3.35.7、Dart 3.9、Android 9（API 28）以上。V1 使用教練人工觀察與規則配對練習，沒有自動 AI 評分、登入、廣告或雲端上傳。

## 功能

- 六項技術教學，以正手高遠球為重點。
- 學員暱稱、年齡、慣用手、學習經驗、評估及改善紀錄。
- 系統選檔匯入影片到私人空間；最多 3 分鐘及 300 MiB。
- 0.25／0.5／0.75／1 倍播放、跳轉、原生影格索引逐格、截圖畫線與圖片匯出。
- 七項人工評估；按所選問題配對最多三項練習、教練口令及完成記錄。
- SQLite 離線儲存，刪除學員一併刪除其私人影片及相關資料。

逐格須 Android 解碼器支援影格索引且完整時間戳與影格數吻合，否則明確標示近似時間擷取，不會冒充逐格。手機影片格式支援依裝置而異。

## 免費編譯

使用公開 GitHub repository 的標準 `ubuntu-24.04` runner；不用付費大型 runner。Actions → Android V1 APK 或建立 PR 會執行分析、單元／介面測試、release APK 編譯、APK 權限與簽章檢查、Android 模擬器整合測試。全部成功後提供 `Badminton-AI-Coach-V1-APK` artifact，保留 7 天。

在 Linux/macOS/Windows WSL 安裝 Flutter 3.35.7、Java 17、Android SDK 後：

```bash
sdkmanager 'platforms;android-36' 'build-tools;35.0.0' 'ndk;27.0.12077973'
bash scripts/build_apk.sh
```

`bootstrap.sh` 以指定 Flutter 版本產生標準 Android wrapper 和樣式，保留本專案的原生功能與權限設定。首次需網絡下載 SDK／依賴，App 安裝後可離線使用。CI 產生並保存 `pubspec.lock`；重建同一版本時使用該 lockfile。建置輸出 `build/app/outputs/flutter-apk/app-release.apk`。

Android 模擬器整合驗證：

```bash
flutter test integration_test/app_test.dart -d emulator-5554
```

## Android 手機安裝

1. 下載 `Badminton_AI_Coach_V1.apk` 並打開。
2. Android 要求時，暫時允許正在開啟檔案的瀏覽器／檔案 App「安裝未知應用程式」。
3. 安裝完成可關閉該項許可。App 本身不要求相機、咪高峰或整個媒體庫存取權。

此為 **release 模式、Android 測試金鑰簽署的測試 APK**，不適合直接上架。CI 每個全新 runner 可能產生不同測試金鑰；不同簽章無法覆蓋更新，先解除安裝會清除本機資料。正式持續更新須另外保管穩定的私人簽章金鑰，不能把私人金鑰提交到公開 repo。

## 資料與限制

release APK 無 INTERNET 權限；Android 備份及裝置資料轉移關閉；Android FLAG_SECURE 保護系統截圖／最近使用畫面（App 內自行產生標記圖片仍可使用）。資料依賴 Android App 沙盒及手機螢幕鎖，並非額外資料庫加密。請用暱稱、取得合適同意。匯出圖片後的副本由使用者保管。

ML Kit 人體姿態、GPT API、雲端備份均未啟用。本版本不會診斷傷患或自動判斷握拍手指、真實 3D 轉身角度、拍面或擊球瞬間。詳細規格見 `docs/APP_SPEC.md`，裝置驗收表見 `docs/DEVICE_CHECKS.md`。

依賴遵循各自開源授權；Flutter／Dart、sqflite、video_player 及 path 不需付費 API。設定畫面提供開源授權入口。
