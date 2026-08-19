# MenuPeek

macOS 選單列圖示的搜尋面板。按 `⌃⌥⌘M` 叫出面板，可以看到**全部**的選單列圖示
（包含被瀏海遮住、或被其他選單列管理器推出畫面的），打字過濾，點擊直接觸發。

## 為什麼需要它

14 吋 MacBook Pro 的瀏海佔掉選單列中間 185px（實測 x=663~848）。
右側可用區只有 664px，而 18 個圖示的總寬是 706px —— 塞不下。
macOS 會把放不下的圖示直接藏起來，而且沒有任何介面可以叫出來。

## 權限

只需要**輔助使用（Accessibility）**。不需要螢幕錄製。

圖示是用 `NSRunningApplication.icon` 取得擁有者 app 的圖示，
不是截取選單列的畫面，所以省掉了螢幕錄製權限。

## 實作筆記

幾個踩過的坑，都是實測出來的：

- **圖示的真名只能靠 AX 拿。** `CGWindowList` 對第三方圖示一律回傳 `Item-0`，
  而且 macOS 26 上所有圖示的 owner 都顯示 "Control Center"，完全分不出誰是誰。
  改用 `AXExtrasMenuBar` 才能拿到真正的擁有者。

- **`AXPress` 的回傳碼是假訊號。**
  回 `cannotComplete(-25204)` 其實代表選單「有」打開——因為選單進入 modal tracking
  loop 把 AX 呼叫卡住了。反倒是回 `success(0)` 可能什麼都沒發生（ChatGPT、Clipipi
  那種自繪面板）。所以只有 `success` 時才需要確認有沒有真的長出 `AXMenu`，沒有就補一次模擬點擊。

- **`AXPress` 一定要在背景執行緒呼叫。** 跑在主執行緒上會被 modal tracking loop
  卡到選單關閉為止，整個 app 凍住，連熱鍵都沒反應。

- **瀏海範圍要用 `NSScreen.auxiliaryTopLeftArea/RightArea` 量**，不能估。

- **App 不能放在 Downloads。** 帶著 quarantine 從那裡執行會觸發 App Translocation，
  每次啟動路徑都不同，TCC 權限永遠授不牢。

## 開發

```sh
./build.sh          # 編譯 + 簽章，安裝到 ~/Applications/MenuPeek.app
```

簽章用的是本機自簽憑證 `MenuPeek Dev`（keychain 裡）。ad-hoc 簽章不能用：
每次重新編譯 cdhash 都會變，TCC 會判定成不同的 app，輔助使用權限就掉了。

開發用參數：`--show` 啟動即開面板。除錯記錄寫在 `~/menupeek-debug.log`。
