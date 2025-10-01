import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_itri_hrbr/helper/devLog.dart';
import 'package:flutter_itri_hrbr/model/health_data.dart';
import 'package:flutter_itri_hrbr/provider/health_provider.dart';
import 'package:flutter_itri_hrbr/provider/per_device_health_provider.dart';
import 'package:flutter_itri_hrbr/services/HealthCalculate.dart';
import 'package:flutter_itri_hrbr/services/data_Classifier_Service.dart';
import 'package:flutter_itri_hrbr/utils/performance_monitor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:permission_handler/permission_handler.dart';

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

/// Riverpod Provider，讓 App 的任何地方都能取用我們的 BluetoothManager
final bluetoothManagerProvider =
    StateNotifierProvider<BluetoothManager, BluetoothMultiConnectionState>((
      ref,
    ) {
      final manager = BluetoothManager(ref);
      ref.onDispose(manager.cleanup);
      return manager;
    });

/// 藍牙「大腦」：負責所有藍牙相關的狀態與邏輯，完全獨立於 UI
class BluetoothManager extends StateNotifier<BluetoothMultiConnectionState> {
  BluetoothManager(this._ref) : super(const BluetoothMultiConnectionState()) {
    _initBluetoothStateListener();
  }

  final Ref _ref;

  // NEW: 每裝置一個 HealthCalculate
  final Map<DeviceIdentifier, HealthCalculate> _calculators = {};

  HealthCalculate _getCalculator(DeviceIdentifier id) {
    return _calculators.putIfAbsent(id, () => HealthCalculate(3));
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

  HealthCalculate? _healthCalculator;

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

    _batchUpdateTimer ??= Timer(const Duration(milliseconds: 100), () {
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
    try {
      await c.setNotifyValue(true);
      final calc = _getCalculator(device.remoteId);
      final sub = c.lastValueStream.listen((value) async {
        (_notifyValues[device.remoteId] ??= {})[c.uuid] = value;

        if (!_ref.mounted) return;

        _ref
            .read(mutiFilteredFirstRawDataFamily(device.remoteId).notifier)
            .mutiFilterData(value, device.remoteId, _ref);

        final dataValue = _ref.read(
          mutiFilteredFirstRawDataFamily(device.remoteId),
        );

        await calc.splitPackage(Uint8List.fromList(dataValue.splitRawData));
        if (!_ref.mounted) return;

        // 創建 HealthData 物件並加入待處理佇列
        _pendingHealthUpdates[device.remoteId] = HealthData(
          splitRawData: dataValue.splitRawData,
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

        _hasPendingStateUpdate = true;

        _scheduleBatchUpdate();

        // _ref
        //     .read(perDeviceHealthProvider.notifier)
        //     .patchDevice(
        //       id: device.remoteId,
        //       hr: calc.getHRValue(),
        //       br: calc.getBRValue(),
        //       gyroX: calc.getGyroValueX(),
        //       gyroY: calc.getGyroValueY(),
        //       gyroZ: calc.getGyroValueZ(),
        //       temp: (calc.getTempValue() is num)
        //           ? (calc.getTempValue() as num).toDouble()
        //           : 0,
        //       hum: (calc.getHumValue() is num)
        //           ? (calc.getHumValue() as num).toDouble()
        //           : 0,
        //       spO2: calc.getSpO2Value(),
        //       step: calc.getStepValue(),
        //       power: calc.getPowerValue(),
        //       time: calc.getTimeStamp(),
        //       hrFiltered: (calc.getHRFiltered() is List)
        //           ? (calc.getHRFiltered() as List)
        //                 .map((e) => (e as num).toDouble())
        //                 .toList()
        //           : null,
        //       brFiltered: (calc.getBRFiltered() is List)
        //           ? (calc.getBRFiltered() as List)
        //                 .map((e) => (e as num).toDouble())
        //                 .toList()
        //           : null,
        //       isWearing:
        //           calc.getIsWearing() == 1 || calc.getIsWearing() == true,
        //       rawData: (calc.getRawData() is List)
        //           ? (calc.getRawData() as List)
        //                 .map((e) => (e as num).toInt())
        //                 .toList()
        //           : null,
        //       type: calc.getType(),
        //       fftOut: (calc.getFFTOut() is List)
        //           ? (calc.getFFTOut() as List)
        //                 .map((e) => (e as num).toDouble())
        //                 .toList()
        //           : null,
        //       petPose: calc.getPetPoseValue(),
        //     );
        // if (_ref.mounted) {
        //   state = state.copyWith();
        // }
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

  // Future<void> _processAndUpsample(
  //   List<int> currentPacket,
  // ) async {
  //   // 使用系統時間生成連續的時間戳，避免設備時間戳跳躍問題
  //   final baseTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 10;

  //   // 直接處理當前封包
  //   await _processSinglePacketWithTimestamp(currentPacket, baseTimestamp);
  // }

  // Future<void> _processSinglePacketWithTimestamp(
  //   List<int> packetData,
  //   int baseTimestamp,
  // ) async {
  //   if (_healthCalculator == null) return;

  //   // ======= 步驟1: 數據分類篩選 =======
  //   // 使用你現有的智慧篩選器，自動區分第一組/第二組/雜訊
  //   final dataType = _ref
  //       .read(filteredFirstRawDataProvider.notifier)
  //       .mutiFilterData(packetData, _ref);

  //   // ======= 步驟2: 只處理第一組數據 =======
  //   if (dataType == DataType.first) {
  //     // 從Provider取得篩選後的第一組數據
  //     final dataValue = _ref.read(filteredFirstRawDataProvider);
  //     final currentPacket = List<int>.from(dataValue.splitRawData);
  //     final currentTimestamp = _bytesToTimestamp(currentPacket);

  //     // 2️⃣ 送當前筆原始數據 (current)

  //     // 傳一筆 HR => 52
  //     await _healthCalculator!.splitPackage(
  //       Uint8List.fromList(currentPacket),
  //     );
  //     // await _healthCalculator!.splitPackage(
  //     //   Uint8List.fromList(currentPacket),
  //     // );
  //     // // 傳二筆 HR => 105

  //     devLog('SDK送出', '原始數據=$currentPacket');
  //     devLog('SDK送出', '原始 ts=$currentTimestamp');

  //     // 更新UI
  //     // await _updateUIAndProvider();

  //     // 更新緩存供下次使用
  //     // _firstGroupPacket = currentPacket;
  //     // _firstGroupTimestamp = currentTimestamp;
  //   } else if (dataType == DataType.second) {
  //     // 第二組數據：完全忽略，不送SDK，不加Provider
  //     devLog('數據過濾', '第二組數據已自動忽略');
  //   } else if (dataType == DataType.noise) {
  //     // 過渡期雜訊：完全忽略
  //     devLog('數據過濾', '過渡期雜訊已自動忽略');
  //   }
  // }

  /// 需要新增這個輔助方法來提取時間戳
  int _bytesToTimestamp(List<int> packet) {
    if (packet.length < 6) return 0;
    return packet[1] |
        (packet[2] << 8) |
        (packet[3] << 16) |
        (packet[4] << 24) |
        (packet[5] << 32);
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

  /// 斷開所有連線
  Future<void> disconnectAll() async {
    final devices = List<BluetoothDevice>.from(state.connectedDevices.values);

    for (final device in devices) {
      await disconnectFromDevice(device);
    }
    _calculators.clear();
  }

  /// 斷線時清理快取
  void _removeDeviceFromConnected(BluetoothDevice device) {
    final newDevices = Map<DeviceIdentifier, BluetoothDevice>.from(
      state.connectedDevices,
    )..remove(device.remoteId);
    _servicesCache.remove(device.remoteId);
    _calculators.remove(device.remoteId);

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

  /// 在 App 生命週期結束時，清理所有連線
  void cleanup() {
    devLog('', '開始清理藍牙資源...');

    // 停止掃描
    _scanTimer?.cancel();
    _scanResultsSubscription?.cancel();

    // 停止
    _batchUpdateTimer?.cancel();

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
    state = const BluetoothMultiConnectionState();
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
    cleanup();
    super.dispose();
  }
}
