import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_itri_hrbr/helper/devLog.dart';
import 'package:flutter_itri_hrbr/model/health_data.dart';
import 'package:flutter_itri_hrbr/provider/health_provider.dart';
import 'package:flutter_itri_hrbr/provider/per_device_health_provider.dart';
import 'package:flutter_itri_hrbr/services/HealthCalculate_Device_ID.dart';
import 'package:flutter_itri_hrbr/services/batch_data_processor.dart';
import 'package:flutter_itri_hrbr/services/data_Classifier_Service.dart';
import 'package:flutter_itri_hrbr/utils/performance_monitor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:permission_handler/permission_handler.dart';

/// 定義藍牙管理器需要維護的所有狀態
class BluetoothISOMultiConnectionState {
  /// 使用 Map 來儲存所有已連線的裝置，以 deviceId 為 key
  final Map<DeviceIdentifier, BluetoothDevice> connectedDevices;

  /// 當前掃描到的裝置列表
  final List<ScanResult> scanResults;

  /// 是否正在掃描
  final bool isScanning;

  const BluetoothISOMultiConnectionState({
    this.connectedDevices = const {},
    this.scanResults = const [],
    this.isScanning = false,
  });

  /// 方便複製並更新狀態的 copyWith 方法
  BluetoothISOMultiConnectionState copyWith({
    Map<DeviceIdentifier, BluetoothDevice>? connectedDevices,
    List<ScanResult>? scanResults,
    bool? isScanning,
  }) {
    return BluetoothISOMultiConnectionState(
      connectedDevices: connectedDevices ?? this.connectedDevices,
      scanResults: scanResults ?? this.scanResults,
      isScanning: isScanning ?? this.isScanning,
    );
  }
}

/// Riverpod Provider，讓 App 的任何地方都能取用我們的 BluetoothManager
final bluetoothManagerProvider =
    StateNotifierProvider<
      BluetoothISOManager,
      BluetoothISOMultiConnectionState
    >((
      ref,
    ) {
      final manager = BluetoothISOManager(ref);
      ref.onDispose(manager.cleanup);
      return manager;
    });

/// 藍牙「大腦」：負責所有藍牙相關的狀態與邏輯，完全獨立於 UI
class BluetoothISOManager
    extends StateNotifier<BluetoothISOMultiConnectionState> {
  BluetoothISOManager(this._ref)
    : super(const BluetoothISOMultiConnectionState()) {
    _initBluetoothStateListener();
    _initBatchProcessor(); // ✅ 新增
  }

  final Ref _ref;

  // NEW: 每裝置一個 HealthCalculateDeviceID
  final Map<DeviceIdentifier, HealthCalculateDeviceID> _calculators = {};

  HealthCalculateDeviceID _getCalculator(DeviceIdentifier id) {
    return _calculators.putIfAbsent(id, () => HealthCalculateDeviceID(3));
  }

  // 連線狀態監聽
  final Map<DeviceIdentifier, StreamSubscription<BluetoothConnectionState>>
  _connectionSubscriptions = {};

  // 服務快取
  final Map<DeviceIdentifier, List<BluetoothService>> _servicesCache = {};

  // 改成巢狀結構（依裝置分隔）
  final Map<DeviceIdentifier, Map<Guid, List<int>>> _notifyValues = {};
  final Map<DeviceIdentifier, Map<Guid, List<int>>> _readValues = {};
  final Map<DeviceIdentifier, Map<Guid, StreamSubscription<List<int>>>>
  _notifySubs = {};

  // 對外只讀
  Map<DeviceIdentifier, List<BluetoothService>> get servicesCache =>
      _servicesCache;

  // 用於掃描
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;

  // 用於監聽藍牙開關狀態
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;

  // 掃描計時器
  Timer? _scanTimer;

  HealthCalculateDeviceID? _healthCalculator;

  // ✅ 新增批次處理器
  BatchDataProcessor? _batchProcessor;
  StreamSubscription? _batchSubscription;
  StreamSubscription? _statsSubscription;

  // 在 BluetoothISOManager 類別中新增
  final Map<DeviceIdentifier, DateTime> _lastUIUpdate = {};
  static const _uiUpdateInterval = Duration(milliseconds: 100); // 1Hz 更新

  // 取得資料的 helper
  List<int>? getNotifyValue(DeviceIdentifier id, Guid uuid) =>
      _notifyValues[id]?[uuid];
  List<int>? getReadValue(DeviceIdentifier id, Guid uuid) =>
      _readValues[id]?[uuid];
  bool isNotifying(DeviceIdentifier id, Guid uuid) =>
      _notifySubs[id]?.containsKey(uuid) ?? false;

  //!--------------優化部分---------------

  // 新增：批次更新相關
  Timer? _batchUpdateTimer;
  final Map<DeviceIdentifier, HealthData> _pendingHealthUpdates = {};
  bool _hasPendingStateUpdate = false;

  /// 新增：批次更新排程
  void _scheduleBatchUpdate() {
    // 添加監控
    PerformanceMonitor().logUpdate('health_updates');

    _batchUpdateTimer ??= Timer(const Duration(milliseconds: 1500), () {
      if (_pendingHealthUpdates.isNotEmpty) {
        // 使用批次更新方法
        _ref
            .read(perDeviceHealthProvider.notifier)
            .batchUpdate(_pendingHealthUpdates);

        // 清空待處理的更新
        _pendingHealthUpdates.clear();
      }

      if (_hasPendingStateUpdate) {
        state = state.copyWith();
        _hasPendingStateUpdate = false;
      }

      _batchUpdateTimer = null;
    });
  }

  //-------------------------------------

  // ✅ 新增：初始化批次處理器
  Future<void> _initBatchProcessor() async {
    // ✅ 防止重複初始化
    if (_batchProcessor != null) {
      devLog('批次處理器', '⚠️ 已存在，跳過重複初始化');
      return;
    }

    _batchProcessor = BatchDataProcessor();

    // 啟動 Isolate,設定批次參數
    await _batchProcessor!.start(
      batchInterval: Duration(milliseconds: 100),
      batchSize: 10,
    );

    // 監聽批次資料
    _batchSubscription = _batchProcessor!.batchStream.listen((batches) {
      _processBatches(batches);
    });

    // 監聽統計資訊(可選,用於除錯)
    _statsSubscription = _batchProcessor!.statsStream.listen((stats) {
      devLog(
        '批次統計',
        '收到: ${stats['totalReceived']}, '
            '已處理: ${stats['totalSent']}, '
            '緩衝: ${stats['buffered']}, '
            '設備數: ${stats['devices']}',
      );
    });

    devLog('批次處理器', '✅ 初始化完成');
  }

  /// ✅ 修改：批次處理方法
  Future<void> _processBatches(
    Map<String, List<BatchDataItem>> batches,
  ) async {
    final processingStart = DateTime.now();

    devLog('批次處理', '收到批次：${batches.length} 個設備');

    // 清空待更新列表
    _pendingHealthUpdates.clear();

    for (final entry in batches.entries) {
      final deviceIdStr = entry.key;
      final dataItems = entry.value;

      devLog('批次處理', '  - $deviceIdStr: ${dataItems.length} 筆資料');

      // 找到對應的設備
      final deviceId = DeviceIdentifier(deviceIdStr);

      if (!_calculators.containsKey(deviceId)) {
        devLog('批次處理', '  ⚠️  找不到 calculator: $deviceIdStr');
        continue;
      }

      final calc = _calculators[deviceId]!;

      // ✅ 關鍵改動：改用非同步呼叫（不阻塞主線程）
      for (final item in dataItems) {
        try {
          // ⚡ 使用 unawaited 避免阻塞
          // 傳入 deviceId 確保數據不會錯亂

          unawaited(
            calc.splitPackage(
              Uint8List.fromList(item.bytes),
              deviceId.toString(), // ← 傳入設備 ID
            ),
          );
        } catch (e) {
          devLog('批次處理錯誤', '$deviceIdStr: $e');
        }
      }

      // ✅ 檢查是否該更新 UI（節流機制）
      final now = DateTime.now();
      final lastUpdate = _lastUIUpdate[deviceId];

      if (lastUpdate == null ||
          now.difference(lastUpdate) >= _uiUpdateInterval) {
        // 🔥 重要：這裡取得的是 SDK 累積後的結果
        // SDK 會在累積 16 筆後才開始輸出有效數據
        _pendingHealthUpdates[deviceId] = HealthData(
          splitRawData: dataItems.last.bytes,
          hr: calc.getHRValue() ?? 0,
          br: calc.getBRValue() ?? 0,
          gyroX: calc.getGyroValueX() ?? 0,
          gyroY: calc.getGyroValueY() ?? 0,
          gyroZ: calc.getGyroValueZ() ?? 0,
          temp: (calc.getTempValue() is num)
              ? (calc.getTempValue() as num).toDouble()
              : 0.0,
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

        _lastUIUpdate[deviceId] = now;
      }
    }

    // ✅ 批次更新所有需要更新的設備（只觸發一次 rebuild）
    if (_pendingHealthUpdates.isNotEmpty) {
      _ref
          .read(perDeviceHealthProvider.notifier)
          .batchUpdate(_pendingHealthUpdates);

      final processingTime = DateTime.now()
          .difference(processingStart)
          .inMilliseconds;
      devLog(
        '批次處理',
        '✅ 完成：${_pendingHealthUpdates.length} 個設備, '
            '耗時: ${processingTime}ms',
      );

      _pendingHealthUpdates.clear();
    }
  }

  /// 初始化藍牙狀態監聽器
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

  /// 開始掃描藍牙裝置
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      // 檢查權限
      if (!await _requestPermissions()) {
        devLog('', '權限不足，無法掃描');
        return;
      }

      // 檢查藍牙是否開啟
      if (!await _checkBluetoothEnabled()) {
        devLog('', '藍牙未開啟，無法掃描');
        return;
      }

      // 如果正在掃描，先停止舊的掃描
      if (state.isScanning) {
        await stopScan();
      }

      // 清空舊的掃描結果，並將狀態設為掃描中
      state = state.copyWith(scanResults: [], isScanning: true);

      // 開始監聽掃描結果流
      _scanResultsSubscription = FlutterBluePlus.scanResults.listen(
        (results) {
          // 過濾掉沒有名稱的裝置，並更新狀態
          final filteredResults = results
              .where((r) => r.device.platformName.isNotEmpty)
              .toList();

          // 排序：依據 RSSI 強度，訊號較強的排前面
          filteredResults.sort((a, b) => b.rssi.compareTo(a.rssi));

          state = state.copyWith(scanResults: filteredResults);
        },
        onError: (error) {
          devLog('', '掃描錯誤: $error');
        },
      );

      // 正式開始掃描
      await FlutterBluePlus.startScan(timeout: timeout);

      // 設定計時器，在超時後自動停止
      _scanTimer?.cancel();
      _scanTimer = Timer(timeout, () {
        if (state.isScanning) {
          stopScan();
        }
      });
    } catch (e) {
      devLog('', '開始掃描時發生錯誤: $e');
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
      devLog('', '掃描已停止');
    } catch (e) {
      devLog('', '停止掃描時發生錯誤: $e');
    }
  }

  /// 連線到指定裝置
  Future<bool> connectToDevice(BluetoothDevice device) async {
    // 防止重複連線
    if (state.connectedDevices.containsKey(device.remoteId)) {
      devLog('', '${device.platformName} 已經連線了。');
      return false;
    }

    // 先建立監聽器
    final subscription = device.connectionState.listen(
      (connectionState) {
        if (connectionState == BluetoothConnectionState.disconnected) {
          devLog('', '${device.platformName} 意外斷線。');
          // 從連線列表中移除
          _removeDeviceFromConnected(device);
        }
        if (connectionState == BluetoothConnectionState.connected) {
          devLog(
            'connectToDevice',
            '${device.platformName} 連線成功，HealthCalculate 已初始化。',
          );
        }
      },
      onError: (error) {
        devLog('', '連線狀態監聽錯誤: $error');
      },
    );

    try {
      // 嘗試連線
      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false, // 不使用自動重連
      );

      // 連線成功後，儲存監聽器和裝置
      _connectionSubscriptions[device.remoteId] = subscription;

      final newDevices = Map<DeviceIdentifier, BluetoothDevice>.from(
        state.connectedDevices,
      );
      newDevices[device.remoteId] = device;
      state = state.copyWith(connectedDevices: newDevices);

      devLog(
        '',
        '成功連線到 ${device.platformName}。目前連線數: ${state.connectedDevices.length}',
      );
      devLog('連線數量', _connectionSubscriptions.toString());

      // 可選：發現服務
      try {
        final svcs = await device.discoverServices();
        _servicesCache[device.remoteId] = svcs; // 加入快取 (多裝置隔離)
        devLog('', '已發現 ${device.platformName} 的服務');
      } catch (e) {
        devLog('', '發現服務時發生錯誤: $e');
      }

      return true;
    } catch (e) {
      devLog('', '連線到 ${device.platformName} 失敗: $e');
      await subscription.cancel();
      _connectionSubscriptions.remove(device.remoteId);
      return false;
    }
  }

  /// 讀取特徵
  Future<void> readCharacteristic(
    BluetoothDevice device,
    BluetoothCharacteristic c,
  ) async {
    try {
      final v = await c.read();
      (_readValues[device.remoteId] ??= {})[c.uuid] = v;
      devLog('Read', '[${device.platformName}] ${c.uuid} => $v');
      state = state.copyWith();
    } catch (e) {
      devLog('Read失敗', '$e');
    }
  }

  /// 寫入特徵（範例：可改為參數 bytes）
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
      devLog('Write失敗', '$e');
    }
  }

  /// 開始監聽特徵的通知
  Future<void> toggleNotify(
    BluetoothDevice device,
    BluetoothCharacteristic c,
  ) async {
    final subMap = _notifySubs.putIfAbsent(device.remoteId, () => {});
    if (subMap.containsKey(c.uuid)) {
      await subMap[c.uuid]?.cancel();
      await c.setNotifyValue(false);
      subMap.remove(c.uuid);
      devLog('Notify關閉', '[${device.platformName}] ${c.uuid}');
      state = state.copyWith();
      return;
    }

    // // 在 toggleNotify 中
    // int callCount = 0;
    // final totalStopwatch = Stopwatch(); // 總時間

    try {
      await c.setNotifyValue(true);

      final calc = _getCalculator(device.remoteId);

      final sub = c.lastValueStream.listen((value) async {
        // callCount++;

        (_notifyValues[device.remoteId] ??= {})[c.uuid] = value;

        if (!_ref.mounted) return;

        // ✅ 第一層檢查：原始資料
        if (value.isEmpty || value.length < 17) {
          return;
        }

        // ✅ 資料篩選（保留你原有的邏輯）
        final dataType = _ref
            .read(mutiFilteredFirstRawDataFamily(device.remoteId).notifier)
            .mutiFilterData(value, device.remoteId, _ref);

        if (dataType != DataType.first) {
          devLog('dataType', 'dataType = $dataType 忽略資料');
          return;
        }

        final dataValue = _ref.read(
          mutiFilteredFirstRawDataFamily(device.remoteId),
        );

        // ✅ 第二層檢查：篩選後的資料
        if (dataValue.splitRawData.isEmpty ||
            dataValue.splitRawData.length < 17) {
          devLog(
            '數據過濾',
            '⚠️ 篩選後資料為空或長度不足 (${dataValue.splitRawData.length})，已忽略',
          );
          return;
        }

        // final singleCallStopwatch = Stopwatch()..start();

        // ✅✅✅ 關鍵改動：不再立即處理，而是轉發給 Isolate
        _batchProcessor?.addData(
          device.remoteId.toString(),
          dataValue.splitRawData,
        );

        // singleCallStopwatch.stop();

        // devLog(
        //   '效能',
        //   '第$callCount次: ${singleCallStopwatch.elapsedMilliseconds}ms',
        // );

        // ❌ 移除：不再立即呼叫 SDK 和更新 Provider
        // await calc.splitPackage(Uint8List.fromList(dataValue.splitRawData));
        // _pendingHealthUpdates[device.remoteId] = HealthData(...);
        // _scheduleBatchUpdate();
      });

      subMap[c.uuid] = sub;
      devLog('Notify開啟', '[${device.platformName}] ${c.uuid}');
      state = state.copyWith();
    } catch (e) {
      devLog('Notify失敗', '$e');
    }
  }

  /// 載入指定裝置服務（若已快取則直接返回）
  Future<void> ensureServices(BluetoothDevice device) async {
    if (_servicesCache.containsKey(device.remoteId)) return;
    try {
      final svcs = await device.discoverServices();
      _servicesCache[device.remoteId] = svcs;
      devLog('服務快取', 'device=${device.platformName} 服務數=${svcs.length}');
    } catch (e) {
      devLog('服務載入失敗', e.toString());
    }
  }

  // --- 新增：將文件中的 Java/Kotlin 時間轉換邏輯翻譯成 Dart ---
  Uint8List getTimeSyncCommand() {
    // 1. 獲取當前時間戳 (毫秒)，並除以 10
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 10;

    // 2. 使用 ByteData 來處理位元運算，這比手動位移更安全可靠
    final byteData = ByteData(8)..setInt64(0, timestamp, Endian.little);

    // 3. 根據文件規格組合 byte array
    final command = Uint8List(6);
    command[0] = 0xfc; // 指令 Header
    command[1] = byteData.getUint8(0); // 時間戳的第 0-7 位
    command[2] = byteData.getUint8(1); // 時間戳的第 8-15 位
    command[3] = byteData.getUint8(2); // 時間戳的第 16-23 位
    command[4] = byteData.getUint8(3); // 時間戳的第 24-31 位
    command[5] = byteData.getUint8(4); // 時間戳的第 32-39 位

    devLog('時間同步', '產生的指令: $command');
    return command;
  }

  /// 從指定裝置斷線
  Future<void> disconnectFromDevice(BluetoothDevice device) async {
    try {
      // ✅ 斷線前立即發送該裝置的緩衝資料
      //  _batchProcessor?.flush();

      // 取消監聽器
      await _connectionSubscriptions[device.remoteId]?.cancel();
      _connectionSubscriptions.remove(device.remoteId);

      // 斷線
      await device.disconnect();

      // 從狀態中移除
      _removeDeviceFromConnected(device);

      devLog(
        '',
        '已與 ${device.platformName} 斷線。目前連線數: ${state.connectedDevices.length}',
      );
    } catch (e) {
      devLog('', '從 ${device.platformName} 斷線時發生錯誤: $e');
      // 即使斷線失敗，也要從列表中移除
      _removeDeviceFromConnected(device);
    }
  }

  /// 斷開所有裝置的連線
  Future<void> disconnectAll() async {
    // ✅ 斷線前立即處理所有緩衝資料
    // _batchProcessor?.flush();
    await Future.delayed(Duration(milliseconds: 200));

    final devices = List<BluetoothDevice>.from(state.connectedDevices.values);

    for (final device in devices) {
      await disconnectFromDevice(device);
    }

    // ✅ 清理所有 calculator（每個都會呼叫 dispose）
    _calculators.clear();
  }

  /// ✅ 修改：從連線列表中移除裝置，並清理相關資源
  void _removeDeviceFromConnected(BluetoothDevice device) {
    final newDevices = Map<DeviceIdentifier, BluetoothDevice>.from(
      state.connectedDevices,
    )..remove(device.remoteId);
    _servicesCache.remove(device.remoteId);

    // ✅ 修改：清理時傳入 deviceId
    final calc = _calculators.remove(device.remoteId);
    if (calc != null) {
      calc.dispose(device.remoteId.toString()); // ← 傳入 deviceId
    }

    // 清除 per-device notify/read/sub
    _notifyValues.remove(device.remoteId);
    _readValues.remove(device.remoteId);
    final subs = _notifySubs.remove(device.remoteId);
    if (subs != null) {
      for (final s in subs.values) {
        s.cancel();
      }
    }

    _ref.read(perDeviceHealthProvider.notifier).removeDevice(device.remoteId);
    state = state.copyWith(connectedDevices: newDevices);
    _connectionSubscriptions[device.remoteId]?.cancel();
    _connectionSubscriptions.remove(device.remoteId);
  }

  /// 取得特定裝置的連線狀態
  bool isDeviceConnected(BluetoothDevice device) {
    return state.connectedDevices.containsKey(device.remoteId);
  }

  /// 在 App 生命週期結束時,清理所有連線
  void cleanup() {
    devLog('', '開始清理藍牙資源...');

    // 停止掃描
    _scanTimer?.cancel();
    _scanResultsSubscription?.cancel();

    // 停止
    _batchUpdateTimer?.cancel();

    // ✅ 完整清理批次處理器
    _batchSubscription?.cancel();
    _batchSubscription = null;
    _statsSubscription?.cancel();
    _statsSubscription = null;
    _batchProcessor?.dispose(); // 呼叫 dispose 清理 Isolate
    _batchProcessor = null;

    // 取消藍牙狀態監聽
    _adapterStateSubscription?.cancel();

    // 取消所有連線狀態監聽
    for (var sub in _connectionSubscriptions.values) {
      sub.cancel();
    }
    _connectionSubscriptions.clear();

    // 斷開所有裝置連線
    for (var device in state.connectedDevices.values) {
      try {
        device.disconnect();
      } catch (e) {
        devLog('', '清理時斷線錯誤: $e');
      }
    }

    // 重置狀態
    state = const BluetoothISOMultiConnectionState();
    devLog('', '已清理所有藍牙連線。');
  }

  // --- 私有輔助方法 ---

  /// 請求藍牙權限
  Future<bool> _requestPermissions() async {
    try {
      if (Platform.isAndroid) {
        // Android 需要多個權限
        final statuses = await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.locationWhenInUse, // Android 12 以下可能需要位置權限
        ].request();

        return statuses[Permission.bluetoothScan]!.isGranted &&
            statuses[Permission.bluetoothConnect]!.isGranted;
      } else if (Platform.isIOS) {
        // iOS 只需要藍牙權限
        return await Permission.bluetooth.request().isGranted;
      }
      return false;
    } catch (e) {
      devLog('', '請求權限時發生錯誤: $e');
      return false;
    }
  }

  /// 檢查藍牙是否已開啟
  Future<bool> _checkBluetoothEnabled() async {
    try {
      final adapterState = await FlutterBluePlus.adapterState.first;
      return adapterState == BluetoothAdapterState.on;
    } catch (e) {
      devLog('', '檢查藍牙狀態時發生錯誤: $e');
      return false;
    }
  }

  @override
  void dispose() {
    // ✅ 在 StateNotifier dispose 前先清理批次處理器
    _batchSubscription?.cancel();
    _statsSubscription?.cancel();
    _batchProcessor?.dispose();

    cleanup();
    super.dispose();
  }
}
