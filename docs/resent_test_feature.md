# 資料補傳測試功能文檔

**建立日期**：2025-12-04  
**版本**：2.0（獨立模組版本）

---

## 一、功能概述

此功能用於測試藍牙裝置的「資料補傳」機制，包含：
1. **最大補傳時間測試**：確認裝置能保留多長時間的離線資料
2. **即時資料影響測試**：確認補傳期間是否影響即時資料的接收
3. **補傳完整性測試**：確認補傳資料是否完整無遺漏

---

## 二、檔案結構

```
lib/
├── ble_test/                         # 測試模組（獨立）
│   ├── ble_test.dart                 # 模組匯出檔
│   ├── resent_test_service.dart      # 測試服務（核心邏輯）
│   ├── resent_test_widget.dart       # 測試 UI 元件
│   └── resent_test_page.dart         # 獨立測試頁面（可選）
├── services/
│   └── simple_single_connection_service.dart  # 簡易藍牙連線服務（整合測試功能）
└── simple_single_connection_view.dart          # 簡易連線頁面（整合測試 UI）
```

---

## 三、目前整合方式

測試功能已整合到 `simple` 中，所有測試相關程式碼都有 `⭐ 測試功能` 標記。

### Service 層修改 (`simple_single_connection_service.dart`)

```dart
// ⭐ 測試功能（移除時註解掉此行）
import 'package:flutter_itri_hrbr/ble_test/ble_test.dart';

// ...

// ⭐ 測試功能（移除時註解掉此區塊）
final ReSentTestService _testService = ReSentTestService();
ReSentTestService get testService => _testService;
// ⭐ 測試功能結束

// ...

// ⭐ 測試功能：記錄測試資料（移除時註解掉此行）
_testService.recordTestData(value);

// ...

// ⭐ 測試功能：清理測試服務（移除時註解掉此行）
_testService.dispose();
```

### View 層修改 (`simple_single_connection_view.dart`)

```dart
// ⭐ 測試功能（移除時註解掉此行）
import 'package:flutter_itri_hrbr/ble_test/ble_test.dart';

// ...

// ⭐ 測試功能 UI（移除時註解掉此區塊）
const SizedBox(height: 16),
ReSentTestWidget(
  testService: service.testService,
  isConnected: serviceState.isConnected,
  onDisconnect: () => service.disconnectFromDevice(),
  onReconnect: () => service.connectToDevice(serviceState.connectedDevice!),
),
// ⭐ 測試功能 UI 結束
```

---

## 四、移除測試功能的步驟

當你要把 `simple` 給別人使用時，只需要：

### 1. `simple_single_connection_service.dart`
註解掉以下幾行：
- Line 16: `import 'package:flutter_itri_hrbr/ble_test/ble_test.dart';`
- Line 88-90: `_testService` 相關
- Line 467: `_testService.recordTestData(value);`
- Line 746: `_testService.dispose();`

### 2. `simple_single_connection_view.dart`
註解掉以下幾行：
- Line 11: `import 'package:flutter_itri_hrbr/ble_test/ble_test.dart';`
- Line 244-252: `ReSentTestWidget` 區塊

---

## 五、測試功能 API

### ReSentTestService

| 方法 | 說明 |
|------|------|
| `recordTestData(List<int> data)` | 記錄測試資料 |
| `startTimedDisconnectTest(...)` | 開始定時斷線測試 |
| `cancelTimedTest()` | 取消測試 |
| `clearTestRecords()` | 清空記錄 |
| `getRealtimeStats()` | 取得即時統計 |
| `generateTestReport()` | 產生測試報告 |
| `parseDeviceTimestamp(List<int> data)` | 解析裝置時間戳 |
| `isReSentData(List<int> data)` | 判斷是否為補傳資料 |

### ReSentTestWidget

| 參數 | 類型 | 說明 |
|------|------|------|
| `testService` | `ReSentTestService` | 測試服務實例 |
| `isConnected` | `bool` | 是否已連線 |
| `onDisconnect` | `Future<void> Function()` | 斷線回調 |
| `onReconnect` | `Future<bool> Function()` | 重連回調 |

---

## 六、資料識別方式

| 第一位 Byte | 十進位 | 類型 |
|------------|--------|------|
| `0xFA` | 250 | 補傳資料 |
| `0xFF` | 255 | 即時資料 |

---

## 七、時間戳解析

原始資料的 `data[1]~[5]` 為時間戳（10ms 單位）：

```dart
int timestamp = data[1]              // TS1 (第 0-7 位)
              + (data[2] << 8)       // TS2 (第 8-15 位)
              + (data[3] << 16)      // TS3 (第 16-23 位)
              + (data[4] << 24)      // TS4 (第 24-31 位)
              + (data[5] << 32);     // TS5 (第 32-39 位)

// 轉回毫秒
int milliseconds = timestamp * 10;
```

---

## 八、測試報告範例

```
========== 測試報告 ==========
斷線時間：2025-12-04 14:00:00
重連時間：2025-12-04 14:00:10
斷線時長：10 秒

--- 補傳資料統計 ---
補傳筆數：312 筆
補傳時間範圍：14:00:00 ~ 14:00:09
預期筆數：320 筆
完整率：97.5%

--- 即時資料統計 ---
即時筆數：156 筆
補傳平均延遲：5000 ms
即時平均延遲：45 ms
即時最大延遲：120 ms

--- 時間戳缺口分析 ---
缺口數量：2
缺口位置：
  - 第 45 筆前缺 1 筆 (間隔 62ms)
  - 第 198 筆前缺 2 筆 (間隔 93ms)
================================
```

---

## 九、注意事項

1. **測試功能已整合到 simple**，不需要額外頁面
2. **所有測試程式碼都有 `⭐` 標記**，方便識別和移除
3. **每次測試前建議清空記錄**
4. **確保裝置電量充足**

---

## 十、後續擴展

- [ ] 匯出測試報告到檔案
- [ ] 支援多組測試對比
- [ ] 視覺化時間戳分佈圖
- [ ] 自動化批次測試
