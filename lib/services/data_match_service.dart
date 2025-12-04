import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_itri_hrbr/helper/devLog.dart';
import 'package:flutter_itri_hrbr/model/inter_data.dart';
import 'package:flutter_itri_hrbr/provider/health_provider.dart';
import 'package:flutter_itri_hrbr/services/HealthCalculate_Device_ID.dart';
import 'package:flutter_itri_hrbr/services/data_Classifier_Service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:permission_handler/permission_handler.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ✅ 新增：重連階段枚舉
// ═══════════════════════════════════════════════════════════════════════════

enum ReconnectPhase {
  none, // 沒有在重連
  quick, // 階段1：快速直連（利用記憶）
  full, // 階段2：完整清理重連
}

// ═══════════════════════════════════════════════════════════════════════════
// State 類別
// ═══════════════════════════════════════════════════════════════════════════

class DataMatchState {
  final BluetoothDevice? connectedDevice;
  final List<BluetoothService> services;
  final Map<Guid, List<int>> readValues;
  final Map<Guid, List<int>> notifyValues;
  final bool isScanning;
  final bool enableInterpolation;

  // ✅ 新增：重連狀態
  final bool isReconnecting;
  final int reconnectAttempts;

  // ✅ 新增：重連階段
  final ReconnectPhase reconnectPhase; // ⭐ 加這一行

  // 統計數據
  final int originalPacketCount;
  final int interpolatedPacketCount;
  final int packetsInCurrentSecond;
  final int currentSecond;

  const DataMatchState({
    this.connectedDevice,
    this.services = const [],
    this.readValues = const {},
    this.notifyValues = const {},
    this.isScanning = false,
    this.enableInterpolation = true,
    this.isReconnecting = false,
    this.reconnectAttempts = 0,
    this.originalPacketCount = 0,
    this.interpolatedPacketCount = 0,
    this.packetsInCurrentSecond = 0,
    this.currentSecond = 0,
    this.reconnectPhase = ReconnectPhase.none, // ⭐ 預設值
  });

  bool get isConnected => connectedDevice != null;

  DataMatchState copyWith({
    BluetoothDevice? connectedDevice,
    List<BluetoothService>? services,
    Map<Guid, List<int>>? readValues,
    Map<Guid, List<int>>? notifyValues,
    bool? isScanning,
    bool? enableInterpolation,
    bool? isReconnecting,
    int? reconnectAttempts,
    int? originalPacketCount,
    int? interpolatedPacketCount,
    int? packetsInCurrentSecond,
    int? currentSecond,
    bool clearDevice = false,
    ReconnectPhase? reconnectPhase, // ⭐ 新增參數
  }) {
    return DataMatchState(
      connectedDevice: clearDevice
          ? null
          : (connectedDevice ?? this.connectedDevice),
      services: services ?? this.services,
      readValues: readValues ?? this.readValues,
      notifyValues: notifyValues ?? this.notifyValues,
      isScanning: isScanning ?? this.isScanning,
      enableInterpolation: enableInterpolation ?? this.enableInterpolation,
      isReconnecting: isReconnecting ?? this.isReconnecting,
      reconnectAttempts: reconnectAttempts ?? this.reconnectAttempts,
      originalPacketCount: originalPacketCount ?? this.originalPacketCount,
      interpolatedPacketCount:
          interpolatedPacketCount ?? this.interpolatedPacketCount,
      packetsInCurrentSecond:
          packetsInCurrentSecond ?? this.packetsInCurrentSecond,
      currentSecond: currentSecond ?? this.currentSecond,
      reconnectPhase: reconnectPhase ?? this.reconnectPhase, // ⭐ 新增這一行
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Service Provider
// ═══════════════════════════════════════════════════════════════════════════

final dataMatchServiceProvider =
    StateNotifierProvider<DataMatchService, DataMatchState>((ref) {
      return DataMatchService(ref);
    });

// ═══════════════════════════════════════════════════════════════════════════
// Service 類別
// ═══════════════════════════════════════════════════════════════════════════

class DataMatchService extends StateNotifier<DataMatchState> {
  final Ref ref;

  // SDK 相關
  HealthCalculateDeviceID? _healthCalculator;
  String? _currentDeviceId;

  // 連線狀態旗標
  bool _isConnecting = false;
  bool _isConnected = false;
  bool _isDisconnecting = false;
  bool _isTogglingNotify = false;

  // ✅ 新增：手動斷線旗標（區分主動/被動斷線）
  bool _isIntentionalDisconnect = false;

  // ✅ 新增：記住上次連線的裝置（用於自動重連）
  BluetoothDevice? _lastConnectedDevice;

  // ✅ 新增：記住上次連線的服務 UUIDs
  List<Guid> _lastConnectedServiceUuids = [];

  // ✅ 新增：重連相關
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5; // 改成 5 次
  // static const int _scanTimeoutSeconds = 30; // 每次掃描 30 秒
  Timer? _reconnectTimer;
  StreamSubscription<List<ScanResult>>? _reconnectScanSubscription;

  // 最後連線時間
  DateTime? _lastConnectedTime;

  // Debug 計數器
  int _connectAttempts = 0;
  int _disconnectAttempts = 0;

  // 插值相關
  List<int>? _firstGroupPacket;
  int? _firstGroupTimestamp;
  bool _isWaitingForSecond = false;

  // 統計相關
  Timer? _statsTimer;
  DateTime? _statsStartTime;
  int _originalPacketCount = 0;
  int _interpolatedPacketCount = 0;
  int _packetsInCurrentSecond = 0;
  int _currentSecond = 0;

  // 訂閱管理
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;
  final Map<Guid, StreamSubscription<List<int>>> _notifySubscriptions = {};

  // 新增：上次斷線時間（用於計算冷卻時間）
  DateTime? _lastDisconnectTime;

  // ═══════════════════════════════════════════════════════════════════════════
  // ✅ 操作保護機制
  // ═══════════════════════════════════════════════════════════════════════════

  // 操作間隔限制
  // DateTime? _lastDisconnectTime;
  DateTime? _lastConnectTime;
  static const Duration _minOperationInterval = Duration(seconds: 3);

  // 連續操作計數（用於偵測異常快速操作）
  int _rapidOperationCount = 0;
  DateTime? _rapidOperationWindowStart;
  static const Duration _rapidOperationWindow = Duration(seconds: 30);
  static const int _maxRapidOperations = 5; // 30秒內最多5次操作

  /// 檢查是否可以執行連線操作
  Future<bool> canConnect() async {
    // 1. 檢查基本冷卻時間
    if (_lastDisconnectTime != null) {
      final timeSinceDisconnect = DateTime.now().difference(
        _lastDisconnectTime!,
      );
      if (timeSinceDisconnect < _minOperationInterval) {
        final waitTime = _minOperationInterval - timeSinceDisconnect;
        devLog('操作保護', '⏳ 冷卻中，還需等待 ${waitTime.inMilliseconds}ms');
        return false;
      }
    }

    // 2. 檢查連續操作次數
    if (!_checkRapidOperations()) {
      devLog('操作保護', '🛑 操作過於頻繁，請稍後再試');
      return false;
    }

    return true;
  }

  /// 檢查連續操作次數，防止快速連續操作
  bool _checkRapidOperations() {
    final now = DateTime.now();

    // 如果超過時間窗口，重置計數
    if (_rapidOperationWindowStart == null ||
        now.difference(_rapidOperationWindowStart!) > _rapidOperationWindow) {
      _rapidOperationWindowStart = now;
      _rapidOperationCount = 0;
    }

    _rapidOperationCount++;

    if (_rapidOperationCount > _maxRapidOperations) {
      devLog(
        '操作保護',
        '🛑 ${_rapidOperationWindow.inSeconds}秒內已操作 $_rapidOperationCount 次，超過限制 $_maxRapidOperations 次',
      );
      return false;
    }

    devLog(
      '操作保護',
      '✅ 操作次數: $_rapidOperationCount/$_maxRapidOperations (${_rapidOperationWindow.inSeconds}秒內)',
    );
    return true;
  }

  /// 取得下次可操作的等待時間（秒）
  int getWaitTimeSeconds() {
    if (_lastDisconnectTime == null) return 0;

    final timeSinceDisconnect = DateTime.now().difference(_lastDisconnectTime!);
    if (timeSinceDisconnect >= _minOperationInterval) return 0;

    return (_minOperationInterval - timeSinceDisconnect).inSeconds + 1;
  }

  /// 是否在冷卻中
  bool get isInCooldown {
    if (_lastDisconnectTime == null) return false;
    final timeSinceDisconnect = DateTime.now().difference(_lastDisconnectTime!);
    return timeSinceDisconnect < _minOperationInterval;
  }

  /// 是否操作過於頻繁
  bool get isTooFrequent {
    if (_rapidOperationWindowStart == null) return false;
    final now = DateTime.now();
    if (now.difference(_rapidOperationWindowStart!) > _rapidOperationWindow) {
      return false;
    }
    return _rapidOperationCount >= _maxRapidOperations;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Service 類別
  // ═══════════════════════════════════════════════════════════════════════════

  DataMatchService(this.ref) : super(const DataMatchState()) {
    _initStats();
  }

  void _initStats() {
    _statsStartTime = DateTime.now();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Getter：取得上次連線的裝置
  // ═══════════════════════════════════════════════════════════════════════════

  BluetoothDevice? get lastConnectedDevice => _lastConnectedDevice;

  // ═══════════════════════════════════════════════════════════════════════════
  // Debug：取得當前狀態
  // ═══════════════════════════════════════════════════════════════════════════

  void printDebugStatus() {
    devLog('DEBUG', '''
══════════════════════════════════════
連線嘗試次數: $_connectAttempts
斷線嘗試次數: $_disconnectAttempts
重連嘗試次數: $_reconnectAttempts / $_maxReconnectAttempts
重連階段: ${state.reconnectPhase}  // ⭐ 加這行
_isConnecting: $_isConnecting
_isConnected: $_isConnected
_isDisconnecting: $_isDisconnecting
_isIntentionalDisconnect: $_isIntentionalDisconnect
state.isConnected: ${state.isConnected}
connectedDevice: ${state.connectedDevice?.platformName ?? 'null'}
lastConnectedDevice: ${_lastConnectedDevice?.platformName ?? 'null'}
services 數量: ${state.services.length}
notifySubscriptions 數量: ${_notifySubscriptions.length}
最後連線時間: $_lastConnectedTime
══════════════════════════════════════
    ''');
  }

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
  // 掃描前準備
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> prepareForScan() async {
    devLog('掃描準備', '開始準備掃描環境...');

    // 取消任何進行中的重連
    _cancelReconnect();

    if (_isDisconnecting) {
      devLog('掃描準備', '等待斷線完成...');
      int waitCount = 0;
      while (_isDisconnecting && waitCount < 30) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitCount++;
      }
    }

    if (_isConnected || state.connectedDevice != null) {
      devLog('掃描準備', '發現殘留連線，正在清理...');
      await disconnectFromDevice();
    }

    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      devLog('掃描準備', '停止掃描失敗（可忽略）: $e');
    }

    final connectedDevices = FlutterBluePlus.connectedDevices;
    if (connectedDevices.isNotEmpty) {
      devLog('掃描準備', '發現 ${connectedDevices.length} 個系統殘留連線');
      for (final device in connectedDevices) {
        try {
          await device.disconnect();
          devLog('掃描準備', '已斷開系統殘留: ${device.platformName}');
        } catch (e) {
          devLog('掃描準備', '斷開系統殘留失敗: $e');
        }
      }
    }

    await Future.delayed(const Duration(milliseconds: 500));

    _isConnecting = false;
    _isConnected = false;
    _isDisconnecting = false;
    _isTogglingNotify = false;
    _isIntentionalDisconnect = false;

    devLog('掃描準備', '✅ 掃描環境準備完成');
    printDebugStatus();
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
  // 連線（支援手動連線和自動重連）
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> connectToDevice(
    BluetoothDevice device, {
    bool isAutoReconnect = false,
  }) async {
    _connectAttempts++;
    devLog(
      '連線流程',
      '=== 第 $_connectAttempts 次連線嘗試 ${isAutoReconnect ? "(自動重連)" : "(手動)"} ===',
    );

    // ✅ 手動連線需要檢查保護機制
    if (!isAutoReconnect) {
      if (!await canConnect()) {
        devLog('連線流程', '⚠️ 操作被保護機制阻擋');
        return;
      }
    }

    if (_isConnecting) {
      devLog('連線流程', '⚠️ 已經在連線中，忽略此次請求');
      return;
    }

    if (_isConnected) {
      devLog('連線流程', '⚠️ 已經連線，先斷開再連');
      await disconnectFromDevice();
      await Future.delayed(const Duration(milliseconds: 500));
    }

    _isConnecting = true;
    _isConnected = false;
    _isIntentionalDisconnect = false;

    if (isAutoReconnect) {
      state = state.copyWith(isReconnecting: true);
    }

    devLog('連線流程', '開始連線到 ${device.platformName} (${device.remoteId})');
    printDebugStatus();

    // 取消舊的監聽器
    await _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;

    try {
      // ✅ 統一使用手動連線模式（不用 autoConnect）
      devLog('連線流程', '🚀 開始連線...');

      await device.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 10),
      );

      devLog('連線流程', '✅ 連線成功');

      await Future.delayed(const Duration(milliseconds: 500));

      List<BluetoothService> discoveredServices = await device
          .discoverServices();
      devLog('連線流程', '✅ 發現 ${discoveredServices.length} 個服務');

      await Future.delayed(const Duration(milliseconds: 300));

      _currentDeviceId = device.remoteId.str;
      _healthCalculator = HealthCalculateDeviceID(3);
      await _healthCalculator!.reset(_currentDeviceId!);

      _isConnecting = false;
      _isConnected = true;
      _lastConnectedTime = DateTime.now();
      _lastConnectTime = DateTime.now(); // ✅ 記錄連線時間
      _lastConnectedDevice = device;
      _reconnectAttempts = 0; // ✅ 連線成功，重置計數

      devLog('連線流程', '✅ 連線完成');

      state = state.copyWith(
        connectedDevice: device,
        services: discoveredServices,
        isReconnecting: false,
        reconnectAttempts: 0,
      );

      _setupConnectionStateListener(device);

      printDebugStatus();
    } catch (e) {
      devLog('連線流程', '❌ 連線失敗: $e');
      _isConnecting = false;
      _isConnected = false;

      state = state.copyWith(isReconnecting: false);

      // ⭐⭐⭐ 根據當前階段決定處理方式 ⭐⭐⭐
      if (isAutoReconnect) {
        final currentPhase = state.reconnectPhase;

        if (currentPhase == ReconnectPhase.quick) {
          // 階段1失敗：不做 disconnect，直接切換到階段2
          devLog('連線流程', '⚠️ 階段1連線失敗，準備切換到階段2');

          state = state.copyWith(
            reconnectPhase: ReconnectPhase.full,
          );

          if (!_isIntentionalDisconnect) {
            devLog('連線流程', '繼續重連流程（階段2）...');
            _scheduleReconnect(device);
          }
        } else {
          // 階段2失敗：需要完整清理
          try {
            devLog('連線流程', '🔧 階段2失敗，執行完整清理...');
            await device.disconnect();
            devLog('連線流程', '✅ disconnect() 完成');

            if (Platform.isIOS) {
              devLog('連線流程', '⏳ [iOS] 等待 2 秒清理...');
              await Future.delayed(const Duration(seconds: 2));
            } else {
              devLog('連線流程', '⏳ [Android] 等待 1 秒...');
              await Future.delayed(const Duration(seconds: 1));
            }
          } catch (disconnectError) {
            devLog('連線流程', '⚠️ disconnect 失敗: $disconnectError');
            if (Platform.isIOS) {
              await Future.delayed(const Duration(seconds: 2));
            }
          }

          if (!_isIntentionalDisconnect) {
            devLog('連線流程', '繼續重連流程...');
            _scheduleReconnect(device);
          }
        }
      } else {
        // 手動連線失敗，確保斷線
        try {
          await device.disconnect();
        } catch (_) {}
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ✅ 建立連線狀態監聽器
  // ═══════════════════════════════════════════════════════════════════════════

  void _setupConnectionStateListener(BluetoothDevice device) {
    _connectionStateSubscription?.cancel();

    _connectionStateSubscription = device.connectionState.listen((
      connState,
    ) async {
      devLog(
        '監聽器',
        '狀態: $connState | isConnected=$_isConnected, isIntentional=$_isIntentionalDisconnect',
      );

      if (connState == BluetoothConnectionState.disconnected) {
        if (_isConnected && !_isIntentionalDisconnect) {
          // ✅ 意外斷線：執行自動重連
          devLog('監聽器', '⚠️ 裝置意外斷開！啟動自動重連...');
          await _handleUnexpectedDisconnect(device);
        } else if (_isIntentionalDisconnect) {
          devLog('監聽器', '✋ 手動斷線，不執行重連');
        } else {
          devLog('監聽器', '🔇 忽略 disconnected 事件');
        }
      }
    });
  }

  // Future<void> _handleUnexpectedDisconnect(BluetoothDevice device) async {
  //   devLog('意外斷線', '開始處理意外斷線...');

  //   _isConnected = false;
  //   _isConnecting = false;

  //   // 記住這台裝置
  //   _lastConnectedDevice = device;

  //   // 取消所有訂閱
  //   for (var sub in _notifySubscriptions.values) {
  //     sub.cancel();
  //   }
  //   _notifySubscriptions.clear();

  //   // 清理 SDK
  //   if (_healthCalculator != null && _currentDeviceId != null) {
  //     _healthCalculator!.dispose(_currentDeviceId!);
  //   }
  //   _healthCalculator = null;
  //   _currentDeviceId = null;

  //   // 重置插值狀態
  //   _firstGroupPacket = null;
  //   _firstGroupTimestamp = null;
  //   _isWaitingForSecond = false;

  //   state = state.copyWith(
  //     clearDevice: true,
  //     services: [],
  //     readValues: {},
  //     notifyValues: {},
  //   );

  //   // ⭐⭐⭐ 關鍵修改：主動斷開連接（Android 和 iOS 都要！）⭐⭐⭐
  //   devLog('意外斷線', '🔧 主動執行 disconnect() 清理連接狀態');
  //   try {
  //     await device.disconnect();
  //     devLog('意外斷線', '✅ disconnect() 完成');
  //   } catch (e) {
  //     devLog('意外斷線', '⚠️ disconnect() 失敗: $e');
  //     // 即使失敗也繼續，有可能已經斷了
  //   }

  //   // ✅ iOS 專用：等待更長時間讓系統釋放藍牙資源
  //   if (Platform.isIOS) {
  //     devLog('意外斷線', '🍎 [iOS] 等待 2 秒讓系統釋放藍牙資源...');
  //     Future.delayed(const Duration(seconds: 2), () {
  //       if (!_isIntentionalDisconnect) {
  //         devLog('意外斷線', '✅ 清理完成，準備重連');
  //         printDebugStatus();
  //         _scheduleReconnect(device);
  //       }
  //     });
  //   } else {
  //     devLog('意外斷線', '✅ 清理完成，準備重連');
  //     printDebugStatus();
  //     _scheduleReconnect(device);
  //   }
  // }
  // ═══════════════════════════════════════════════════════════════════════════
  // ✅ 意外斷線處理（兩段式策略版）
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _handleUnexpectedDisconnect(BluetoothDevice device) async {
    devLog('意外斷線', '========== 開始處理意外斷線 ==========');
    devLog('意外斷線', '設備: ${device.platformName}');

    _isConnected = false;
    _isConnecting = false;

    // 記住這台裝置
    _lastConnectedDevice = device;

    // 記錄當前狀態
    devLog('意外斷線', '當前訂閱數: ${_notifySubscriptions.length}');
    devLog('意外斷線', '當前服務數: ${state.services.length}');

    // ⭐⭐⭐ 關鍵：只清理 Dart 層，不清理藍牙層 ⭐⭐⭐
    // 這樣可以利用 iOS 的記憶加速重連

    // 1. 取消 StreamSubscription（Dart 層清理）
    for (var sub in _notifySubscriptions.values) {
      try {
        await sub.cancel();
        devLog('意外斷線', '✅ 已取消 Stream 訂閱');
      } catch (e) {
        devLog('意外斷線', '⚠️ 取消訂閱失敗: $e');
      }
    }
    _notifySubscriptions.clear();

    // 2. 清理 SDK
    if (_healthCalculator != null && _currentDeviceId != null) {
      try {
        await _healthCalculator!.dispose(_currentDeviceId!);
        devLog('意外斷線', '✅ SDK 清理完成');
      } catch (e) {
        devLog('意外斷線', '⚠️ SDK 清理失敗: $e');
      }
    }
    _healthCalculator = null;
    _currentDeviceId = null;

    // 3. 重置插值狀態
    _firstGroupPacket = null;
    _firstGroupTimestamp = null;
    _isWaitingForSecond = false;

    // 4. 更新 UI 狀態
    state = state.copyWith(
      clearDevice: true,
      services: [],
      readValues: {},
      notifyValues: {},
      reconnectPhase: ReconnectPhase.quick, // ⭐ 設定為快速重連階段
    );

    // ⭐⭐⭐ 關鍵：不呼叫 disconnect() ⭐⭐⭐
    // 讓 iOS 保留設備記憶，加速重連
    devLog('意外斷線', '✅ Dart 層清理完成（保留藍牙層記憶）');
    devLog('意外斷線', '→ 準備快速重連（階段1）');

    printDebugStatus();

    // ✅ 啟動兩段式重連
    _scheduleReconnect(device);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ✅ 新增：階段1 - 快速重連（利用 iOS 記憶）
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> _quickReconnect(BluetoothDevice device) async {
    devLog('快速重連', '========== 階段1：快速重連 ==========');

    final deviceId = device.remoteId.str;
    final deviceName = device.platformName;

    // ⭐⭐⭐ 步驟1：檢查幽靈連線（iOS 專用）⭐⭐⭐
    if (Platform.isIOS) {
      devLog('快速重連', '🍎 [iOS] 步驟1：檢查幽靈連線...');

      final ghostDevice = await _tryRetrieveSystemConnectedDevice(deviceId);

      if (ghostDevice != null) {
        devLog('快速重連', '✅ 發現幽靈連線！嘗試直接使用...');

        try {
          // 檢查連線狀態
          final connState = await ghostDevice.connectionState.first.timeout(
            const Duration(seconds: 2),
          );

          if (connState == BluetoothConnectionState.connected) {
            devLog('快速重連', '✅ 幽靈連線狀態正常，直接完成連線流程！');
            await _completeConnection(ghostDevice);

            state = state.copyWith(
              reconnectPhase: ReconnectPhase.none,
              isReconnecting: false,
              reconnectAttempts: 0,
            );

            return true;
          } else {
            devLog('快速重連', '⚠️ 幽靈連線狀態異常: $connState，嘗試重新連線...');

            // 嘗試對幽靈連線裝置進行連線
            await ghostDevice.connect(
              autoConnect: false,
              timeout: const Duration(seconds: 8),
            );

            final newState = await ghostDevice.connectionState.first.timeout(
              const Duration(seconds: 2),
            );

            if (newState == BluetoothConnectionState.connected) {
              devLog('快速重連', '✅ 幽靈連線重新連線成功！');
              await _completeConnection(ghostDevice);

              state = state.copyWith(
                reconnectPhase: ReconnectPhase.none,
                isReconnecting: false,
                reconnectAttempts: 0,
              );

              return true;
            }
          }
        } catch (e) {
          devLog('快速重連', '⚠️ 使用幽靈連線失敗: $e');

          // 清理幽靈連線
          try {
            devLog('快速重連', '🔧 清理幽靈連線...');
            await ghostDevice.disconnect();
            await Future.delayed(const Duration(seconds: 1));
          } catch (disconnectError) {
            devLog('快速重連', '⚠️ 清理幽靈連線失敗: $disconnectError');
          }
        }
      } else {
        devLog('快速重連', '📭 無幽靈連線');
      }
    }

    // ⭐⭐⭐ 步驟2：使用 fromId 直接連線 ⭐⭐⭐
    devLog('快速重連', '🚀 步驟2：使用 fromId 直接連線...');

    try {
      final quickDevice = BluetoothDevice.fromId(deviceId);

      final timeout = Platform.isIOS ? 8 : 5;

      await quickDevice.connect(
        autoConnect: false,
        timeout: Duration(seconds: timeout),
      );

      // 驗證連接狀態
      final connState = await quickDevice.connectionState.first.timeout(
        const Duration(seconds: 2),
      );

      if (connState == BluetoothConnectionState.connected) {
        devLog('快速重連', '✅ 快速重連成功！');

        await _completeConnection(quickDevice);

        state = state.copyWith(
          reconnectPhase: ReconnectPhase.none,
          isReconnecting: false,
          reconnectAttempts: 0,
        );

        return true;
      } else {
        devLog('快速重連', '❌ 連接狀態異常: $connState');
        return false;
      }
    } catch (e) {
      devLog('快速重連', '❌ 快速重連失敗: $e');
      devLog('快速重連', '→ 準備進入階段2（完整清理）');

      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ✅ 修改：排程重連（兩段式策略）
  // ═══════════════════════════════════════════════════════════════════════════

  void _scheduleReconnect(BluetoothDevice device) {
    _reconnectTimer?.cancel();
    _reconnectScanSubscription?.cancel();

    if (_reconnectAttempts >= _maxReconnectAttempts) {
      devLog('自動重連', '❌ 已達最大重連次數 ($_maxReconnectAttempts)，停止重連');
      _reconnectAttempts = 0;
      state = state.copyWith(
        isReconnecting: false,
        reconnectAttempts: 0,
        reconnectPhase: ReconnectPhase.none,
      );
      return;
    }

    _reconnectAttempts++;

    // ⭐⭐⭐ 根據階段決定等待時間和策略 ⭐⭐⭐
    final currentPhase = state.reconnectPhase;

    int waitSeconds;
    String strategyDesc;

    if (currentPhase == ReconnectPhase.quick) {
      // 階段1：快速重連，較短等待
      waitSeconds = Platform.isIOS ? 2 : 1;
      strategyDesc = '快速重連（利用記憶）';
    } else {
      // 階段2：完整清理，較長等待
      waitSeconds = Platform.isIOS ? 5 : 3;
      strategyDesc = '完整清理重連';
    }

    devLog(
      '自動重連',
      '⏳ ${waitSeconds}秒後開始第 $_reconnectAttempts/$_maxReconnectAttempts 次重連 [$strategyDesc]',
    );

    state = state.copyWith(
      isReconnecting: true,
      reconnectAttempts: _reconnectAttempts,
    );

    _reconnectTimer = Timer(Duration(seconds: waitSeconds), () async {
      if (_isIntentionalDisconnect) {
        devLog('自動重連', '✋ 使用者已手動斷線，取消重連');
        state = state.copyWith(
          isReconnecting: false,
          reconnectAttempts: 0,
          reconnectPhase: ReconnectPhase.none,
        );
        return;
      }

      if (_isConnected || _isConnecting) {
        devLog('自動重連', '已經連線或正在連線，取消重連');
        return;
      }

      // ⭐⭐⭐ 根據階段執行不同的重連策略 ⭐⭐⭐
      if (currentPhase == ReconnectPhase.quick) {
        // 階段1：嘗試快速重連
        final success = await _quickReconnect(device);

        if (!success) {
          // 快速重連失敗，切換到階段2
          devLog('自動重連', '⚠️ 階段1失敗，切換到階段2（完整清理）');

          state = state.copyWith(
            reconnectPhase: ReconnectPhase.full,
          );

          // 進入完整清理流程
          await _startFullCleanReconnect(device);
        }
      } else {
        // 階段2：完整清理重連
        await _startFullCleanReconnect(device);
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ✅ 新增：階段2 - 完整清理重連
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _startFullCleanReconnect(BluetoothDevice device) async {
    devLog('完整重連', '========== 階段2：完整清理重連 ==========');
    devLog('完整重連', '策略：disconnect + 等待 + 掃描');

    // ⭐⭐⭐ 步驟1：徹底清理藍牙狀態 ⭐⭐⭐
    try {
      devLog('完整重連', '🔧 執行 disconnect() 清理藍牙狀態...');
      await device.disconnect();
      devLog('完整重連', '✅ disconnect() 完成');

      // iOS 需要較長等待時間
      if (Platform.isIOS) {
        devLog('完整重連', '⏳ [iOS] 等待 3 秒清理狀態...');
        await Future.delayed(const Duration(seconds: 3));

        // 檢查系統連接
        try {
          final connectedDevices = FlutterBluePlus.connectedDevices;
          for (var dev in connectedDevices) {
            if (dev.remoteId.str == device.remoteId.str) {
              devLog('完整重連', '⚠️ 發現殘留連接，再次斷開');
              await dev.disconnect();
              await Future.delayed(const Duration(milliseconds: 500));
            }
          }
        } catch (e) {
          devLog('完整重連', '系統檢查失敗: $e');
        }

        devLog('完整重連', '✅ [iOS] 清理完成');
      } else {
        devLog('完整重連', '⏳ [Android] 等待 1 秒...');
        await Future.delayed(const Duration(seconds: 1));
      }
    } catch (e) {
      devLog('完整重連', '⚠️ disconnect 失敗: $e');
      // 即使失敗也要等待
      if (Platform.isIOS) {
        await Future.delayed(const Duration(seconds: 3));
      } else {
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    // ⭐⭐⭐ 步驟2：開始掃描 ⭐⭐⭐
    await _startReconnectScan(device);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ✅ 新增：iOS 專用的連線方法（使用 CBCentralManager 的 retrievePeripherals）
  // ═══════════════════════════════════════════════════════════════════════════

  /// iOS 專用：嘗試透過已知的設備 ID 直接連線
  /// 這利用了 iOS 的設備快取機制，不需要掃描
  Future<bool> connectToKnownDevice(String deviceId) async {
    if (!Platform.isIOS) {
      devLog('直接連線', '此方法僅適用於 iOS');
      return false;
    }

    devLog('直接連線', '🍎 [iOS] 嘗試連線到已知設備: $deviceId');

    try {
      final device = BluetoothDevice.fromId(deviceId);

      // 設定較長的超時時間
      await device.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 20),
      );

      // 驗證連線狀態
      final currentState = await device.connectionState.first;
      if (currentState == BluetoothConnectionState.connected) {
        devLog('直接連線', '🍎 [iOS] 連線成功！');
        await _completeConnection(device);
        return true;
      } else {
        devLog('直接連線', '🍎 [iOS] 連線狀態異常: $currentState');
        return false;
      }
    } catch (e) {
      devLog('直接連線', '🍎 [iOS] 連線失敗: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ✅ 修正：檢查系統幽靈連線（iOS 專用）
  // ═══════════════════════════════════════════════════════════════════════════

  /// 檢查 iOS 系統層是否有「幽靈連線」
  /// 返回：如果找到目標裝置的幽靈連線，返回該裝置；否則返回 null
  Future<BluetoothDevice?> _tryRetrieveSystemConnectedDevice(
    String targetRemoteId,
  ) async {
    devLog('幽靈連線檢查', '========== 開始檢查系統幽靈連線 ==========');
    devLog('幽靈連線檢查', '目標裝置 ID: $targetRemoteId');

    try {
      // ✅ 方法1：使用 connectedDevices（不需要 Service UUID，推薦！）
      devLog('幽靈連線檢查', '🔍 查詢 connectedDevices...');

      final connectedDevices = FlutterBluePlus.connectedDevices;
      devLog('幽靈連線檢查', '找到 ${connectedDevices.length} 個已連線裝置');

      for (var device in connectedDevices) {
        devLog('幽靈連線檢查', '  - ${device.platformName} (${device.remoteId.str})');

        if (device.remoteId.str == targetRemoteId) {
          devLog('幽靈連線檢查', '✅ 找到幽靈連線！裝置: ${device.platformName}');
          return device;
        }
      }

      // ✅ 方法2：如果有記住上次的 Service UUID，也可以用 systemDevices
      // 這是可選的，因為 connectedDevices 通常就夠用了
      if (Platform.isIOS && _lastConnectedServiceUuids.isNotEmpty) {
        devLog('幽靈連線檢查', '🔍 查詢 systemDevices (使用記住的 Service UUIDs)...');

        final systemDevices = await FlutterBluePlus.systemDevices(
          _lastConnectedServiceUuids,
        );
        devLog('幽靈連線檢查', '找到 ${systemDevices.length} 個系統層裝置');

        for (var device in systemDevices) {
          devLog(
            '幽靈連線檢查',
            '  - ${device.platformName} (${device.remoteId.str})',
          );

          if (device.remoteId.str == targetRemoteId) {
            devLog('幽靈連線檢查', '✅ 找到幽靈連線！裝置: ${device.platformName}');
            return device;
          }
        }
      }

      devLog('幽靈連線檢查', '❌ 未找到幽靈連線');
      return null;
    } catch (e) {
      devLog('幽靈連線檢查', '❌ 查詢失敗: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ✅ 新增：檢查系統層級的已連線裝置
  // ═══════════════════════════════════════════════════════════════════════════

  /// 檢查目標裝置是否已經在系統層級連線
  Future<BluetoothDevice?> findConnectedDevice(String targetDeviceId) async {
    try {
      final connectedDevices = FlutterBluePlus.connectedDevices;

      for (final device in connectedDevices) {
        if (device.remoteId.str == targetDeviceId) {
          devLog('系統檢查', '✅ 找到系統層級已連線裝置: ${device.platformName}');
          return device;
        }
      }

      devLog('系統檢查', '未找到已連線的目標裝置');
      return null;
    } catch (e) {
      devLog('系統檢查', '檢查失敗: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ✅ 開始重連掃描
  // ═══════════════════════════════════════════════════════════════════════════

  /// 使用 Device ID 直接連線（不需要掃描）
  Future<bool> connectToDeviceById(String deviceId) async {
    devLog('直接連線', '🚀 嘗試透過 ID 連線: $deviceId');

    try {
      // 從 ID 建立 BluetoothDevice 物件
      final device = BluetoothDevice.fromId(deviceId);
      await connectToDevice(device, isAutoReconnect: false);
      return _isConnected;
    } catch (e) {
      devLog('直接連線', '❌ 透過 ID 連線失敗: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ✅ 重連掃描邏輯（簡化優化版）
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _startReconnectScan(BluetoothDevice targetDevice) async {
    final targetDeviceId = targetDevice.remoteId.str;
    final targetDeviceName = targetDevice.platformName;

    // devLog('自動重連', '========== 開始重連流程 ==========');
    // devLog('自動重連', '目標: $targetDeviceName ($targetDeviceId)');

    devLog('掃描重連', '========== 開始掃描重連 =========='); // ⭐ 加這行
    devLog('掃描重連', '目標: $targetDeviceName ($targetDeviceId)'); // ⭐ 改這行

    // ⭐⭐⭐ 策略：iOS 和 Android 統一使用掃描 ⭐⭐⭐
    // 不再嘗試直接連線，因為在狀態未清理時會失敗

    // 確保停止之前的掃描
    try {
      await FlutterBluePlus.stopScan();
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (_) {}

    devLog('自動重連', '🔍 開始掃描尋找裝置...');

    bool deviceFound = false;

    // ⭐ 縮短掃描時間：從 30 秒改為 15 秒
    const scanTimeout = 15;

    final scanTimeoutTimer = Timer(Duration(seconds: scanTimeout), () {
      if (!deviceFound) {
        devLog('自動重連', '⏰ 掃描 $scanTimeout 秒超時，未找到裝置');
        _reconnectScanSubscription?.cancel();
        FlutterBluePlus.stopScan();

        if (!_isIntentionalDisconnect) {
          _scheduleReconnect(targetDevice);
        }
      }
    });

    // 開始掃描
    FlutterBluePlus.startScan(timeout: Duration(seconds: scanTimeout));

    _reconnectScanSubscription = FlutterBluePlus.scanResults.listen((
      results,
    ) async {
      if (deviceFound || _isIntentionalDisconnect) return;

      for (final result in results) {
        if (result.device.remoteId.str == targetDeviceId && result.rssi > -85) {
          deviceFound = true;

          devLog(
            '自動重連',
            '✅ 找到目標裝置: ${result.device.platformName} (RSSI: ${result.rssi})',
          );

          // 停止掃描
          scanTimeoutTimer.cancel();
          _reconnectScanSubscription?.cancel();

          try {
            await FlutterBluePlus.stopScan();
          } catch (e) {
            devLog('自動重連', '⚠️ stopScan 失敗: $e');
          }

          // ⭐ 重要：掃描後等待，讓系統穩定
          if (Platform.isIOS) {
            devLog('自動重連', '⏳ [iOS] 掃描後等待 1 秒...');
            await Future.delayed(const Duration(milliseconds: 1000));
          } else {
            devLog('自動重連', '⏳ [Android] 掃描後等待 500ms...');
            await Future.delayed(const Duration(milliseconds: 500));
          }

          devLog('自動重連', '🔄 開始連線...');
          await connectToDevice(result.device, isAutoReconnect: true);

          break;
        }
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ✅ 新增：完成連線流程（供直接連線使用）
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _completeConnection(BluetoothDevice device) async {
    try {
      devLog('連線流程', '✅ 連線成功，開始探索服務...');

      await Future.delayed(const Duration(milliseconds: 500));

      List<BluetoothService> discoveredServices = await device
          .discoverServices();
      devLog('連線流程', '✅ 發現 ${discoveredServices.length} 個服務');

      // ✅ 新增：記住這些服務的 UUID（用於下次幽靈連線檢查）
      _lastConnectedServiceUuids = discoveredServices
          .map((s) => s.uuid)
          .toList();

      await Future.delayed(const Duration(milliseconds: 300));

      _currentDeviceId = device.remoteId.str;
      _healthCalculator = HealthCalculateDeviceID(3);
      await _healthCalculator!.reset(_currentDeviceId!);

      _isConnecting = false;
      _isConnected = true;
      _lastConnectedTime = DateTime.now();
      _lastConnectedDevice = device;
      _reconnectAttempts = 0;

      devLog('連線流程', '✅ 連線完成');

      state = state.copyWith(
        connectedDevice: device,
        services: discoveredServices,
        isReconnecting: false,
        reconnectAttempts: 0,
      );

      _setupConnectionStateListener(device);

      printDebugStatus();
    } catch (e) {
      devLog('連線流程', '❌ 完成連線流程失敗: $e');
      _isConnecting = false;
      _isConnected = false;

      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ✅ 新增：取得上次連線的裝置 ID（可用於持久化）
  // ═══════════════════════════════════════════════════════════════════════════

  String? get lastConnectedDeviceId => _lastConnectedDevice?.remoteId.str;
  String? get lastConnectedDeviceName => _lastConnectedDevice?.platformName;

  /// 設定上次連線的裝置（從持久化資料恢復）
  void setLastConnectedDeviceId(String deviceId, {String? deviceName}) {
    _lastConnectedDevice = BluetoothDevice.fromId(deviceId);
    devLog('裝置記憶', '已設定上次裝置: $deviceId ${deviceName ?? ""}');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ✅ 取消重連（更新版）
  // ═══════════════════════════════════════════════════════════════════════════

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    _reconnectScanSubscription?.cancel();
    _reconnectScanSubscription = null;

    // 停止重連掃描
    try {
      FlutterBluePlus.stopScan();
    } catch (_) {}

    _reconnectAttempts = 0;
    state = state.copyWith(
      isReconnecting: false,
      reconnectAttempts: 0,
      reconnectPhase: ReconnectPhase.none, // ⭐ 加這行
    );
    devLog('自動重連', '已取消自動重連');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 斷線（手動斷線不會觸發重連）
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> disconnectFromDevice() async {
    _disconnectAttempts++;
    devLog('斷線流程', '=== 第 $_disconnectAttempts 次斷線（手動）===');

    if (_isDisconnecting) {
      devLog('斷線流程', '⚠️ 已經在斷線中，忽略此次請求');
      return;
    }

    _isDisconnecting = true;
    _isIntentionalDisconnect = true;
    _cancelReconnect();

    printDebugStatus();

    _isConnecting = false;
    _isConnected = false;

    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;

    // 關閉所有通知
    if (state.connectedDevice != null && _notifySubscriptions.isNotEmpty) {
      devLog('斷線流程', '🔔 開始關閉 ${_notifySubscriptions.length} 個通知訂閱...');

      for (var entry in _notifySubscriptions.entries) {
        try {
          await entry.value.cancel();
          devLog('斷線流程', '已取消 Stream 訂閱: ${entry.key}');
        } catch (e) {
          devLog('斷線流程', '取消 Stream 訂閱失敗: $e');
        }
      }

      for (var service in state.services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.properties.notify ||
              characteristic.properties.indicate) {
            if (_notifySubscriptions.containsKey(characteristic.uuid)) {
              try {
                devLog('斷線流程', '🔕 關閉 BLE 通知: ${characteristic.uuid}');
                await characteristic.setNotifyValue(false);
                devLog('斷線流程', '✅ 已關閉 BLE 通知: ${characteristic.uuid}');
                await Future.delayed(const Duration(milliseconds: 200));
              } catch (e) {
                devLog('斷線流程', '⚠️ 關閉 BLE 通知失敗: ${characteristic.uuid} - $e');
              }
            }
          }
        }
      }

      _notifySubscriptions.clear();

      devLog('斷線流程', '⏳ 等待裝置處理通知關閉...');
      await Future.delayed(const Duration(milliseconds: 500));
    }

    try {
      await state.connectedDevice?.disconnect();
      devLog('斷線流程', '已斷開藍牙連線');
    } catch (e) {
      devLog('斷線流程', '斷開連線錯誤: $e');
    }

    await Future.delayed(const Duration(milliseconds: 500));

    if (_healthCalculator != null && _currentDeviceId != null) {
      await _healthCalculator!.dispose(_currentDeviceId!);
      devLog('斷線流程', '已清理 SDK: $_currentDeviceId');
    }
    _healthCalculator = null;
    _currentDeviceId = null;

    _firstGroupPacket = null;
    _firstGroupTimestamp = null;
    _isWaitingForSecond = false;

    state = state.copyWith(
      clearDevice: true,
      services: [],
      readValues: {},
      notifyValues: {},
      isReconnecting: false,
      reconnectAttempts: 0,
    );

    _isDisconnecting = false;

    // ✅ 記錄斷線時間
    _lastDisconnectTime = DateTime.now();

    devLog('斷線流程', '✅ 完整斷線清理完成');
    printDebugStatus();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ✅ 修改：connectToLastDevice（針對 iOS 優化）
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> connectToLastDevice() async {
    if (_lastConnectedDevice == null) {
      devLog('快速重連', '❌ 沒有上次連線的裝置資訊');
      return false;
    }

    // ✅ 檢查保護機制
    if (!await canConnect()) {
      devLog('快速重連', '⚠️ 操作被保護機制阻擋');
      return false;
    }

    final targetDeviceId = _lastConnectedDevice!.remoteId.str;
    final targetDeviceName = _lastConnectedDevice!.platformName;

    devLog('快速重連', '========== 手動快速重連 ==========');
    devLog('快速重連', '目標: $targetDeviceName ($targetDeviceId)');

    // ⭐⭐⭐ 步驟1：檢查幽靈連線（iOS 專用）⭐⭐⭐
    if (Platform.isIOS) {
      devLog('快速重連', '🍎 [iOS] 檢查幽靈連線...');

      final ghostDevice = await _tryRetrieveSystemConnectedDevice(
        targetDeviceId,
      );

      if (ghostDevice != null) {
        devLog('快速重連', '✅ 發現幽靈連線！');

        try {
          final connState = await ghostDevice.connectionState.first.timeout(
            const Duration(seconds: 2),
          );

          if (connState == BluetoothConnectionState.connected) {
            devLog('快速重連', '✅ 幽靈連線狀態正常，直接使用！');
            await _completeConnection(ghostDevice);
            return _isConnected;
          } else {
            devLog('快速重連', '⚠️ 幽靈連線狀態: $connState，嘗試連線...');
            await ghostDevice.connect(
              autoConnect: false,
              timeout: const Duration(seconds: 10),
            );
            await _completeConnection(ghostDevice);
            return _isConnected;
          }
        } catch (e) {
          devLog('快速重連', '⚠️ 幽靈連線失敗: $e，清理後繼續...');
          try {
            await ghostDevice.disconnect();
          } catch (_) {}
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }

    // ⭐⭐⭐ 步驟2：檢查 connectedDevices ⭐⭐⭐
    final existingDevice = await findConnectedDevice(targetDeviceId);
    if (existingDevice != null) {
      devLog('快速重連', '✅ 裝置已在系統層級連線，直接使用');
      await _completeConnection(existingDevice);
      return _isConnected;
    }

    // ⭐⭐⭐ 步驟3：嘗試直接連線（不掃描）⭐⭐⭐
    devLog('快速重連', '🚀 嘗試直接連線（不掃描）...');

    try {
      final device = BluetoothDevice.fromId(targetDeviceId);
      final timeout = Platform.isIOS ? 15 : 10;

      await device.connect(
        autoConnect: false,
        timeout: Duration(seconds: timeout),
      );

      final connState = await device.connectionState.first.timeout(
        const Duration(seconds: 2),
      );

      if (connState == BluetoothConnectionState.connected) {
        devLog('快速重連', '✅ 直接連線成功！');
        await _completeConnection(device);
        return _isConnected;
      }
    } catch (e) {
      devLog('快速重連', '⚠️ 直接連線失敗: $e，改用掃描模式');
    }

    // ⭐⭐⭐ 步驟4：掃描模式（最後手段）⭐⭐⭐
    devLog('快速重連', '🔍 使用掃描模式...');

    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 500));

    final quickScanSeconds = Platform.isIOS ? 15 : 10;
    bool deviceFound = false;
    BluetoothDevice? foundDevice;

    final completer = Completer<bool>();

    final timeoutTimer = Timer(Duration(seconds: quickScanSeconds), () {
      if (!completer.isCompleted) {
        devLog('快速重連', '⏰ 掃描超時，未找到裝置');
        completer.complete(false);
      }
    });

    FlutterBluePlus.startScan(
      timeout: Duration(seconds: quickScanSeconds),
    );

    final subscription = FlutterBluePlus.scanResults.listen((results) {
      if (deviceFound || completer.isCompleted) return;

      for (final result in results) {
        if (result.device.remoteId.str == targetDeviceId) {
          deviceFound = true;
          foundDevice = result.device;
          devLog(
            '快速重連',
            '✅ 找到裝置: ${result.device.platformName} (RSSI: ${result.rssi})',
          );

          if (!completer.isCompleted) {
            completer.complete(true);
          }
          break;
        }
      }
    });

    final found = await completer.future;

    timeoutTimer.cancel();
    await subscription.cancel();
    await FlutterBluePlus.stopScan();

    if (!found || foundDevice == null) {
      devLog('快速重連', '❌ 裝置不在範圍內');
      return false;
    }

    final waitTime = Platform.isIOS ? 1500 : 1000;
    devLog('快速重連', '⏳ 等待裝置準備 (${waitTime}ms)...');
    await Future.delayed(Duration(milliseconds: waitTime));

    devLog('快速重連', '🚀 開始連線...');
    await connectToDevice(foundDevice!, isAutoReconnect: false);

    return _isConnected;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 讀取/寫入
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> readCharacteristic(BluetoothCharacteristic c) async {
    try {
      List<int> value = await c.read();
      final newReadValues = Map<Guid, List<int>>.from(state.readValues);
      newReadValues[c.uuid] = value;
      state = state.copyWith(readValues: newReadValues);
      devLog('讀取特徵', 'UUID: ${c.uuid}, 值: $value');
    } catch (e) {
      devLog('讀取特徵錯誤', '$e');
    }
  }

  Future<void> writeCharacteristic(BluetoothCharacteristic c) async {
    try {
      await c.write(utf8.encode('Hello Flutter'), withoutResponse: true);
      devLog('寫入特徵', 'UUID: ${c.uuid}, 已寫入');
    } catch (e) {
      devLog('寫入特徵錯誤', '$e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 通知訂閱
  // ═══════════════════════════════════════════════════════════════════════════

  bool isNotifying(Guid uuid) => _notifySubscriptions.containsKey(uuid);

  Future<void> toggleNotify(BluetoothCharacteristic c) async {
    if (_isTogglingNotify) {
      devLog('通知', '⚠️ 正在處理通知操作，忽略此次請求');
      return;
    }

    if (!_isConnected) {
      devLog('通知', '⚠️ 未連線，無法操作通知');
      return;
    }

    _isTogglingNotify = true;

    try {
      if (_notifySubscriptions.containsKey(c.uuid)) {
        try {
          await _notifySubscriptions[c.uuid]!.cancel();
        } catch (e) {
          devLog('取消通知', '取消訂閱失敗: $e');
        }

        try {
          await c.setNotifyValue(false);
        } catch (e) {
          devLog('取消通知', '關閉通知失敗: $e');
        }

        _notifySubscriptions.remove(c.uuid);
        await Future.delayed(const Duration(milliseconds: 100));
        devLog('取消通知', '✅ UUID: ${c.uuid}');
      } else {
        const maxRetries = 3;
        for (int attempt = 1; attempt <= maxRetries; attempt++) {
          try {
            devLog('啟用通知', '嘗試 $attempt/$maxRetries - UUID: ${c.uuid}');

            if (attempt > 1) {
              await Future.delayed(Duration(milliseconds: 300 * attempt));
            }

            // await c.setNotifyValue(true);

            // final sub = c.lastValueStream.listen((value) async {
            //   // if (!_isConnected) return;

            //   // // devLog('原始數據', value.toString());
            //   // // await _processAndUpsample(value);

            //   // final newNotifyValues = Map<Guid, List<int>>.from(
            //   //   state.notifyValues,
            //   // );
            //   // newNotifyValues[c.uuid] = value;
            //   // state = state.copyWith(notifyValues: newNotifyValues);
            // });

            // _notifySubscriptions[c.uuid] = sub;
            // devLog('啟用通知', '✅ 成功 - UUID: ${c.uuid}');

            // if (c.uuid.toString().toUpperCase().contains('FFF4')) {
            //   await Future.delayed(const Duration(milliseconds: 200));
            //   try {
            //     final writeCharacteristic = state.services
            //         .expand((s) => s.characteristics)
            //         .firstWhere(
            //           (ch) => ch.uuid.toString().toUpperCase().contains('FFF5'),
            //         );

            //     if (writeCharacteristic.properties.write) {
            //       await writeCharacteristic.write(
            //         getTimeSyncCommand(),
            //         withoutResponse: false,
            //       );
            //       devLog('時間同步', '成功發送時間指令到 FFF5');
            //     }
            //   } catch (e) {
            //     devLog('時間同步錯誤', '$e');
            //   }
            // }

            break;
          } catch (e) {
            devLog('啟用通知錯誤', '嘗試 $attempt/$maxRetries 失敗: $e');

            if (attempt == maxRetries) {
              devLog('啟用通知錯誤', '❌ 已達最大重試次數');
            }
          }
        }
      }
    } finally {
      _isTogglingNotify = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 時間同步指令
  // ═══════════════════════════════════════════════════════════════════════════

  // Uint8List getTimeSyncCommand() {
  //   final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 10;
  //   final byteData = ByteData(8)..setInt64(0, timestamp, Endian.little);
  //   final command = Uint8List(6);
  //   command[0] = 0xfc;
  //   command[1] = byteData.getUint8(0);
  //   command[2] = byteData.getUint8(1);
  //   command[3] = byteData.getUint8(2);
  //   command[4] = byteData.getUint8(3);
  //   command[5] = byteData.getUint8(4);
  //   return command;
  // }

  Uint8List getTimeSyncCommand() {
    final now = DateTime.now();

    devLog('時間同步', "當前本地時間: $now");

    // 1. 獲取 UTC 時間戳
    int timestamp = now.millisecondsSinceEpoch;

    devLog('時間同步', "當前時間戳 (UTC): $timestamp");

    // 2. 加上本地時區偏移 (例如台灣是 +8小時的毫秒數)
    timestamp += now.timeZoneOffset.inMilliseconds;

    devLog('時間同步', "加上時區偏移後的時間戳: $timestamp");

    // 3. 轉成 10ms 單位
    timestamp = timestamp ~/ 10;

    final byteData = ByteData(8)..setInt64(0, timestamp, Endian.little);
    final command = Uint8List(6);
    command[0] = 0xfc;
    command[1] = byteData.getUint8(0);
    command[2] = byteData.getUint8(1);
    command[3] = byteData.getUint8(2);
    command[4] = byteData.getUint8(3);
    command[5] = byteData.getUint8(4);

    devLog('時間同步', "寫入時間戳 (Local): $timestamp"); // Debug 用
    return command;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 插值控制
  // ═══════════════════════════════════════════════════════════════════════════

  // void setInterpolationEnabled(bool enabled) {
  //   state = state.copyWith(enableInterpolation: enabled);
  //   devLog('插值設定', '插值功能: ${enabled ? "開啟" : "關閉"}');
  // }

  // void toggleInterpolation() {
  //   final newValue = !state.enableInterpolation;
  //   state = state.copyWith(enableInterpolation: newValue);
  //   devLog('插值設定', '插值功能: ${newValue ? "開啟" : "關閉"}');
  // }
  // 修改 setInterpolationEnabled 和 toggleInterpolation

  void setInterpolationEnabled(bool enabled) {
    // ✅ 切換時重置插值相關狀態
    _resetInterpolationState();

    state = state.copyWith(enableInterpolation: enabled);
    devLog('插值設定', '插值功能: ${enabled ? "開啟" : "關閉"}');
  }

  void toggleInterpolation() {
    // ✅ 切換時重置插值相關狀態
    _resetInterpolationState();

    final newValue = !state.enableInterpolation;
    state = state.copyWith(enableInterpolation: newValue);
    devLog('插值設定', '插值功能: ${newValue ? "開啟" : "關閉"}');
  }

  /// 重置插值相關狀態
  void _resetInterpolationState() {
    _firstGroupPacket = null;
    _firstGroupTimestamp = null;
    _isWaitingForSecond = false;
    devLog('插值設定', '已重置插值狀態');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 數據處理
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _processAndUpsample(List<int> currentPacket) async {
    final baseTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 10;
    await _processSinglePacketWithTimestamp(currentPacket, baseTimestamp);
  }

  Future<void> _processSinglePacketWithTimestamp(
    List<int> packetData,
    int baseTimestamp,
  ) async {
    if (_healthCalculator == null || _currentDeviceId == null) return;
    if (!_isConnected) return;

    final dataType = ref
        .read(filteredFirstRawDataProvider.notifier)
        .filterData(packetData, ref);

    if (dataType == DataType.first) {
      final dataValue = ref.read(filteredFirstRawDataProvider);
      final currentPacket = List<int>.from(dataValue.splitRawData);
      final currentTimestamp = _bytesToTimestamp(currentPacket);

      // ✅ 加入 Debug Log
      devLog(
        '封包處理',
        '插值=${state.enableInterpolation}, 原始封包數=$_originalPacketCount, 插值封包數=$_interpolatedPacketCount',
      );

      if (!state.enableInterpolation) {
        await _healthCalculator!.splitPackage(
          Uint8List.fromList(currentPacket),
          _currentDeviceId!,
        );

        // ✅ 關閉插值：只處理一次
        devLog('封包處理', '🔵 關閉插值模式：呼叫 splitPackage 1 次');

        ref
            .read(interpolatedDataProvider.notifier)
            .addPacket(
              InterpolatedPacket(
                data: currentPacket,
                timestamp: currentTimestamp,
                isInterpolated: false,
              ),
            );

        await _updateUIAndProvider();
        _originalPacketCount++;
        _packetsInCurrentSecond++;
        return;
      }

      if (_firstGroupPacket == null) {
        _firstGroupPacket = currentPacket;
        _firstGroupTimestamp = currentTimestamp;
        _isWaitingForSecond = true;

        await _healthCalculator!.splitPackage(
          Uint8List.fromList(currentPacket),
          _currentDeviceId!,
        );

        ref
            .read(interpolatedDataProvider.notifier)
            .addPacket(
              InterpolatedPacket(
                data: currentPacket,
                timestamp: currentTimestamp,
                isInterpolated: false,
              ),
            );

        await _updateUIAndProvider();
        _originalPacketCount++;
        _packetsInCurrentSecond++;
      } else if (_isWaitingForSecond) {
        _isWaitingForSecond = false;

        final midpoint = _firstGroupTimestamp! + (2 << 16);

        final interp1 = List<int>.from(_firstGroupPacket!);
        _updateTimestampInPacket(interp1, midpoint);

        await _healthCalculator!.splitPackage(
          Uint8List.fromList(interp1),
          _currentDeviceId!,
        );

        ref
            .read(interpolatedDataProvider.notifier)
            .addPacket(
              InterpolatedPacket(
                data: interp1,
                timestamp: midpoint,
                isInterpolated: true,
              ),
            );
        _interpolatedPacketCount++;
        _packetsInCurrentSecond++;

        await _healthCalculator!.splitPackage(
          Uint8List.fromList(currentPacket),
          _currentDeviceId!,
        );

        ref
            .read(interpolatedDataProvider.notifier)
            .addPacket(
              InterpolatedPacket(
                data: currentPacket,
                timestamp: currentTimestamp,
                isInterpolated: false,
              ),
            );
        _originalPacketCount++;
        _packetsInCurrentSecond++;

        await _updateUIAndProvider();

        _firstGroupPacket = currentPacket;
        _firstGroupTimestamp = currentTimestamp;
      } else {
        final timeDiff = currentTimestamp - _firstGroupTimestamp!;

        int midpoint;
        if (timeDiff > 0 && timeDiff < 243000) {
          midpoint = _firstGroupTimestamp! + (timeDiff ~/ 2);
        } else {
          midpoint = _firstGroupTimestamp! + (2 << 16);
        }

        final interp = List<int>.from(_firstGroupPacket!);
        _updateTimestampInPacket(interp, midpoint);

        await _healthCalculator!.splitPackage(
          Uint8List.fromList(interp),
          _currentDeviceId!,
        );

        ref
            .read(interpolatedDataProvider.notifier)
            .addPacket(
              InterpolatedPacket(
                data: interp,
                timestamp: midpoint,
                isInterpolated: true,
              ),
            );
        _interpolatedPacketCount++;
        _packetsInCurrentSecond++;

        await _healthCalculator!.splitPackage(
          Uint8List.fromList(currentPacket),
          _currentDeviceId!,
        );

        ref
            .read(interpolatedDataProvider.notifier)
            .addPacket(
              InterpolatedPacket(
                data: currentPacket,
                timestamp: currentTimestamp,
                isInterpolated: false,
              ),
            );
        _originalPacketCount++;
        _packetsInCurrentSecond++;

        await _updateUIAndProvider();

        _firstGroupPacket = currentPacket;
        _firstGroupTimestamp = currentTimestamp;
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 輔助方法
  // ═══════════════════════════════════════════════════════════════════════════

  int _bytesToTimestamp(List<int> packet) {
    if (packet.length < 6) return 0;
    return packet[1] |
        (packet[2] << 8) |
        (packet[3] << 16) |
        (packet[4] << 24) |
        (packet[5] << 32);
  }

  void _updateTimestampInPacket(List<int> packet, int timestamp) {
    if (packet.length < 6) return;
    packet[1] = timestamp & 0xFF;
    packet[2] = (timestamp >> 8) & 0xFF;
    packet[3] = (timestamp >> 16) & 0xFF;
    packet[4] = (timestamp >> 24) & 0xFF;
    packet[5] = (timestamp >> 32) & 0xFF;
  }

  Future<void> _updateUIAndProvider() async {
    final results = _extractAllResults();

    ref
        .read(healthDataProvider.notifier)
        .normalUpdate(
          hr: results['hr'],
          br: results['br'],
          gyroX: results['gyroX'],
          gyroY: results['gyroY'],
          gyroZ: results['gyroZ'],
          temp: (results['temp'] is num) ? results['temp'].toDouble() : 0,
          hum: (results['hum'] is num) ? results['hum'].toDouble() : 0,
          spO2: results['spO2'],
          step: results['step'],
          power: results['power'],
          time: results['time'],
          hrFiltered: (results['hrFiltered'] is List)
              ? results['hrFiltered'].map((e) => (e as num).toDouble()).toList()
              : const [],
          brFiltered: (results['brFiltered'] is List)
              ? results['brFiltered'].map((e) => (e as num).toDouble()).toList()
              : const [],
          isWearing: results['isWearing'] == 1 || results['isWearing'] == true,
          rawData: (results['rawData'] is List)
              ? results['rawData'].map((e) => (e as num).toInt()).toList()
              : const [],
          type: results['type'],
          fftOut: results['fftOut'] is List
              ? results['fftOut']?.map((e) => (e as num).toDouble()).toList()
              : null,
          petPose: results['petPose'],
        );
  }

  Map<String, dynamic> _extractAllResults() {
    final timestamp =
        _healthCalculator?.getTimeStamp() ??
        DateTime.now().millisecondsSinceEpoch ~/ 10;

    return {
      'hr': _healthCalculator?.getHRValue() ?? 0,
      'br': _healthCalculator?.getBRValue() ?? 0,
      'gyroX': _healthCalculator?.getGyroValueX() ?? 0,
      'gyroY': _healthCalculator?.getGyroValueY() ?? 0,
      'gyroZ': _healthCalculator?.getGyroValueZ() ?? 0,
      'temp': _healthCalculator?.getTempValue() ?? 0,
      'hum': _healthCalculator?.getHumValue() ?? 0,
      'spO2': _healthCalculator?.getSpO2Value() ?? 0,
      'step': _healthCalculator?.getStepValue() ?? 0,
      'power': _healthCalculator?.getPowerValue() ?? 0,
      'time': timestamp,
      'hrFiltered': _healthCalculator?.getHRFiltered() ?? [],
      'brFiltered': _healthCalculator?.getBRFiltered() ?? [],
      'isWearing': _healthCalculator?.getIsWearing() ?? false,
      'rawData': _healthCalculator?.getRawData() ?? [],
      'type': _healthCalculator?.getType() ?? 0,
      'fftOut': _healthCalculator?.getFFTOut(),
      'petPose': _healthCalculator?.getPetPoseValue(),
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 清理（更新版）
  // ═══════════════════════════════════════════════════════════════════════════

  void cleanup() {
    _cancelReconnect();

    ref.read(interpolatedDataProvider.notifier).clear();

    _firstGroupPacket = null;
    _firstGroupTimestamp = null;
    _isWaitingForSecond = false;

    _isConnecting = false;
    _isConnected = false;
    _isDisconnecting = false;
    _isTogglingNotify = false;
    _isIntentionalDisconnect = true;

    _lastConnectedServiceUuids.clear();

    _statsTimer?.cancel();
    disconnectFromDevice();

    for (var sub in _notifySubscriptions.values) {
      sub.cancel();
    }
    _notifySubscriptions.clear();
  }

  @override
  void dispose() {
    cleanup();
    super.dispose();
  }
}
