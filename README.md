# MenuBaba

macOS 選單列圖示的搜尋面板。按 `⌃⌥⌘M` 叫出面板，可以看到**全部**的選單列圖示
（包含被瀏海遮住、或被其他選單列管理器推出畫面的），打字過濾，點擊直接觸發。

## 為什麼需要它

14 吋 MacBook Pro 的瀏海佔掉選單列中間 185px（實測 x=663~848）。
右側可用區只有 664px，而 18 個圖示的總寬是 706px —— 塞不下。
macOS 會把放不下的圖示直接藏起來，而且沒有任何介面可以叫出來。

## 權限

- **輔助使用（Accessibility）**：必要。用來列舉圖示、取得名稱、觸發點擊。
- **螢幕錄製**：選用。給了就能顯示選單列上的**原圖示**（用 ScreenCaptureKit
  截取圖示自己的視窗）；沒給就退回擁有者 app 的圖示，功能不受影響。

實測被瀏海遮住的圖示視窗也截得到，不會因為看不見就拿不到畫面。

## 實作筆記

幾個踩過的坑，都是實測出來的：

- **圖示的真名只能靠 AX 拿。** `CGWindowList` 對第三方圖示一律回傳 `Item-0`，
  而且 macOS 26 上所有圖示的 owner 都顯示 "Control Center"，完全分不出誰是誰。
  改用 `AXExtrasMenuBar` 才能拿到真正的擁有者。

- **`AXPress` 一下就夠了，不要自作聰明加後備方案。**
  這裡踩過一個很花時間的坑：開自繪面板的圖示（ChatGPT、Clipipi、控制中心那類）
  按下去之後**不會**產生 `AXMenu` 子元素，因為它們開的是 popover 不是選單。
  我一度把「沒有 AXMenu」當成「AXPress 失敗」，於是補送一次模擬點擊——
  結果那一下等於在同一顆圖示上再點一次，把剛打開的面板關掉了。
  症狀是「點了閃一下就消失」，看起來像 AXPress 無效，其實是後備方案自己搞的。

- **`AXPress` 的回傳碼不能用來判斷成敗。**
  回 `cannotComplete(-25204)` 可能是選單開了之後 modal tracking loop 卡住呼叫，
  也可能只是撞到 `AXUIElementSetMessagingTimeout` 設的上限，兩者共用同一個錯誤碼。
  結論是不要根據回傳碼做任何後續動作。

- **`AXPress` 一定要在背景執行緒呼叫。** 跑在主執行緒上會被 modal tracking loop
  卡到選單關閉為止，整個 app 凍住，連熱鍵都沒反應。

- **瀏海範圍要用 `NSScreen.auxiliaryTopLeftArea/RightArea` 量**，不能估。

- **截到的圖示要標成 template image**，否則白色圖示在淺色面板上會整個看不見。
  另外時鐘那種是一長條文字（165x33），縮進小方格會糊成一團，長寬比超過 2.5 的就不採用。

- **App 不能放在 Downloads。** 帶著 quarantine 從那裡執行會觸發 App Translocation，
  每次啟動路徑都不同，TCC 權限永遠授不牢。

## 開發

```sh
./build.sh          # 編譯 + 簽章，安裝到 ~/Applications/MenuBaba.app
```

簽章用的是本機自簽憑證 `MenuBaba Dev`（keychain 裡）。ad-hoc 簽章不能用：
每次重新編譯 cdhash 都會變，TCC 會判定成不同的 app，輔助使用權限就掉了。

開發用參數：`--show` 啟動即開面板。除錯記錄寫在 `~/menubaba-debug.log`。
