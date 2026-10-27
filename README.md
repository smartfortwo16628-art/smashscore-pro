# Badminton AI Coach

免費、離線、繁體中文／廣東話羽毛球訓練助手。Flutter 3.35.7、Dart 3.9、Android 9（API 28）以上。1.2 自動分析實驗版：匯入影片後在裝置上執行 ML Kit 姿態辨識，產生有影格依據的 2D 動作觀察及練習建議。沒有登入、廣告、付費 API 或雲端上傳。

## 自動分析

- 匯入完成即開始分析全段影片；既有影片可按「自動分析／查看報告」。
- 每秒約 8 個影格，最多 3 分鐘；有進度、停止、重試，離開 App 會停止。
- 找出完整抬手及回落的疑似頭頂揮拍；顯示時間、可信骨架及鏡頭平面的手肘角度、軀幹傾角、腳位變化。
- 保守提示：準備手肘較低、非持拍手未抬過肩、揮拍後軀幹傾斜；自動配對練習，可加入計劃及記錄改善。
- 支援左右手及鏡像設定；低可見度、短片、缺腳、突變、靜態姿勢不產生虛構技術評語。
- 報告與身體關鍵點存 SQLite，重開可看；每片保留最近三次，刪除影片／學員連帶清除骨架資料。

**重要界線：這是已接通真實姿態模型的實驗性 2D 規則系統，並非經訓練驗證的羽毛球分類器。** 不保證分辨高遠球／殺球、握拍、3D 轉身、擊球點、剪刀步或戰術回位。一般舉手也可能觸發疑似揮拍，需重看畫面。未有經家長同意且人工標註的兒童羽毛球資料集，因此不聲稱技術準確率或專業評分。

## 其他功能

- 六項技術教學，以正手高遠球為重點。
- 學員暱稱、年齡、慣用手、學習經驗、評估及改善紀錄。
- 系統選檔匯入影片到私人空間；最多 3 分鐘及 300 MiB。
- 0.25／0.5／0.75／1 倍播放、跳轉、原生影格索引逐格、截圖畫線與圖片匯出。
- 七項人工評估；按所選問題配對最多三項練習、教練口令及完成記錄。
- SQLite 離線儲存，刪除學員一併刪除其私人影片及相關資料。

逐格須 Android 解碼器支援影格索引且完整時間戳與影格數吻合，否則明確標示近似時間擷取，不會冒充逐格。手機影片格式支援依裝置而異。

## 免費編譯

使用公開 GitHub repository 的標準 `ubuntu-24.04` runner；不用付費大型 runner。Actions → Android AI APK 或建立 PR 會執行分析、單元／介面測試、release APK 編譯、APK 權限與簽章檢查、Android 模擬器整合測試。全部成功後提供 `Badminton-AI-Coach-AI-APK` artifact，保留 7 天。

在 Linux/macOS/Windows WSL 安裝 Flutter 3.35.7、Java 17、Android SDK、Python 3 及 ffmpeg 後：

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

1. 下載 `Badminton_AI_Coach_AI.apk` 並打開。
2. Android 要求時，暫時允許正在開啟檔案的瀏覽器／檔案 App「安裝未知應用程式」。
3. 安裝完成可關閉該項許可。App 本身不要求相機、咪高峰或整個媒體庫存取權。

此為 **release 模式、Android 測試金鑰簽署的測試 APK**，不適合直接上架。CI 每個全新 runner 可能產生不同測試金鑰；不同簽章無法覆蓋更新，先解除安裝會清除本機資料。正式持續更新須另外保管穩定的私人簽章金鑰，不能把私人金鑰提交到公開 repo。

## 資料與限制

release APK 無 INTERNET 權限；Android 備份及裝置資料轉移關閉；Android FLAG_SECURE 保護系統截圖／最近使用畫面（App 內自行產生標記圖片仍可使用）。資料依賴 Android App 沙盒及手機螢幕鎖，並非額外資料庫加密。請用暱稱、取得合適同意。匯出圖片後的副本由使用者保管。

ML Kit 人體姿態已啟用，bundled CPU 模型隨 APK 安裝；GPT API、雲端備份未啟用。本版本不會診斷傷患或自動判斷握拍手指、真實 3D 轉身角度、拍面或擊球瞬間。詳細規格見 `docs/APP_SPEC.md`，裝置驗收表見 `docs/DEVICE_CHECKS.md`。

ML Kit 並非全開源，遵循 Google ML Kit 條款；CPU 模型不要求帳戶或金鑰。其他依賴遵循各自開源授權；Flutter／Dart、sqflite、video_player 及 path 不需付費 API。設定畫面提供開源授權入口。

## 驗證範圍

- 規則回歸：左右手、鏡像、低可信值、缺腳、靜態舉手、鏡頭／身份突變、不完整動作、像素長寬比、時間重複及序列化。
- SQLite：v1→v2 無損遷移、報告重開、重複加入計劃只建立一份、低品質無針對性計劃、刪除身體資料。
- Android integration：原有媒體與畫線流程，加上真實 ML Kit inference、進度、取消、私有路徑限制、報告自動儲存及骨架畫面。
- 模擬器關閉 Wi-Fi／流動數據後冷啟動模型，驗證安裝時已內置模型。release APK 檢查沒有網絡權限，並驗證簽章。
- 真實模型 smoke test 使用 Google MediaPipe 公開固定人體姿勢照片轉為短片，SHA-256 鎖定上游內容，僅在建置時下載，不打包進 APK。此測試不能當成羽毛球技術準確率驗證。
- 手機效能、相容性、不同鏡頭及真實兒童羽毛球動作仍需裝置／人工標註驗收；詳見 docs/AUTO_ANALYSIS.md。
