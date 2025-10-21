import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_itri_hrbr/helper/devLog.dart';
import 'package:flutter_itri_hrbr/model/health_data.dart';
import 'package:flutter_itri_hrbr/provider/health_provider.dart';
import 'package:flutter_itri_hrbr/provider/multi_device_health_provider.dart';
import 'package:flutter_itri_hrbr/services/HealthCalculate_Device_ID.dart';
import 'package:flutter_itri_hrbr/services/data_Classifier_Service.dart';
import 'package:flutter_itri_hrbr/utils/performance_monitor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:permission_handler/permission_handler.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 📦 狀態模型定義區
// ═══════════════════════════════════════════════════════════════════════════

/// 定義藍牙管理器需要維護的所有狀態
class BluetoothMultiConnectionState {
  /// 使用 Map 來儲存所有已連線的裝置，以 deviceId 為 key
  final Map<DeviceIdentifier, BluetoothDevice> connectedDevices;

  /// 當前掃描到的裝置列表
  final List<ScanResult> scanResults;

  /// 是否正在掃描
  final bool isScanning;

  const BluetoothMultiConnectionState({
    this.connectedDevices = const {},
    this.scanResults = const [],
    this.isScanning = false,
  });

  /// 方便複製並更新狀態的 copyWith 方法
  BluetoothMultiConnectionState copyWith({
    Map<DeviceIdentifier, BluetoothDevice>? connectedDevices,
    List<ScanResult>? scanResults,
    bool? isScanning,
  }) {
    return BluetoothMultiConnectionState(
      connectedDevices: connectedDevices ?? this.connectedDevices,
      scanResults: scanResults ?? this.scanResults,
      isScanning: isScanning ?? this.isScanning,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🔌 Provider 定義區
// ═══════════════════════════════════════════════════════════════════════════

/// Riverpod Provider，讓 App 的任何地方都能取用我們的 BluetoothManager
final bluetoothManagerProvider =
    StateNotifierProvider<BluetoothMultiManager, BluetoothMultiConnectionState>(
      (ref) {
        final manager = BluetoothMultiManager(ref);
        ref.onDispose(manager.cleanup);
        return manager;
      },
    );

// ═══════════════════════════════════════════════════════════════════════════
// 🧠 藍牙管理器主類別
// ═══════════════════════════════════════════════════════════════════════════

/// 藍牙「大腦」：負責所有藍牙相關的狀態與邏輯，完全獨立於 UI
class BluetoothMultiManager
    extends StateNotifier<BluetoothMultiConnectionState> {
  BluetoothMultiManager(this._ref)
    : super(const BluetoothMultiConnectionState()) {
    _initBluetoothStateListener();
  }

  final Ref _ref;

  // ───────────────────────────────────────────────────────────────────────
  // 📊 SDK 計算器管理區（每裝置獨立實例）
  // ───────────────────────────────────────────────────────────────────────

  /// 儲存每個裝置專屬的 SDK 計算器實例
  final Map<DeviceIdentifier, HealthCalculateDeviceID> _calculators = {};

  /// 🔧 工具方法：取得或建立指定裝置的計算器
  HealthCalculateDeviceID _getCalculator(DeviceIdentifier id) {
    return _calculators.putIfAbsent(id, () => HealthCalculateDeviceID(3));
  }

  // ───────────────────────────────────────────────────────────────────────
  // 🔗 連線狀態監聽管理區
  // ───────────────────────────────────────────────────────────────────────

  /// 儲存每個裝置的連線狀態監聽器
  final Map<DeviceIdentifier, StreamSubscription<BluetoothConnectionState>>
  _connectionSubscriptions = {};

  // ───────────────────────────────────────────────────────────────────────
  // 🗂️ 服務快取區
  // ───────────────────────────────────────────────────────────────────────

  /// 快取每個裝置的藍牙服務列表（避免重複發現）
  final Map<DeviceIdentifier, List<BluetoothService>> _servicesCache = {};

  // ───────────────────────────────────────────────────────────────────────
  // 📡 藍牙特徵資料儲存區（依裝置分隔）
  // ───────────────────────────────────────────────────────────────────────

  /// 儲存每個裝置的 Notify 特徵資料
  final Map<DeviceIdentifier, Map<Guid, List<int>>> _notifyValues = {};

  /// 儲存每個裝置的 Read 特徵資料
  final Map<DeviceIdentifier, Map<Guid, List<int>>> _readValues = {};

  /// 儲存每個裝置的 Notify 訂閱監聽器
  final Map<DeviceIdentifier, Map<Guid, StreamSubscription<List<int>>>>
  _notifySubs = {};

  /// 對外提供唯讀的服務快取
  Map<DeviceIdentifier, List<BluetoothService>> get servicesCache =>
      _servicesCache;

  // ───────────────────────────────────────────────────────────────────────
  // 🔍 掃描管理區
  // ───────────────────────────────────────────────────────────────────────

  /// 掃描結果的訂閱監聽器
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;

  /// 藍牙開關狀態的訂閱監聽器
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;

  /// 掃描計時器（用於超時停止）
  Timer? _scanTimer;

  // ───────────────────────────────────────────────────────────────────────
  // ⏱️ UI 節流機制區（防止過度頻繁更新）
  // ───────────────────────────────────────────────────────────────────────

  /// 記錄每個裝置最後一次 UI 更新的時間
  // final Map<DeviceIdentifier, DateTime> _lastUIUpdate = {};

  /// UI 更新的最小間隔（100 毫秒）
  // static const _uiUpdateInterval = Duration(milliseconds: 100);

  // ───────────────────────────────────────────────────────────────────────
  // 📦 批次更新機制區（基於 Timer 的資料累積與延遲更新）
  // ───────────────────────────────────────────────────────────────────────

  /// 批次更新的計時器（1.5 秒後統一更新）
  Timer? _batchUpdateTimer;

  /// 🎯 核心資料暫存區：累積待處理的健康資料（key = deviceId）
  /// 📝 資料流向：toggleNotify 接收 → 存入此 Map → _scheduleBatchUpdate 讀取並送出
  final Map<DeviceIdentifier, HealthData> _pendingHealthUpdates = {};

  /// 標記是否有待處理的狀態更新
  bool _hasPendingStateUpdate = false;

  // ───────────────────────────────────────────────────────────────────────
  // 🔧 資料讀取工具方法區
  // ───────────────────────────────────────────────────────────────────────

  /// 取得指定裝置的 Notify 資料
  List<int>? getNotifyValue(DeviceIdentifier id, Guid uuid) =>
      _notifyValues[id]?[uuid];

  /// 取得指定裝置的 Read 資料
  List<int>? getReadValue(DeviceIdentifier id, Guid uuid) =>
      _readValues[id]?[uuid];

  /// 檢查指定裝置的特徵是否正在監聽
  bool isNotifying(DeviceIdentifier id, Guid uuid) =>
      _notifySubs[id]?.containsKey(uuid) ?? false;

  // ═══════════════════════════════════════════════════════════════════════════
  // 🎯 核心功能：批次更新排程（資料送出點）
  // ═══════════════════════════════════════════════════════════════════════════

  /// ✅ 批次更新排程（基於 Timer 的節流機制）
  ///
  /// 📋 功能說明：
  /// 1. 延遲 1.5 秒後統一處理所有累積的健康資料
  /// 2. 避免頻繁呼叫 Provider 更新，減少 UI 重繪次數
  /// 3. 自動防止重複排程（使用 ??= 運算子）
  ///
  /// 📤 資料送出流程：
  /// _pendingHealthUpdates（暫存） → batchUpdate（Provider） → UI 更新
  void _scheduleBatchUpdate() {
    // 📊 效能監控：記錄更新頻率
    PerformanceMonitor().logUpdate('health_updates');

    // 🔒 防重複：如果已有排程中的 timer，不重複建立
    _batchUpdateTimer ??= Timer(const Duration(milliseconds: 150), () {
      // 📤 批次送出：如果有累積的健康資料，統一送出
      if (_pendingHealthUpdates.isNotEmpty) {
        // 🎯 關鍵操作：呼叫 Provider 批次更新所有裝置的健康資料
        _ref
            .read(batchHealthUpdaterProvider)
            .batchUpdate(_pendingHealthUpdates);

        devLog(
          '批次更新',
          '✅ 已更新 ${_pendingHealthUpdates.length} 個裝置的健康資料',
        );

        // 🧹 清空暫存：送出後清空待處理佇列
        _pendingHealthUpdates.clear();
      }

      // 🔄 狀態更新：如果有需要更新的 UI 狀態，執行一次
      if (_hasPendingStateUpdate) {
        state = state.copyWith();
        _hasPendingStateUpdate = false;
      }

      // 🔓 重置 timer：允許下次排程
      _batchUpdateTimer = null;
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🎧 藍牙狀態監聽初始化
  // ═══════════════════════════════════════════════════════════════════════════

  /// 初始化藍牙狀態監聽器（監聽藍牙開關狀態）
  void _initBluetoothStateListener() {
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((
      adapterState,
    ) {
      if (adapterState != BluetoothAdapterState.on) {
        // 如果藍牙被關閉，停止掃描
        if (state.isScanning) {
          stopScan();
        }
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔍 藍牙掃描功能區
  // ═══════════════════════════════════════════════════════════════════════════

  /// 開始掃描藍牙裝置
  ///
  /// 📋 功能流程：
  /// 1. 檢查權限與藍牙狀態
  /// 2. 清空舊掃描結果
  /// 3. 監聽掃描結果流
  /// 4. 啟動掃描並設定超時
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      // 🔐 權限檢查
      if (!await _requestPermissions()) {
        devLog('掃描', '權限不足，無法掃描');
        return;
      }

      // 📡 藍牙狀態檢查
      if (!await _checkBluetoothEnabled()) {
        devLog('掃描', '藍牙未開啟，無法掃描');
        return;
      }

      // 🔄 停止舊掃描
      if (state.isScanning) {
        await stopScan();
      }

      // 🧹 清空舊的掃描結果，並將狀態設為掃描中
      state = state.copyWith(scanResults: [], isScanning: true);

      // 🎧 開始監聽掃描結果流
      _scanResultsSubscription = FlutterBluePlus.scanResults.listen(
        (results) {
          // 🔍 過濾掉沒有名稱的裝置
          final filteredResults = results
              .where((r) => r.device.platformName.isNotEmpty)
              .toList();

          // 📊 排序：依據 RSSI 強度，訊號較強的排前面
          filteredResults.sort((a, b) => b.rssi.compareTo(a.rssi));

          state = state.copyWith(scanResults: filteredResults);
        },
        onError: (error) {
          devLog('掃描', '掃描錯誤: $error');
        },
      );

      // 🚀 正式開始掃描
      await FlutterBluePlus.startScan(timeout: timeout);

      // ⏰ 設定計時器，在超時後自動停止
      _scanTimer?.cancel();
      _scanTimer = Timer(timeout, () {
        if (state.isScanning) {
          stopScan();
        }
      });

      devLog('掃描', '✅ 開始掃描 (超時: ${timeout.inSeconds}秒)');
    } catch (e) {
      devLog('掃描', '開始掃描時發生錯誤: $e');
      state = state.copyWith(isScanning: false);
    }
  }

  /// 停止掃描
  Future<void> stopScan() async {
    try {
      _scanTimer?.cancel();
      _scanTimer = null;

      await FlutterBluePlus.stopScan();
      await _scanResultsSubscription?.cancel();
      _scanResultsSubscription = null;

      state = state.copyWith(isScanning: false);
      devLog('掃描', '已停止掃描');
    } catch (e) {
      devLog('掃描', '停止掃描時發生錯誤: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔗 裝置連線管理區
  // ═══════════════════════════════════════════════════════════════════════════

  /// 連線到指定裝置
  ///
  /// 📋 功能流程：
  /// 1. 檢查是否已連線（防重複）
  /// 2. 建立連線狀態監聽器
  /// 3. 執行連線
  /// 4. 儲存連線資訊
  /// 5. 發現服務並快取
  Future<bool> connectToDevice(BluetoothDevice device) async {
    // 🔒 防止重複連線
    if (state.connectedDevices.containsKey(device.remoteId)) {
      devLog('連線', '${device.platformName} 已經連線了。');
      return false;
    }

    // 🎧 先建立連線狀態監聽器（監聽意外斷線）
    final subscription = device.connectionState.listen(
      (connectionState) {
        if (connectionState == BluetoothConnectionState.disconnected) {
          devLog('連線', '${device.platformName} 意外斷線。');
          // 從連線列表中移除
          _removeDeviceFromConnected(device);
        }
        if (connectionState == BluetoothConnectionState.connected) {
          devLog(
            '連線',
            '${device.platformName} 連線成功，HealthCalculate 已初始化。',
          );
        }
      },
      onError: (error) {
        devLog('連線', '連線狀態監聽錯誤: $error');
      },
    );

    try {
      // 🔗 嘗試連線（15 秒超時）
      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

      // 💾 連線成功後，儲存監聽器和裝置
      _connectionSubscriptions[device.remoteId] = subscription;

      final newDevices = Map<DeviceIdentifier, BluetoothDevice>.from(
        state.connectedDevices,
      );
      newDevices[device.remoteId] = device;
      state = state.copyWith(connectedDevices: newDevices);

      devLog(
        '連線',
        '✅ 成功連線到 ${device.platformName}。目前連線數: ${state.connectedDevices.length}',
      );

      // 🔍 發現服務並快取
      try {
        final svcs = await device.discoverServices();
        _servicesCache[device.remoteId] = svcs;
        devLog('服務', '已發現 ${device.platformName} 的 ${svcs.length} 個服務');
      } catch (e) {
        devLog('服務', '發現服務時發生錯誤: $e');
      }

      return true;
    } catch (e) {
      devLog('連線', '連線到 ${device.platformName} 失敗: $e');
      await subscription.cancel();
      _connectionSubscriptions.remove(device.remoteId);
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 📖 藍牙特徵讀寫操作區
  // ═══════════════════════════════════════════════════════════════════════════

  /// 讀取特徵值
  Future<void> readCharacteristic(
    BluetoothDevice device,
    BluetoothCharacteristic c,
  ) async {
    try {
      final v = await c.read();
      // 💾 儲存讀取的資料
      (_readValues[device.remoteId] ??= {})[c.uuid] = v;
      devLog('Read', '[${device.platformName}] ${c.uuid} => $v');
      state = state.copyWith();
    } catch (e) {
      devLog('Read', '讀取失敗: $e');
    }
  }

  /// 寫入特徵值
  Future<void> writeCharacteristic(
    BluetoothDevice device,
    BluetoothCharacteristic c, {
    List<int>? bytes,
  }) async {
    try {
      final data = bytes ?? utf8.encode('Hello Flutter');
      await c.write(data, withoutResponse: true);
      devLog('Write', '[${device.platformName}] ${c.uuid} => $data');
    } catch (e) {
      devLog('Write', '寫入失敗: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🎯 核心功能：監聽藍牙通知並處理資料（資料接收點）
  // ═══════════════════════════════════════════════════════════════════════════

  /// ✅ 開始監聽特徵的通知（包含批次更新機制）
  ///
  /// 📋 完整資料流：
  /// 1. 📡 接收藍牙原始資料（value）
  /// 2. 🔍 資料篩選與驗證
  /// 3. 🧮 SDK 處理（splitPackage）
  /// 4. 💾 暫存至 _pendingHealthUpdates
  /// 5. ⏱️ 排程批次更新（_scheduleBatchUpdate）
  /// 6. 📤 1.5 秒後統一送出至 Provider
  Future<void> toggleNotify(
    BluetoothDevice device,
    BluetoothCharacteristic c,
  ) async {
    final subMap = _notifySubs.putIfAbsent(device.remoteId, () => {});

    if (subMap.containsKey(c.uuid)) {
      await subMap[c.uuid]?.cancel();
      await c.setNotifyValue(false);
      subMap.remove(c.uuid);
      devLog('Notify', '❌ [${device.platformName}] ${c.uuid} 已關閉');
      state = state.copyWith();
      return;
    }

    try {
      await c.setNotifyValue(true);
      final calc = _getCalculator(device.remoteId);

      // ✅ 新增：訂閱計數器
      int receivedCount = 0;

      final sub = c.lastValueStream.listen((value) async {
        receivedCount++;

        // ✅ Debug：每 10 筆輸出一次
        if (receivedCount % 10 == 1) {
          devLog(
            'Notify',
            '📡 [${device.platformName}] 已接收 $receivedCount 筆資料，長度: ${value.length}',
          );
        }

        (_notifyValues[device.remoteId] ??= {})[c.uuid] = value;

        if (!_ref.mounted) return;

        if (value.isEmpty || value.length < 17) {
          return;
        }

        final dataType = _ref
            .read(mutiFilteredFirstRawDataFamily(device.remoteId).notifier)
            .mutiFilterData(value, device.remoteId, _ref);

        if (dataType != DataType.first) {
          devLog('dataType', 'dataType = $dataType，忽略資料');
          return;
        }

        final dataValue = _ref.read(
          mutiFilteredFirstRawDataFamily(device.remoteId),
        );

        if (dataValue.splitRawData.isEmpty ||
            dataValue.splitRawData.length < 17) {
          devLog(
            '數據過濾',
            '⚠️ 篩選後資料為空或長度不足 (${dataValue.splitRawData.length})，已忽略',
          );
          return;
        }

        // 檢查 UI 更新間隔
        // final now = DateTime.now();
        // final lastUpdate = _lastUIUpdate[device.remoteId];
        // if (lastUpdate != null &&
        //     now.difference(lastUpdate) < _uiUpdateInterval) {
        //   return;
        // }

        try {
          await calc.splitPackage(
            Uint8List.fromList(dataValue.splitRawData),
            device.remoteId.toString(),
          );

          // ✅ Debug：SDK 處理結果
          final hr = calc.getHRValue() ?? 0;
          final br = calc.getBRValue() ?? 0;
          final temp = (calc.getTempValue() is num)
              ? (calc.getTempValue() as num).toDouble()
              : 0.0;

          devLog(
            'SDK處理',
            '✅ [${device.platformName}] HR=$hr, BR=$br, Temp=$temp',
          );

          _pendingHealthUpdates[device.remoteId] = HealthData(
            splitRawData: dataValue.splitRawData,
            hr: hr,
            br: br,
            gyroX: calc.getGyroValueX() ?? 0,
            gyroY: calc.getGyroValueY() ?? 0,
            gyroZ: calc.getGyroValueZ() ?? 0,
            temp: temp,
            hum: (calc.getHumValue() is num)
                ? (calc.getHumValue() as num).toDouble()
                : 0.0,
            spO2: calc.getSpO2Value() ?? 0,
            step: calc.getStepValue() ?? 0,
            power: calc.getPowerValue() ?? 0,
            time: calc.getTimeStamp() ?? 0,
            hrFiltered: calc.getHRFiltered() ?? [],
            brFiltered: calc.getBRFiltered() ?? [],
            isWearing: calc.getIsWearing() == 1 || calc.getIsWearing() == true,
            rawData: calc.getRawData() ?? [],
            type: calc.getType() ?? 0,
            fftOut: calc.getFFTOut() ?? [],
            petPose: calc.getPetPoseValue(),
          );

          _hasPendingStateUpdate = true;
          _scheduleBatchUpdate();
          // _lastUIUpdate[device.remoteId] = now;

          // ✅ Debug：確認已加入待處理佇列
          devLog(
            '批次暫存',
            '✅ [${device.platformName}] 已加入待處理佇列，目前共 ${_pendingHealthUpdates.length} 筆',
          );
        } catch (e) {
          devLog('SDK處理', '❌ 處理資料時發生錯誤: $e');
        }
      });

      subMap[c.uuid] = sub;
      devLog('Notify', '✅ [${device.platformName}] ${c.uuid} 已開啟監聽');
      state = state.copyWith();
    } catch (e) {
      devLog('Notify', '開啟失敗: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔧 工具方法區
  // ═══════════════════════════════════════════════════════════════════════════

  /// 載入指定裝置服務（若已快取則直接返回）
  Future<void> ensureServices(BluetoothDevice device) async {
    if (_servicesCache.containsKey(device.remoteId)) return;
    try {
      final svcs = await device.discoverServices();
      _servicesCache[device.remoteId] = svcs;
      devLog('服務快取', 'device=${device.platformName} 服務數=${svcs.length}');
    } catch (e) {
      devLog('服務載入', '載入失敗: $e');
    }
  }

  /// 產生時間同步指令
  Uint8List getTimeSyncCommand() {
    // 1. 獲取當前時間戳 (毫秒)，並除以 10
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 10;

    // 2. 使用 ByteData 來處理位元運算
    final byteData = ByteData(8)..setInt64(0, timestamp, Endian.little);

    // 3. 根據文件規格組合 byte array
    final command = Uint8List(6);
    command[0] = 0xfc; // 指令 Header
    command[1] = byteData.getUint8(0);
    command[2] = byteData.getUint8(1);
    command[3] = byteData.getUint8(2);
    command[4] = byteData.getUint8(3);
    command[5] = byteData.getUint8(4);

    devLog('時間同步', '產生的指令: $command');
    return command;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔌 裝置斷線管理區
  // ═══════════════════════════════════════════════════════════════════════════

  /// 從指定裝置斷線
  ///
  /// ⚠️ 策略說明：
  /// - 已註解掉「斷線前補傳資料」的邏輯
  /// - 斷線時【不進行】最後資料補傳
  /// - 直接清理該裝置的所有資源
  Future<void> disconnectFromDevice(BluetoothDevice device) async {
    try {
      // ❌ 已停用：斷線前立即處理該裝置的待處理資料
      // 📝 使用者選擇：斷線時不補傳最後一筆資料
      // if (_pendingHealthUpdates.containsKey(device.remoteId)) {
      //   final data = {device.remoteId: _pendingHealthUpdates[device.remoteId]!};
      //   _ref.read(perDeviceHealthProvider.notifier).batchUpdate(data);
      //   _pendingHealthUpdates.remove(device.remoteId);
      //   devLog('斷線', '✅ 已送出 ${device.platformName} 的最後健康資料');
      // }

      // 🔇 取消連線狀態監聽器
      await _connectionSubscriptions[device.remoteId]?.cancel();
      _connectionSubscriptions.remove(device.remoteId);

      // 🔌 執行斷線
      await device.disconnect();

      // 🧹 清理該裝置的所有資源
      _removeDeviceFromConnected(device);

      devLog(
        '斷線',
        '✅ 已與 ${device.platformName} 斷線。目前連線數: ${state.connectedDevices.length}',
      );
    } catch (e) {
      devLog('斷線', '從 ${device.platformName} 斷線時發生錯誤: $e');
      // 🛡️ 即使斷線失敗，也要從列表中移除
      _removeDeviceFromConnected(device);
    }
  }

  /// 斷開所有裝置的連線
  ///
  /// ⚠️ 策略說明：
  /// - 已註解掉「批次補傳所有待處理資料」的邏輯
  /// - 斷線時【不進行】批次補傳
  /// - 直接清理所有裝置資源
  Future<void> disconnectAll() async {
    devLog('[斷線管理]', '🔌 開始執行全部斷線');

    // 1. 先取得所有設備 ID
    final deviceIds = state.connectedDevices.keys.toList();

    // 2. 逐一斷線
    for (final deviceId in deviceIds) {
      final device = state.connectedDevices[deviceId];
      if (device != null) {
        try {
          await device.disconnect();
          devLog('[斷線管理]', '✅ 已斷線: $deviceId');
        } catch (e) {
          devLog('[斷線管理]', '❌ 斷線失敗: $deviceId - $e');
        }
      }
    }

    // 3. ⭐ 關鍵：清空所有狀態
    state = BluetoothMultiConnectionState(
      connectedDevices: {},
      scanResults: [],
      isScanning: false,
    );

    // 4. ⭐ 清空 services cache
    _servicesCache.clear();

    // 5. ⭐ 手動清理所有設備的健康數據 Provider
    // for (final deviceId in deviceIds) {
    //   _ref.invalidate(batchHealthUpdaterProvider(deviceId));
    // }

    _ref.read(batchHealthUpdaterProvider).clearAll(deviceIds);

    devLog('[斷線管理]', '🎉 全部斷線完成，所有狀態已清理');
  }

  /// 從連線列表中移除裝置，並清理相關資源
  ///
  /// 🧹 清理項目：
  /// - 裝置連線狀態
  /// - 服務快取
  /// - SDK 計算器
  /// - Notify/Read 訂閱與資料
  /// - 待處理的健康資料
  /// - UI 更新時間記錄
  /// - Provider 中的裝置資料
  void _removeDeviceFromConnected(BluetoothDevice device) {
    // 🗑️ 從連線列表移除
    final newDevices = Map<DeviceIdentifier, BluetoothDevice>.from(
      state.connectedDevices,
    )..remove(device.remoteId);

    // 🗑️ 清除服務快取
    _servicesCache.remove(device.remoteId);

    // 🗑️ 清理 SDK 計算器（呼叫 dispose 釋放資源）
    final calc = _calculators.remove(device.remoteId);
    if (calc != null) {
      calc.dispose(device.remoteId.toString());
    }

    // 🗑️ 清除 per-device 的 notify/read/sub
    _notifyValues.remove(device.remoteId);
    _readValues.remove(device.remoteId);
    final subs = _notifySubs.remove(device.remoteId);
    if (subs != null) {
      for (final s in subs.values) {
        s.cancel();
      }
    }

    // 🗑️ 清除待處理的健康資料更新
    _pendingHealthUpdates.remove(device.remoteId);

    // 🗑️ 清除 UI 更新時間記錄
    // _lastUIUpdate.remove(device.remoteId);

    // 🗑️ 從 provider 移除該裝置
    _ref.read(batchHealthUpdaterProvider).removeDevice(device.remoteId);

    // 🔄 更新狀態
    state = state.copyWith(connectedDevices: newDevices);

    // 🔇 取消連線監聽
    _connectionSubscriptions[device.remoteId]?.cancel();
    _connectionSubscriptions.remove(device.remoteId);
  }

  /// 取得特定裝置的連線狀態
  bool isDeviceConnected(BluetoothDevice device) {
    return state.connectedDevices.containsKey(device.remoteId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🧹 資源清理區
  // ═══════════════════════════════════════════════════════════════════════════

  /// 在 App 生命週期結束時,清理所有連線與資源
  ///
  /// 🗑️ 清理項目：
  /// - 掃描相關資源
  /// - 批次更新 Timer
  /// - 藍牙狀態監聽
  /// - 所有連線監聽
  /// - 所有裝置連線
  /// - 所有 SDK 計算器
  /// - 重置狀態
  void cleanup() {
    devLog('清理', '開始清理藍牙資源...');

    // 🔍 停止掃描相關
    _scanTimer?.cancel();
    _scanResultsSubscription?.cancel();

    // ⏱️ 取消批次更新 timer
    _batchUpdateTimer?.cancel();
    _batchUpdateTimer = null;

    // 🗑️ 清空待處理的更新與時間記錄
    _pendingHealthUpdates.clear();
    // _lastUIUpdate.clear();

    // 🎧 取消藍牙狀態監聽
    _adapterStateSubscription?.cancel();

    // 🔇 取消所有連線狀態監聽
    for (var sub in _connectionSubscriptions.values) {
      sub.cancel();
    }
    _connectionSubscriptions.clear();

    // 🔌 斷開所有裝置連線
    for (var device in state.connectedDevices.values) {
      try {
        device.disconnect();
      } catch (e) {
        devLog('清理', '清理時斷線錯誤: $e');
      }
    }

    // 🧮 清理所有 SDK 計算器
    for (var calc in _calculators.values) {
      calc.dispose('cleanup');
    }
    _calculators.clear();

    // 🔄 重置狀態
    state = const BluetoothMultiConnectionState();
    devLog('清理', '✅ 已清理所有藍牙連線。');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔐 私有輔助方法區
  // ═══════════════════════════════════════════════════════════════════════════

  /// 請求藍牙權限
  Future<bool> _requestPermissions() async {
    try {
      if (Platform.isAndroid) {
        // Android 需要多個權限
        final statuses = await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.locationWhenInUse,
        ].request();

        return statuses[Permission.bluetoothScan]!.isGranted &&
            statuses[Permission.bluetoothConnect]!.isGranted;
      } else if (Platform.isIOS) {
        // iOS 只需要藍牙權限
        return await Permission.bluetooth.request().isGranted;
      }
      return false;
    } catch (e) {
      devLog('權限', '請求權限時發生錯誤: $e');
      return false;
    }
  }

  /// 檢查藍牙是否已開啟
  Future<bool> _checkBluetoothEnabled() async {
    try {
      final adapterState = await FlutterBluePlus.adapterState.first;
      return adapterState == BluetoothAdapterState.on;
    } catch (e) {
      devLog('藍牙', '檢查藍牙狀態時發生錯誤: $e');
      return false;
    }
  }

  @override
  void dispose() {
    cleanup();
    super.dispose();
  }
}
