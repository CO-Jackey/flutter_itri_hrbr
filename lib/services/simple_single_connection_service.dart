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
          _removeDeviceFromConnected();
        }
        if (connectionState == BluetoothConnectionState.connected) {
          devLog('監聽器', '${device.platformName} 連線成功');
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
    try {
      devLog('斷線', '開始斷線...');

      // 🔇 先取消連線狀態監聽器（參考 muti line 651-652）
      await _connectionStateSubscription?.cancel();
      _connectionStateSubscription = null;

      // ⚠️ 注意：參考 muti disconnectAll() 的做法
      // 不在斷線前呼叫 setNotifyValue(false)
      // 直接斷線，讓連線監聽器處理後續清理
      // await _stopAllNotifications();

      // 🔌 執行斷線（參考 muti line 655）
      await state.connectedDevice?.disconnect();

      // 🧹 清理該裝置的所有資源（參考 muti line 658）
      _removeDeviceFromConnected();

      devLog('斷線', '✅ 已斷線');
    } catch (e) {
      devLog('斷線', '斷線時發生錯誤: $e');
      // 🛡️ 即使斷線失敗，也要從列表中移除（參考 muti line 666-667）
      _removeDeviceFromConnected();
    }
  }

  // ⭐ 新增：正確關閉所有 notify（通知藍牙裝置停止發送）
  Future<void> _stopAllNotifications() async {
    if (state.services.isEmpty) return;

    for (final service in state.services) {
      for (final c in service.characteristics) {
        if (_notifySubscriptions.containsKey(c.uuid)) {
          try {
            await _notifySubscriptions[c.uuid]?.cancel();
            await c.setNotifyValue(false);
            devLog('Notify', '❌ ${c.uuid} 已關閉 notify');
          } catch (e) {
            devLog('Notify', '關閉 ${c.uuid} notify 失敗: $e');
          }
        }
      }
    }
    _notifySubscriptions.clear();
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
  // 訂閱通知（參考 data_match_service 的詳細邏輯）
  // ═══════════════════════════════════════════════════════════════════════════

  bool isNotifying(Guid uuid) => _notifySubscriptions.containsKey(uuid);

  Future<void> toggleNotify(BluetoothCharacteristic c) async {
    if (_notifySubscriptions.containsKey(c.uuid)) {
      // 關閉通知
      await _notifySubscriptions[c.uuid]?.cancel();
      await c.setNotifyValue(false);
      _notifySubscriptions.remove(c.uuid);
      devLog('Notify', '❌ ${c.uuid} 已關閉');
    } else {
      // 開啟通知
      try {
        await c.setNotifyValue(true);

        final sub = c.lastValueStream.listen((value) async {
          devLog('原始數據', value.toString());

          // 更新 UI 上顯示的原始值
          final newNotifyValues = Map<Guid, List<int>>.from(
            state.notifyValues,
          );
          newNotifyValues[c.uuid] = value;
          state = state.copyWith(notifyValues: newNotifyValues);

          // 數據處理（參考 data_match_service）
          if (_healthCalculator != null && _currentDeviceId != null) {
            await _processData(value);
          }
        });

        _notifySubscriptions[c.uuid] = sub;
        devLog('Notify', '✅ ${c.uuid} 已開啟監聽');

        // ⭐ 時間同步已移至 _autoSubscribeFFF4()，在訂閱之前執行
        // 這裡不再發送時間同步指令
      } catch (e) {
        devLog('Notify', '開啟失敗: $e');
      }
    }
  }

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
      await _healthCalculator!.splitPackage(
        Uint8List.fromList(dataValue.splitRawData),
        _currentDeviceId!,
      );

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
        // ⭐ 廠商格式：分兩次發送
        // 第一次：0xEA + TS1 TS2 TS3
        await writeCharacteristic.write(
          _getTimestamp1Command(),
          withoutResponse: false,
        );
        devLog('時間同步', '✅ 已發送 Timestamp1 (0xEA) 到 FFF5');

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
  Uint8List _getTimestamp1Command() {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 10;

    final command = Uint8List(4);
    command[0] = 0xEA;  // Header
    command[1] = (timestamp >> 0) & 0xFF;   // TS1
    command[2] = (timestamp >> 8) & 0xFF;   // TS2
    command[3] = (timestamp >> 16) & 0xFF;  // TS3

    devLog('時間同步', 'Timestamp1 指令: $command');
    return command;
  }

  /// 廠商格式 Timestamp2：0xEB + TS4 TS5（3 bytes）
  Uint8List _getTimestamp2Command() {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 10;

    final command = Uint8List(3);
    command[0] = 0xEB;  // Header
    command[1] = (timestamp >> 24) & 0xFF;  // TS4
    command[2] = (timestamp >> 32) & 0xFF;  // TS5

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
  //
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
