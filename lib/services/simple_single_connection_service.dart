import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_itri_hrbr/helper/devLog.dart';
import 'package:flutter_itri_hrbr/provider/health_provider.dart';
import 'package:flutter_itri_hrbr/services/HealthCalculate_Device_ID.dart';
import 'package:flutter_itri_hrbr/services/data_Classifier_Service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:permission_handler/permission_handler.dart';

// ⭐ 測試功能（移除時註解掉此行）
import 'package:flutter_itri_hrbr/ble_test/ble_test.dart';

// ═══════════════════════════════════════════════════════════════════════════
// State 類別
// ═══════════════════════════════════════════════════════════════════════════

class SimpleConnectionState {
  final BluetoothDevice? connectedDevice;
  final List<BluetoothService> services;
  final Map<Guid, List<int>> readValues;
  final Map<Guid, List<int>> notifyValues;
  final bool isScanning;

  const SimpleConnectionState({
    this.connectedDevice,
    this.services = const [],
    this.readValues = const {},
    this.notifyValues = const {},
    this.isScanning = false,
  });

  bool get isConnected => connectedDevice != null;

  SimpleConnectionState copyWith({
    BluetoothDevice? connectedDevice,
    List<BluetoothService>? services,
    Map<Guid, List<int>>? readValues,
    Map<Guid, List<int>>? notifyValues,
    bool? isScanning,
    bool clearDevice = false,
  }) {
    return SimpleConnectionState(
      connectedDevice: clearDevice
          ? null
          : (connectedDevice ?? this.connectedDevice),
      services: services ?? this.services,
      readValues: readValues ?? this.readValues,
      notifyValues: notifyValues ?? this.notifyValues,
      isScanning: isScanning ?? this.isScanning,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Service Provider
// ═══════════════════════════════════════════════════════════════════════════

final simpleConnectionServiceProvider =
    StateNotifierProvider<SimpleConnectionService, SimpleConnectionState>((
      ref,
    ) {
      return SimpleConnectionService(ref);
    });

// ═══════════════════════════════════════════════════════════════════════════
// Service 類別
// ═══════════════════════════════════════════════════════════════════════════

class SimpleConnectionService extends StateNotifier<SimpleConnectionState> {
  final Ref ref;

  // SDK 相關
  HealthCalculateDeviceID? _healthCalculator;
  String? _currentDeviceId;

  // 訂閱管理
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  final Map<Guid, StreamSubscription<List<int>>> _notifySubscriptions = {};

  int _dataCount = 0;
  int _reSentDataCount = 0;
  int _currentDataCount = 0;

  // ⭐ 測試功能（移除時註解掉此區塊）
  final ReSentTestService _testService = ReSentTestService();
  ReSentTestService get testService => _testService;
  
  // ⭐ 時間戳追蹤（用於除錯）
  DateTime? _lastDisconnectTime;      // 上次斷線時間
  DateTime? _lastConnectTime;         // 這次連線時間
  DateTime? _lastTimeSyncWriteTime;   // 寫入 FFF5 的時間戳時間
  
  DateTime? get lastDisconnectTime => _lastDisconnectTime;
  DateTime? get lastConnectTime => _lastConnectTime;
  DateTime? get lastTimeSyncWriteTime => _lastTimeSyncWriteTime;
  // ⭐ 測試功能結束

  SimpleConnectionService(this.ref) : super(const SimpleConnectionState());

  // ═══════════════════════════════════════════════════════════════════════════
  // 權限
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
      if (statuses[Permission.bluetoothScan] == PermissionStatus.granted &&
          statuses[Permission.bluetoothConnect] == PermissionStatus.granted) {
        return true;
      }
    } else if (Platform.isIOS) {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetooth,
        Permission.locationWhenInUse,
      ].request();
      if (statuses[Permission.bluetooth] == PermissionStatus.granted) {
        return true;
      }
    }
    return false;
  }

  Future<bool> checkBluetoothEnabled() async {
    try {
      final available = await FlutterBluePlus.isSupported;
      if (!available) return false;
      final adapterState = await FlutterBluePlus.adapterState.first;
      return adapterState == BluetoothAdapterState.on;
    } catch (e) {
      devLog('檢查藍牙錯誤', '$e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 掃描
  // ═══════════════════════════════════════════════════════════════════════════

  Stream<List<ScanResult>> startScan() {
    devLog('掃描', '開始掃描...');
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    return FlutterBluePlus.scanResults;
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 連線（參考 muti_mac_view_service 的簡單邏輯）
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> connectToDevice(BluetoothDevice device) async {
    devLog('連線流程', '開始連線到 ${device.platformName}');

    // 🔒 防止重複連線（參考 muti）
    if (state.connectedDevice != null) {
      devLog('連線', '已經有連線的裝置了');
      return false;
    }

    // 🎧 先建立連線狀態監聽器（參考 muti 的做法）
    final subscription = device.connectionState.listen(
      (connectionState) {
        if (connectionState == BluetoothConnectionState.disconnected) {
          devLog('監聽器', '${device.platformName} 意外斷線');
          // ⭐ 只在意外斷線時記錄（主動斷線已在 disconnectFromDevice 記錄）
          _lastDisconnectTime ??= DateTime.now();
          _removeDeviceFromConnected();
        }
        if (connectionState == BluetoothConnectionState.connected) {
          devLog('監聯器', '${device.platformName} 連線成功');
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

      // 💾 連線成功後，儲存監聽器（參考 muti）
      _connectionStateSubscription = subscription;
      
      // ⭐ 記錄連線時間
      _lastConnectTime = DateTime.now();

      devLog('連線流程', '✅ 連線成功');

      // 🔍 發現服務並快取
      final svcs = await device.discoverServices();
      devLog('服務', '已發現 ${device.platformName} 的 ${svcs.length} 個服務');

      // 初始化 SDK
      _currentDeviceId = device.remoteId.str;
      _healthCalculator = HealthCalculateDeviceID(3);

      // 更新狀態
      state = state.copyWith(
        connectedDevice: device,
        services: svcs,
      );

      // ✅ 自動訂閱 FFF4（參考 muti_view_mac_page._autoSubscribeFFF4）
      await _autoSubscribeFFF4(device, svcs);

      devLog('連線流程', '✅ 成功連線到 ${device.platformName}');
      return true;
    } catch (e) {
      devLog('連線', '連線到 ${device.platformName} 失敗: $e');
      // ⚠️ 連線失敗才取消監聽器（參考 muti）
      await subscription.cancel();
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 斷線（參考 muti_mac_view_service 的簡單邏輯）
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> disconnectFromDevice() async {
    final endTime = DateTime.now();
    try {
      devLog('斷線', '開始斷線...');
      
      // ⭐ 記錄斷線時間（在斷線開始時記錄）
      _lastDisconnectTime = endTime;

      // 🔇 先取消連線狀態監聽器（參考 muti line 651-652）
      await _connectionStateSubscription?.cancel();
      _connectionStateSubscription = null;

      // ⚠️ 注意：參考 muti disconnectAll() 的做法
      // 不在斷線前呼叫 setNotifyValue(false)
      // 直接斷線，讓連線監聽器處理後續清理
      await _stopAllNotifications();

      // 🔌 執行斷線（參考 muti line 655）
      await state.connectedDevice?.disconnect();

      // 🧹 清理該裝置的所有資源（參考 muti line 658）
      _removeDeviceFromConnected();

      devLog('資料次數-斷線時間', endTime.toString());

      devLog('斷線', '✅ 已斷線');
    } catch (e) {
      devLog('斷線', '斷線時發生錯誤: $e');
      // 🛡️ 即使斷線失敗，也要從列表中移除（參考 muti line 666-667）
      _removeDeviceFromConnected();
    }
  }

  // ⭐ 修正：正確關閉所有 notify
  Future<void> _stopAllNotifications() async {
    if (_notifySubscriptions.isEmpty) return;

    devLog('Notify', '🔇 開始關閉所有通知 (${_notifySubscriptions.length} 個)...');

    // 複製一份 keys，避免在迭代時修改 map
    final uuidsToCancel = List<Guid>.from(_notifySubscriptions.keys);

    for (final uuid in uuidsToCancel) {
      try {
        // 1. 取消 Stream 訂閱
        await _notifySubscriptions[uuid]?.cancel();
        devLog('Notify', '已取消 Stream 訂閱: $uuid');
      } catch (e) {
        devLog('Notify', '取消 Stream 訂閱失敗: $uuid - $e');
      }
    }

    // 2. 清空 map
    _notifySubscriptions.clear();

    // 3. 關閉 BLE 通知（如果裝置還在連線）
    if (state.connectedDevice != null && state.services.isNotEmpty) {
      for (final service in state.services) {
        for (final c in service.characteristics) {
          if (uuidsToCancel.contains(c.uuid)) {
            try {
              await c.setNotifyValue(false);
              devLog('Notify', '已關閉 BLE 通知: ${c.uuid}');
            } catch (e) {
              devLog('Notify', '關閉 BLE 通知失敗: ${c.uuid} - $e');
            }
          }
        }
      }
    }

    devLog('Notify', '✅ 所有通知已關閉');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 清理資源（參考 muti_mac_view_service）
  // ═══════════════════════════════════════════════════════════════════════════

  void _removeDeviceFromConnected() {
    devLog('清理', '開始清理資源...');

    // ✅ 修正：參考 muti _removeDeviceFromConnected (Line 735-739)
    // 需要呼叫 SDK dispose 以正確釋放資源
    if (_healthCalculator != null && _currentDeviceId != null) {
      _healthCalculator!.dispose(_currentDeviceId!);
      devLog('清理', '✅ 已呼叫 SDK dispose($_currentDeviceId)');
    }
    _healthCalculator = null;
    _currentDeviceId = null;

    // 注意：notify 訂閱已在 _stopAllNotifications() 中清理
    // 這裡只做備用清理（處理意外斷線的情況）
    _notifySubscriptions.clear();

    // 重置狀態
    state = state.copyWith(
      clearDevice: true,
      services: [],
      readValues: {},
      notifyValues: {},
    );

    // 🔇 取消連線監聽（參考 muti Line 763-765）
    // 注意：這裡需要保留，因為意外斷線時會直接呼叫此方法
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;

    devLog('清理', '✅ 資源清理完成');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 自動訂閱 FFF4（參考 muti_view_mac_page._autoSubscribeFFF4）
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _autoSubscribeFFF4(
    BluetoothDevice device,
    List<BluetoothService> services,
  ) async {
    try {
      devLog('[訂閱流程]', '🔍 開始搜尋 fff4 特徵...');

      // ✅ 關鍵：等待服務發現完成（參考 muti）
      await Future.delayed(const Duration(milliseconds: 500));

      // 找出 fff4 特徵
      BluetoothCharacteristic? fff4Char;

      for (final service in services) {
        for (final char in service.characteristics) {
          final uuidStr = char.uuid.toString().toLowerCase();
          if (uuidStr.contains('fff4') &&
              (char.properties.notify || char.properties.indicate)) {
            fff4Char = char;
            devLog('[訂閱流程]', '✅ 找到 fff4 特徵: ${char.uuid}');
            break;
          }
        }
        if (fff4Char != null) break;
      }

      if (fff4Char == null) {
        devLog('[訂閱流程]', '⚠️ 沒有找到 fff4 特徵');
        return;
      }

      // ⭐ 步驟 1：先發送時間同步指令（在訂閱之前）
      devLog('[訂閱流程]', '⏱️ 發送時間同步指令...');
      await _sendTimeSyncCommand();
      // await _sendTimeSyncCommand_OLD();

      // ⭐ 步驟 2：等待裝置處理時間同步
      await Future.delayed(const Duration(milliseconds: 300));

      // ⭐ 步驟 3：訂閱 fff4 特徵
      devLog('[訂閱流程]', '📡 開始訂閱 fff4...');
      await toggleNotify(fff4Char);

      // 驗證訂閱狀態
      final isSubscribed = isNotifying(fff4Char.uuid);
      if (isSubscribed) {
        devLog('[訂閱流程]', '✅ fff4 自動訂閱成功！');
      } else {
        devLog('[訂閱流程]', '⚠️ fff4 訂閱狀態驗證失敗');
      }
    } catch (e) {
      devLog('[訂閱流程]', '❌ 自動訂閱 fff4 失敗: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 讀取/寫入特徵
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> readCharacteristic(BluetoothCharacteristic c) async {
    try {
      final v = await c.read();
      final newReadValues = Map<Guid, List<int>>.from(state.readValues);
      newReadValues[c.uuid] = v;
      state = state.copyWith(readValues: newReadValues);
      devLog('Read', '${c.uuid} => $v');
    } catch (e) {
      devLog('Read', '讀取失敗: $e');
    }
  }

  Future<void> writeCharacteristic(BluetoothCharacteristic c) async {
    try {
      final data = utf8.encode('Hello Flutter');
      await c.write(data, withoutResponse: true);
      devLog('Write', '${c.uuid} => $data');
    } catch (e) {
      devLog('Write', '寫入失敗: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 訂閱通知（修正：使用獨立的 Stream 訂閱）
  // ═══════════════════════════════════════════════════════════════════════════

  bool isNotifying(Guid uuid) => _notifySubscriptions.containsKey(uuid);

  Future<void> toggleNotify(BluetoothCharacteristic c) async {
    if (_notifySubscriptions.containsKey(c.uuid)) {
      // ═══════════════════════════════════════════════════════════════════════
      // 關閉通知
      // ═══════════════════════════════════════════════════════════════════════
      try {
        // 1. 先取消 Stream 訂閱
        await _notifySubscriptions[c.uuid]?.cancel();
        _notifySubscriptions.remove(c.uuid);

        // 2. 再關閉 BLE 通知
        await c.setNotifyValue(false);

        devLog('Notify', '❌ ${c.uuid} 已關閉');
      } catch (e) {
        devLog('Notify', '關閉 ${c.uuid} 失敗: $e');
        // 確保從 map 中移除
        _notifySubscriptions.remove(c.uuid);
      }
    } else {
      // ═══════════════════════════════════════════════════════════════════════
      // 開啟通知
      // ═══════════════════════════════════════════════════════════════════════
      try {
        // ✅ 關鍵修正：先建立監聽器，再開啟通知
        // 使用 onValueReceived 而不是 lastValueStream
        // onValueReceived 是獨立的 Stream，不會與其他監聽者共享

        // 1. 先建立獨立的 Stream 訂閱
        final sub = c.onValueReceived.listen(
          (value) async {
            // ✅ 加入檢查：確保是這個 Service 的訂閱
            if (!_notifySubscriptions.containsKey(c.uuid)) {
              devLog('Notify', '⚠️ 收到資料但訂閱已取消，忽略');
              return;
            }
            devLog('資料次數', '------Start of Data------');
            _dataCount++;
            devLog('資料次數原始數據', '收到資料次數: $_dataCount');

            devLog('資料次數原始數據', '[Simple] ${c.uuid}: $value');

            // ⭐ 測試功能：記錄測試資料（移除時註解掉此行）
            _testService.recordTestData(value);

            // 更新 UI 上顯示的原始值
            final newNotifyValues = Map<Guid, List<int>>.from(
              state.notifyValues,
            );
            newNotifyValues[c.uuid] = value;
            state = state.copyWith(notifyValues: newNotifyValues);

            // 數據處理
            if (_healthCalculator != null && _currentDeviceId != null) {
              await _processData(value);
            }
          },
          onError: (error) {
            devLog('Notify', '❌ ${c.uuid} 接收資料錯誤: $error');
          },
          onDone: () {
            devLog('Notify', '🔇 ${c.uuid} Stream 已結束');
            _notifySubscriptions.remove(c.uuid);
          },
          cancelOnError: false,
        );

        // 2. 儲存訂閱
        _notifySubscriptions[c.uuid] = sub;

        // 3. 開啟 BLE 通知
        await c.setNotifyValue(true);

        devLog('Notify', '✅ ${c.uuid} 已開啟監聽 (獨立 Stream)');
      } catch (e) {
        devLog('Notify', '開啟 ${c.uuid} 失敗: $e');
        // 失敗時清理訂閱
        await _notifySubscriptions[c.uuid]?.cancel();
        _notifySubscriptions.remove(c.uuid);
      }
    }
  }

  // ⭐ 測試功能：取消訂閱 FFF4（移除時註解掉此方法）
  Future<void> unsubscribeFFF4() async {
    try {
      // 找出 FFF4 特徵
      final fff4 = state.services
          .expand((s) => s.characteristics)
          .where((ch) => ch.uuid.toString().toUpperCase().contains('FFF4'))
          .firstOrNull;

      if (fff4 != null && _notifySubscriptions.containsKey(fff4.uuid)) {
        await toggleNotify(fff4);
        devLog('測試', '✅ 已取消訂閱 FFF4');
      } else {
        devLog('測試', '⚠️ FFF4 未訂閱或找不到');
      }
    } catch (e) {
      devLog('測試', '取消訂閱 FFF4 失敗: $e');
    }
  }
  // ⭐ 測試功能結束

  // ═══════════════════════════════════════════════════════════════════════════
  // 數據處理（參考 data_match_service，但移除插值）
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _processData(List<int> value) async {
    if (_healthCalculator == null || _currentDeviceId == null) return;
    if (value.isEmpty || value.length < 17) return;

    // 使用篩選器（參考 data_match_service）
    final dataType = ref
        .read(filteredFirstRawDataProvider.notifier)
        .filterData(value, ref);

    if (dataType == DataType.reSent) {
      devLog('資料次數', '分類結果：🔄 補傳數據');
      devLog('資料次數', '補傳次數: ${++_reSentDataCount}');
    }

    if (dataType == DataType.first) {
      devLog('資料次數', '分類結果：✅ 第一組數據');
      _currentDataCount++;
      devLog('資料次數', '目前第一組數據次數: $_currentDataCount');
    }

    if (dataType != DataType.first) {
      devLog('dataType', 'dataType = $dataType，忽略資料');
      return;
    }

    final dataValue = ref.read(filteredFirstRawDataProvider);

    if (dataValue.splitRawData.isEmpty || dataValue.splitRawData.length < 17) {
      devLog('數據過濾', '⚠️ 篩選後資料為空或長度不足，已忽略');
      return;
    }

    try {
      // 直接處理數據（不做插值）
      await _healthCalculator!
          .splitPackage(
            Uint8List.fromList(dataValue.splitRawData),
            _currentDeviceId!,
          )
          .then((_) {
            devLog('資料次數', '------End of Data------');
          });

      // 更新 healthDataProvider
      _updateHealthProvider();
    } catch (e) {
      devLog('SDK處理', '❌ 處理資料時發生錯誤: $e');
    }
  }

  void _updateHealthProvider() {
    if (_healthCalculator == null) return;

    final timestamp = _healthCalculator!.getTimeStamp();

    ref
        .read(healthDataProvider.notifier)
        .normalUpdate(
          hr: _healthCalculator!.getHRValue() ?? 0,
          br: _healthCalculator!.getBRValue() ?? 0,
          gyroX: _healthCalculator!.getGyroValueX() ?? 0,
          gyroY: _healthCalculator!.getGyroValueY() ?? 0,
          gyroZ: _healthCalculator!.getGyroValueZ() ?? 0,
          temp: (_healthCalculator!.getTempValue() is num)
              ? (_healthCalculator!.getTempValue() as num).toDouble()
              : 0.0,
          hum: (_healthCalculator!.getHumValue() is num)
              ? (_healthCalculator!.getHumValue() as num).toDouble()
              : 0.0,
          spO2: _healthCalculator!.getSpO2Value() ?? 0,
          step: _healthCalculator!.getStepValue() ?? 0,
          power: _healthCalculator!.getPowerValue() ?? 0,
          time: timestamp,
          hrFiltered: (_healthCalculator!.getHRFiltered() is List)
              ? (_healthCalculator!.getHRFiltered() as List)
                    .map((e) => (e as num).toDouble())
                    .toList()
              : const [],
          brFiltered: (_healthCalculator!.getBRFiltered() is List)
              ? (_healthCalculator!.getBRFiltered() as List)
                    .map((e) => (e as num).toDouble())
                    .toList()
              : const [],
          isWearing:
              _healthCalculator!.getIsWearing() == 1 ||
              _healthCalculator!.getIsWearing() == true,
          rawData: (_healthCalculator!.getRawData() is List)
              ? (_healthCalculator!.getRawData() as List)
                    .map((e) => (e as num).toInt())
                    .toList()
              : const [],
          type: _healthCalculator!.getType() ?? 0,
          fftOut: _healthCalculator!.getFFTOut() is List
              ? (_healthCalculator!.getFFTOut() as List?)
                    ?.map((e) => (e as num).toDouble())
                    .toList()
              : null,
          petPose: _healthCalculator!.getPetPoseValue(),
        );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 時間同步指令
  // ═══════════════════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════════════════════
  // 時間同步指令（廠商格式：分兩次發送 0xEA + 0xEB）
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _sendTimeSyncCommand() async {
    try {
      final writeCharacteristic = state.services
          .expand((s) => s.characteristics)
          .firstWhere(
            (ch) => ch.uuid.toString().toUpperCase().contains('FFF5'),
          );

      if (writeCharacteristic.properties.write) {
        // ⭐ 記錄寫入時間戳的時間
        _lastTimeSyncWriteTime = DateTime.now();
        
        // ⭐ 廠商格式：分兩次發送
        // 第一次：0xEA + TS1 TS2 TS3
        await writeCharacteristic.write(
          _getTimestamp1Command(),
          withoutResponse: false,
        );
        devLog('時間同步', '✅ 已發送 Timestamp1 (0xEA) 到 FFF5');
        devLog('時間同步', '⏱️ 寫入時間: $_lastTimeSyncWriteTime');

        // 等待裝置處理
        await Future.delayed(const Duration(milliseconds: 100));

        // 第二次：0xEB + TS4 TS5
        await writeCharacteristic.write(
          _getTimestamp2Command(),
          withoutResponse: false,
        );
        devLog('時間同步', '✅ 已發送 Timestamp2 (0xEB) 到 FFF5');
      }
    } catch (e) {
      devLog('時間同步錯誤', '$e');
    }
  }

  /// 廠商格式 Timestamp1：0xEA + TS1 TS2 TS3（4 bytes）
  /// ✅ 使用台灣本地時間（UTC+8）
  Uint8List _getTimestamp1Command() {
    final now = DateTime.now();

    // ✅ 轉換為本地時間戳（加上時區偏移）
    int timestamp = now.millisecondsSinceEpoch;
    timestamp += now.timeZoneOffset.inMilliseconds; // 加上 UTC+8 的偏移
    timestamp = timestamp ~/ 10; // 轉換為 10ms 單位

    final command = Uint8List(4);
    command[0] = 0xEA; // Header
    command[1] = (timestamp >> 0) & 0xFF; // TS1 (低位元組)
    command[2] = (timestamp >> 8) & 0xFF; // TS2
    command[3] = (timestamp >> 16) & 0xFF; // TS3

    devLog('資料次數-時間同步', '本地時間: $now');
    devLog('時間同步', '本地時間: $now');
    devLog('時間同步', '時區偏移: ${now.timeZoneOffset.inHours} 小時');
    devLog('時間同步', '本地時間戳 (10ms): $timestamp');
    devLog('時間同步', 'Timestamp1 指令: $command');
    return command;
  }

  /// 廠商格式 Timestamp2：0xEB + TS4 TS5（3 bytes）
  /// ✅ 使用台灣本地時間（UTC+8）
  Uint8List _getTimestamp2Command() {
    final now = DateTime.now();

    // ✅ 轉換為本地時間戳（加上時區偏移）
    int timestamp = now.millisecondsSinceEpoch;
    timestamp += now.timeZoneOffset.inMilliseconds; // 加上 UTC+8 的偏移
    timestamp = timestamp ~/ 10; // 轉換為 10ms 單位

    final command = Uint8List(3);
    command[0] = 0xEB; // Header
    command[1] = (timestamp >> 24) & 0xFF; // TS4
    command[2] = (timestamp >> 32) & 0xFF; // TS5 (高位元組)

    devLog('時間同步', 'Timestamp2 指令: $command');
    return command;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 舊版時間同步指令（0xFC 格式，已棄用）
  // ═══════════════════════════════════════════════════════════════════════════

  // Future<void> _sendTimeSyncCommand_OLD() async {
  //   try {
  //     final writeCharacteristic = state.services
  //         .expand((s) => s.characteristics)
  //         .firstWhere(
  //           (ch) => ch.uuid.toString().toUpperCase().contains('FFF5'),
  //         );

  //     if (writeCharacteristic.properties.write) {
  //       await writeCharacteristic.write(
  //         _getTimeSyncCommand_OLD(),
  //         withoutResponse: false,
  //       );
  //       devLog('時間同步', '成功發送時間指令到 FFF5');
  //     }
  //   } catch (e) {
  //     devLog('時間同步錯誤', '$e');
  //   }
  // }

  // Uint8List _getTimeSyncCommand_OLD() {
  //   final now = DateTime.now();
  //   devLog('時間同步', "當前本地時間: $now");
  //   int timestamp = now.millisecondsSinceEpoch;
  //   devLog('時間同步', "當前時間戳 (UTC): $timestamp");
  //   timestamp += now.timeZoneOffset.inMilliseconds;
  //   devLog('時間同步', "加上時區偏移後的時間戳: $timestamp");
  //   timestamp = timestamp ~/ 10;
  //   final byteData = ByteData(8)..setInt64(0, timestamp, Endian.little);
  //   final command = Uint8List(6);
  //   command[0] = 0xfc;
  //   command[1] = byteData.getUint8(0);
  //   command[2] = byteData.getUint8(1);
  //   command[3] = byteData.getUint8(2);
  //   command[4] = byteData.getUint8(3);
  //   command[5] = byteData.getUint8(4);
  //   devLog('時間同步', "寫入時間戳 (Local): $timestamp");
  //   return command;
  // }

  // ═══════════════════════════════════════════════════════════════════════════
  // 清理
  // ═══════════════════════════════════════════════════════════════════════════

  void cleanup() {
    devLog('清理', '開始清理所有資源...');

    _connectionStateSubscription?.cancel();

    // ⭐ 測試功能：清理測試服務（移除時註解掉此行）
    _testService.dispose();

    for (var sub in _notifySubscriptions.values) {
      sub.cancel();
    }
    _notifySubscriptions.clear();

    if (state.connectedDevice != null) {
      try {
        state.connectedDevice!.disconnect();
      } catch (e) {
        devLog('清理', '清理時斷線錯誤: $e');
      }
    }

    // ❌ 不呼叫 SDK dispose（僅 Dart 層清理）
    // 原因：cleanup 是 App 結束時呼叫，不需要 dispose
    _healthCalculator = null;
    _currentDeviceId = null;

    state = const SimpleConnectionState();
    devLog('清理', '✅ 已清理所有資源（僅 Dart 層，未呼叫 SDK dispose）');
  }

  @override
  void dispose() {
    cleanup();
    super.dispose();
  }
}
