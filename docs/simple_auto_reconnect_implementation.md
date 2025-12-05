# Simple 模組自動重連功能實作文檔

> 建立日期：2025-12-05
> 版本：1.0
> 狀態：✅ 已實作

---

## 📋 目錄

1. [功能概述](#功能概述)
2. [重連策略設計](#重連策略設計)
3. [修改檔案清單](#修改檔案清單)
4. [詳細修改內容](#詳細修改內容)
5. [UI 狀態說明](#ui-狀態說明)
6. [使用方式](#使用方式)
7. [時間軸範例](#時間軸範例)
8. [還原方式](#還原方式)

---

## 功能概述

### 目標
為 `simple_single_connection_service.dart` 新增**自動重連**功能，當藍牙裝置意外斷線時，能夠自動嘗試重新連線。

### 參考來源
- `data_match_service.dart` 的兩段式重連策略
- 業界 BLE 最佳實踐（指數退避、避免 OS 節流）

### 核心原則
| 原則 | 說明 |
|------|------|
| 指數退避 | 每次失敗後，等待時間遞增 |
| 避免立即重連 | 不會斷線後馬上重連，避免 OS 節流 |
| 週期性掃描 | 不會無限掃描，節省電量 |
| 使用者控制 | 提供手動重連、取消重連選項 |
| 平台差異處理 | iOS/Android 使用不同參數 |

---

## 重連策略設計

### 三階段重連策略

```
┌─────────────────────────────────────────────────────────────┐
│                    自動重連策略                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  階段1：快速重連（不掃描）                                    │
│  ├─ 嘗試次數：2 次                                          │
│  ├─ 每次超時：3 秒                                          │
│  ├─ 失敗間隔：2 秒                                          │
│  ├─ 方式：iOS 幽靈連線 + fromId 直連                         │
│  └─ 失敗後 → 進入階段2                                      │
│                                                             │
│  階段2：掃描重連（指數退避）                                  │
│  ├─ 嘗試次數：3 次                                          │
│  ├─ 掃描時間：10s → 15s → 20s（遞增）                        │
│  ├─ 失敗間隔：3s → 5s → 8s（指數退避）                       │
│  └─ 失敗後 → 進入階段3                                      │
│                                                             │
│  階段3：使用者介入                                           │
│  ├─ 停止自動重連                                            │
│  ├─ 顯示「連線失敗，請確認裝置在範圍內」                       │
│  ├─ 提供「重新連線」按鈕                                     │
│  └─ 使用者點擊後 → 重新從階段1開始                           │
│                                                             │
│  特殊處理：                                                  │
│  ├─ 連線錯誤（非找不到）：不消耗嘗試次數，額外給 2 次機會      │
│  ├─ 使用者手動斷線：不觸發自動重連                           │
│  └─ enableAutoReconnect = false：不觸發自動重連              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 參數配置

```dart
// 階段1：快速重連參數
static const int _quickReconnectAttempts = 2;      // 快速重連嘗試次數
static const int _quickReconnectTimeout = 3;       // 快速重連超時（秒）
static const int _quickReconnectInterval = 2;      // 快速重連間隔（秒）

// 階段2：掃描重連參數
static const int _scanReconnectAttempts = 3;       // 掃描重連嘗試次數
static const List<int> _scanDurations = [10, 15, 20];  // 掃描時間（秒）
static const List<int> _scanIntervals = [3, 5, 8];     // 掃描間隔（秒）

// 總計最大嘗試次數
static const int _maxReconnectAttempts = 5;        // 2 + 3 = 5 次

// 連線錯誤額外機會
static const int _maxConnectionErrorRetries = 2;   // 連線錯誤額外嘗試次數
```

---

## 修改檔案清單

| 檔案 | 修改類型 | 說明 |
|------|----------|------|
| `lib/services/simple_single_connection_service.dart` | 修改 | 新增自動重連邏輯 |
| `lib/pages/simple_page.dart` | 修改 | 新增重連狀態 UI |

---

## 詳細修改內容

### 1. `simple_single_connection_service.dart`

#### 1.1 新增枚舉

```dart
/// 重連狀態枚舉
enum ReconnectStatus {
  idle,           // 未重連
  quickRetry,     // 階段1：快速重連中
  scanning,       // 階段2：掃描中
  connecting,     // 正在連線
  waiting,        // 等待下一次嘗試
  failed,         // 重連失敗（階段3）
  success,        // 重連成功
}

/// 重連階段枚舉
enum ReconnectPhase {
  none,           // 無
  quick,          // 階段1：快速重連
  scan,           // 階段2：掃描重連
}
```

#### 1.2 修改 `SimpleConnectionState`

新增欄位（普通 Dart class，不使用 Freezed）：

```dart
class SimpleConnectionState {
  // ... 現有欄位 ...
  
  // ===== 新增：重連相關欄位 =====
  final bool isReconnecting;
  final ReconnectStatus reconnectStatus;
  final ReconnectPhase reconnectPhase;
  final int reconnectAttempts;
  final String reconnectMessage;
  final int reconnectRemainingSeconds;
  
  SimpleConnectionState({
    // ... 現有欄位 ...
    this.isReconnecting = false,
    this.reconnectStatus = ReconnectStatus.idle,
    this.reconnectPhase = ReconnectPhase.none,
    this.reconnectAttempts = 0,
    this.reconnectMessage = '',
    this.reconnectRemainingSeconds = 0,
  });
  
  /// copyWith 方法
  SimpleConnectionState copyWith({
    // ... 現有欄位 ...
    bool? isReconnecting,
    ReconnectStatus? reconnectStatus,
    ReconnectPhase? reconnectPhase,
    int? reconnectAttempts,
    String? reconnectMessage,
    int? reconnectRemainingSeconds,
  }) {
    return SimpleConnectionState(
      // ... 現有欄位 ...
      isReconnecting: isReconnecting ?? this.isReconnecting,
      reconnectStatus: reconnectStatus ?? this.reconnectStatus,
      reconnectPhase: reconnectPhase ?? this.reconnectPhase,
      reconnectAttempts: reconnectAttempts ?? this.reconnectAttempts,
      reconnectMessage: reconnectMessage ?? this.reconnectMessage,
      reconnectRemainingSeconds: reconnectRemainingSeconds ?? this.reconnectRemainingSeconds,
    );
  }
}
```

#### 1.3 新增類別變數

```dart
// ===== 自動重連相關 =====
bool enableAutoReconnect = true;              // 控制是否啟用自動重連
bool _isIntentionalDisconnect = false;        // 是否為主動斷線
BluetoothDevice? _lastConnectedDevice;        // 上次連線的裝置
List<Guid> _lastConnectedServiceUuids = [];   // 上次的服務 UUIDs

// 重連計數器
int _reconnectAttempts = 0;                   // 目前重連嘗試次數
int _connectionErrorRetries = 0;              // 連線錯誤額外嘗試次數

// 重連計時器
Timer? _reconnectTimer;
Timer? _countdownTimer;
StreamSubscription? _reconnectScanSubscription;
```

#### 1.4 新增/修改方法

| 方法名稱 | 類型 | 說明 |
|----------|------|------|
| `setAutoReconnect(bool)` | 新增 | 設定是否啟用自動重連 |
| `cancelReconnect()` | 新增 | 手動取消重連 |
| `retryReconnect()` | 新增 | 手動觸發重連（階段3 使用） |
| `_handleUnexpectedDisconnect()` | 新增 | 處理意外斷線 |
| `_scheduleReconnect()` | 新增 | 排程重連 |
| `_quickReconnect()` | 新增 | 階段1：快速重連 |
| `_startScanReconnect()` | 新增 | 階段2：掃描重連 |
| `_tryRetrieveSystemConnectedDevice()` | 新增 | iOS 幽靈連線檢查 |
| `_startCountdown()` | 新增 | 啟動倒數計時（UI 用） |
| `_stopCountdown()` | 新增 | 停止倒數計時 |
| `_updateReconnectState()` | 新增 | 更新重連狀態 |
| `disconnectFromDevice()` | 修改 | 新增 `_isIntentionalDisconnect` 設定 |
| `connectToDevice()` | 修改 | 新增意外斷線偵測 |
| `cleanup()` | 修改 | 新增重連相關資源清理 |

#### 1.5 修改連線監聽器

在 `connectToDevice()` 方法內的連線狀態監聽器中新增：

```dart
_connectionSubscription = device.connectionState.listen((state) {
  if (state == BluetoothConnectionState.disconnected) {
    // 檢查是否為意外斷線
    if (!_isIntentionalDisconnect && enableAutoReconnect) {
      _handleUnexpectedDisconnect(device);
    }
  }
});
```

---

### 2. `simple_page.dart`

#### 2.1 新增重連狀態 UI 區塊

位置：連線按鈕下方

```dart
// 重連狀態顯示
if (connectionState.isReconnecting) {
  _buildReconnectStatusWidget(connectionState)
}
```

#### 2.2 UI 元件內容

```dart
Widget _buildReconnectStatusWidget(SimpleConnectionState state) {
  return Container(
    padding: EdgeInsets.all(16),
    margin: EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(
      color: Colors.orange.shade50,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.orange.shade200),
    ),
    child: Column(
      children: [
        // 狀態圖示 + 文字
        Row(
          children: [
            _getStatusIcon(state.reconnectStatus),
            SizedBox(width: 8),
            Text(state.reconnectMessage),
          ],
        ),
        
        // 進度顯示
        Text('第 ${state.reconnectAttempts}/5 次嘗試'),
        
        // 倒數計時（如果在等待中）
        if (state.reconnectStatus == ReconnectStatus.waiting)
          Text('${state.reconnectRemainingSeconds} 秒後重試'),
        
        // 取消按鈕
        TextButton(
          onPressed: () => ref.read(simpleConnectionProvider.notifier).cancelReconnect(),
          child: Text('取消重連'),
        ),
      ],
    ),
  );
}
```

#### 2.3 階段3 失敗 UI

```dart
if (connectionState.reconnectStatus == ReconnectStatus.failed) {
  return Container(
    // 紅色警告樣式
    child: Column(
      children: [
        Icon(Icons.error, color: Colors.red),
        Text('連線失敗，請確認裝置在範圍內'),
        ElevatedButton(
          onPressed: () => ref.read(simpleConnectionProvider.notifier).retryReconnect(),
          child: Text('重新連線'),
        ),
      ],
    ),
  );
}
```

#### 2.4 新增自動重連開關（Optional）

```dart
SwitchListTile(
  title: Text('自動重連'),
  subtitle: Text('斷線時自動嘗試重新連線'),
  value: connectionState.enableAutoReconnect,
  onChanged: (value) {
    ref.read(simpleConnectionProvider.notifier).setAutoReconnect(value);
  },
),
```

---

## UI 狀態說明

### ReconnectStatus 對應 UI

| 狀態 | 圖示 | 訊息 | 顯示倒數 |
|------|------|------|----------|
| `idle` | - | - | 否（不顯示區塊） |
| `quickRetry` | 🔄 | 快速重連中... | 否 |
| `scanning` | 📡 | 掃描裝置中... | 否 |
| `connecting` | 🔗 | 正在連線... | 否 |
| `waiting` | ⏳ | 等待重試 | 是 |
| `failed` | ❌ | 連線失敗 | 否（顯示重試按鈕） |
| `success` | ✅ | 重連成功！ | 否（2秒後隱藏） |

---

## 使用方式

### 啟用/停用自動重連

```dart
// 啟用
ref.read(simpleConnectionProvider.notifier).setAutoReconnect(true);

// 停用
ref.read(simpleConnectionProvider.notifier).setAutoReconnect(false);
```

### 手動取消重連

```dart
ref.read(simpleConnectionProvider.notifier).cancelReconnect();
```

### 手動觸發重連（階段3 失敗後）

```dart
ref.read(simpleConnectionProvider.notifier).retryReconnect();
```

### 監聽重連狀態

```dart
final connectionState = ref.watch(simpleConnectionProvider);

if (connectionState.isReconnecting) {
  print('重連中：${connectionState.reconnectMessage}');
  print('嘗試次數：${connectionState.reconnectAttempts}/5');
}

if (connectionState.reconnectStatus == ReconnectStatus.failed) {
  print('重連失敗，需要使用者介入');
}
```

---

## 時間軸範例

### 最佳情況（階段1 成功）

```
0s    ─ 意外斷線
      ─ 狀態：quickRetry
2s    ─ 階段1-第1次：快速直連
5s    ─ 連線成功！
      ─ 狀態：success → idle
```

**總耗時：約 5 秒**

### 一般情況（階段2 成功）

```
0s    ─ 意外斷線
      ─ 狀態：quickRetry
2s    ─ 階段1-第1次：快速直連（失敗）
7s    ─ 階段1-第2次：快速直連（失敗）
      ─ 狀態：waiting (3秒)
12s   ─ 階段2-第1次：掃描 10 秒
22s   ─ 找到裝置，連線成功！
      ─ 狀態：success → idle
```

**總耗時：約 22 秒**

### 最差情況（階段3 失敗）

```
0s    ─ 意外斷線
      ─ 狀態：quickRetry
2s    ─ 階段1-第1次：快速直連（失敗）
7s    ─ 階段1-第2次：快速直連（失敗）
      ─ 狀態：scanning
12s   ─ 階段2-第1次：掃描 10 秒（失敗）
      ─ 狀態：waiting (3秒)
25s   ─ 階段2-第2次：掃描 15 秒（失敗）
      ─ 狀態：waiting (5秒)
45s   ─ 階段2-第3次：掃描 20 秒（失敗）
65s   ─ 停止重連
      ─ 狀態：failed
      ─ 顯示「連線失敗，請確認裝置在範圍內」+ 重試按鈕
```

**總耗時：約 65 秒（約 1 分鐘）**

---

## 注意事項

1. **主動斷線不觸發重連**：使用者點擊斷線按鈕時，設定 `_isIntentionalDisconnect = true`，不會觸發自動重連。

2. **連線錯誤處理**：如果是連線錯誤（非找不到裝置），額外給 2 次機會，不消耗主要嘗試次數。

3. **資源清理**：在 `cleanup()` 和 `disconnectFromDevice()` 中都會清理重連相關的 Timer 和 Subscription。

4. **iOS 幽靈連線**：在階段1 會先檢查 iOS 系統層是否有殘留的幽靈連線，有的話直接利用。

5. **狀態同步**：所有狀態變更都會透過 `state = state.copyWith(...)` 更新，UI 可以即時響應。

---

## 還原方式

如需還原到修改前的版本，備份檔案位於：

```bash
# Service 備份
lib/services/simple_single_connection_service.dart.backup_20251205

# UI 備份
lib/simple_single_connection_view.dart.backup_20251205
```

還原指令：

```bash
# 還原 Service
cp lib/services/simple_single_connection_service.dart.backup_20251205 lib/services/simple_single_connection_service.dart

# 還原 UI
cp lib/simple_single_connection_view.dart.backup_20251205 lib/simple_single_connection_view.dart
```

---

## 實作完成清單

- [x] 文檔內容確認
- [x] 新增 `ReconnectStatus` 和 `ReconnectPhase` 枚舉
- [x] 修改 `SimpleConnectionState` 新增重連欄位
- [x] 新增重連相關變數和參數配置
- [x] 修改 `connectToDevice()` 加入重連偵測
- [x] 修改 `disconnectFromDevice()` 加入主動斷線標記
- [x] 實作 `setAutoReconnect()` 開關方法
- [x] 實作 `cancelReconnect()` 取消重連
- [x] 實作 `retryReconnect()` 手動重連
- [x] 實作 `_handleUnexpectedDisconnect()` 意外斷線處理
- [x] 實作 `_startQuickReconnect()` 階段1 快速重連
- [x] 實作 `_startScanReconnect()` 階段2 掃描重連
- [x] 實作 `_enterFailedState()` 階段3 失敗狀態
- [x] 實作 `_completeReconnection()` 完成重連流程
- [x] 實作 `_tryRetrieveSystemConnectedDevice()` iOS 幽靈連線
- [x] 實作 `_startCountdown()` 和 `_stopCountdown()` 倒數計時
- [x] 修改 `cleanup()` 清理重連資源
- [x] UI：新增 `_buildReconnectStatusWidget()` 重連狀態顯示
- [x] UI：新增自動重連開關
- [x] UI：重連失敗後顯示重試按鈕
