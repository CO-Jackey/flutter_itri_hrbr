import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_itri_hrbr/helper/devLog.dart';
import 'package:flutter_itri_hrbr/provider/health_provider.dart';
import 'package:flutter_itri_hrbr/services/HealthCalculate_Device_ID.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

class NormalDataPage extends ConsumerStatefulWidget {
  const NormalDataPage({super.key});

  @override
  ConsumerState<NormalDataPage> createState() => _NormalDataPageState();
}

class _NormalDataPageState extends ConsumerState<NormalDataPage> {
  int HR = 0; // 心率
  int BR = 0; // 呼吸率
  int BR_fun = 0; // 呼吸率函數值
  int GYRO_X = 0; // 假設這是陀螺儀的 X 軸數據
  int GYRO_Y = 0; // 假設這是陀螺儀的 Y 軸數據
  int GYRO_Z = 0; // 假設這是陀螺儀的 Z 軸數據
  dynamic TEMP = 0; // 溫度
  dynamic HUM = 0; // 濕度
  dynamic SPO2 = 0; // RRI數據
  dynamic STEP = 0; // 步數數據
  dynamic POWER = 0; // 電量數據
  dynamic TIME = 0; // 時間戳
  dynamic hrFiltered = []; // 心率波動團表數據
  dynamic brFiltered = []; // 呼吸波動團表數據
  dynamic isWearing = false; //
  dynamic RawData = []; //
  dynamic type = 0; //
  dynamic FFTOut = []; //
  dynamic petPose; // 寵物姿勢

  // --- 新增這一行 ---
  // HealthCalculate? _healthCalculator;
  // HealthCalculateDeviceID? _healthCalculator;

  // ✅ 改用 Map 管理（與 muti_mac 一致）
  final Map<String, HealthCalculateDeviceID> _calculators = {};

  BluetoothDevice? _lastConnectedDevice; // ✅ 新增：用來記住剛斷線的裝置

  // ✅ 新增：用來標記是否為「手動」斷線
  bool _isIntentionalDisconnect = false;

  // ✅ 新增：標記是否正在連線過程中
  bool _isConnecting = false;

  // 在 class 中新增：
  bool _isDisconnecting = false;

  int _reconnectAttempts = 0; // 重連嘗試次數
  static const int _maxReconnectAttempts = 3; // 最大重連次數

  //---------------------------

  Uint8List getTimeCommand() {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 10;
    final byteData = ByteData(8)..setInt64(0, timestamp, Endian.little);
    final byteArray = Uint8List(6)
      ..[0] = 0xfc
      ..[1] = byteData.getUint8(0)
      ..[2] = byteData.getUint8(1)
      ..[3] = byteData.getUint8(2)
      ..[4] = byteData.getUint8(3)
      ..[5] = byteData.getUint8(4);
    return byteArray;
  }

  //----------------------------------

  List<BluetoothService> _services = [];
  BluetoothDevice? _connectedDevice;

  // 為了清晰起見，重新命名訂閱變數
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;

  // 用於儲存特徵的讀取值和通知值
  Map<Guid, List<int>> _readValues = {};
  Map<Guid, StreamSubscription<List<int>>> _notifySubscriptions = {};
  Map<Guid, List<int>> _notifyValues = {};

  // --- 以下是您原有的方法 (基本不變) ---
  Future<bool> _requestPermissions() async {
    // 在 Android 31 (S) 以上版本，需要請求藍牙掃描和連接權限
    if (Platform.isAndroid) {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
      // 檢查是否所有權限都已授予
      if (statuses[Permission.bluetoothScan] == PermissionStatus.granted &&
          statuses[Permission.bluetoothConnect] == PermissionStatus.granted) {
        return true;
      }
    } else if (Platform.isIOS) {
      // iOS 會在 Info.plist 中自動處理，但我們也可以明確請求
      // permission_handler 在 iOS 上會對應 Info.plist 的設定來請求
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetooth,
        Permission.locationWhenInUse, // 掃描也可能需要位置權限
      ].request();
      if (statuses[Permission.bluetooth] == PermissionStatus.granted) {
        return true;
      }
    }
    return false; // 如果權限被拒絕，返回 false
  }

  // ✅ 工具方法：取得或建立計算器（不會重複 new）
  HealthCalculateDeviceID _getCalculator(String deviceId) {
    return _calculators.putIfAbsent(deviceId, () {
      devLog('SDK', '🆕 為裝置 $deviceId 建立新的 HealthCalculateDeviceID');
      return HealthCalculateDeviceID(3);
    });
  }

  // ✅ 工具方法：取得當前裝置的計算器（可能為 null）
  HealthCalculateDeviceID? get _healthCalculator {
    if (_connectedDevice == null) return null;
    return _calculators[_connectedDevice!.remoteId.str];
  }

  // 修改方法簽名，加入 isAutoConnect 參數，預設為 false (手動連線)
  // Future<void> _connectToDevice(
  //   BluetoothDevice device, {
  //   bool isAutoConnect = false,
  // }) async {
  //   // 0. 防止重複監聽，先取消舊的
  //   await _connectionStateSubscription?.cancel();
  //   _connectionStateSubscription = null; // ✅ 新增：確保清空

  //   _isIntentionalDisconnect = false;
  //   _isConnecting = true;

  //   // ❌ 移除這裡的監聽器建立
  //   // _connectionStateSubscription = device.connectionState.listen(...);

  //   try {
  //     // 2. 根據模式選擇連線方式
  //     if (isAutoConnect) {
  //       devLog('連線模式', '啟動自動連線 (等待裝置出現...)');
  //       await device.connect(autoConnect: true, mtu: null);

  //       devLog('連線模式', '正在等待連線建立...');
  //       await device.connectionState
  //           .where((val) {
  //             devLog('連線狀況', '$val');
  //             return val == BluetoothConnectionState.connected;
  //           })
  //           .first;
  //       devLog('連線模式', '裝置已成功連線！');
  //     } else {
  //       devLog('連線模式', '啟動手動連線 (超時設定 15秒)');
  //       await device.connect(
  //         autoConnect: true,
  //         // timeout: const Duration(seconds: 15),
  //         mtu: null,
  //       );
  //     }

  //     // 3. 連接成功後，探索服務
  //     devLog('連線模式', '開始探索服務...');
  //     List<BluetoothService> discoveredServices = await device.discoverServices();
  //     devLog('連線模式', '服務探索完成');

  //     // 4. 更新 UI
  //     if (mounted) {
  //       setState(() {
  //         _connectedDevice = device;
  //         _services = discoveredServices;
  //         _healthCalculator = HealthCalculateDeviceID(3);
  //       });

  //       await _autoSubscribeFFF4(device, discoveredServices);
  //     }

  //     // ✅ 所有流程完成後，才建立斷線監聽器
  //     _isConnecting = false;
  //     devLog('連線模式', '✅ 連線流程完成，開始監聽斷線事件');

  //     _connectionStateSubscription = device.connectionState.listen((state) {
  //       if (state == BluetoothConnectionState.disconnected) {
  //         devLog('監聽器', '裝置斷開');

  //         _lastConnectedDevice = device;

  //         if (mounted) {
  //           setState(() {
  //             _connectedDevice = null;
  //             _services = [];
  //             _readValues.clear();
  //             _notifyValues.clear();
  //             for (var sub in _notifySubscriptions.values) {
  //               sub.cancel();
  //             }
  //             _notifySubscriptions.clear();
  //           });
  //         }

  //         if (!_isIntentionalDisconnect) {
  //           devLog('自動重連', '偵測到意外斷線，3秒後啟動背景重連...');
  //           Future.delayed(const Duration(seconds: 3), () {
  //             if (!_isIntentionalDisconnect && mounted) {
  //               _connectToDevice(_lastConnectedDevice!, isAutoConnect: true);
  //             }
  //           });
  //         } else {
  //           devLog('監聯器', '使用者手動斷線，不執行重連。');
  //         }
  //       }
  //     });

  //   } catch (e, stackTrace) {
  //     _isConnecting = false;
  //     devLog('Strace', '$stackTrace');
  //     devLog('連接失敗', '$e');

  //     // if (isAutoConnect && !_isIntentionalDisconnect) {
  //     //   devLog('自動重連', '連線過程發生錯誤，3秒後重試...');
  //     //   await Future.delayed(const Duration(seconds: 3));
  //     //   if (!_isIntentionalDisconnect && mounted) {
  //     //     _connectToDevice(_lastConnectedDevice!, isAutoConnect: true);
  //     //   }
  //     // }
  //   }
  // }

  Future<void> _connectToDevice(
    BluetoothDevice device, {
    bool isAutoConnect = false,
  }) async {
    if (_isConnecting) {
      devLog('連線模式', '⚠️ 已有連線進行中，忽略此次請求');
      return;
    }

    _isIntentionalDisconnect = false;
    _isConnecting = true;

    try {
      // 1. 建立連線
      if (isAutoConnect) {
        devLog('連線模式', '🔄 啟動自動重連...');
        await device.connect(autoConnect: true);
        await device.connectionState
            .where((state) => state == BluetoothConnectionState.connected)
            .first
            .timeout(const Duration(seconds: 30));
      } else {
        devLog('連線模式', '🚀 啟動手動連線...');
        await device.connect(
          autoConnect: false,
          timeout: const Duration(seconds: 15),
        );
      }

      devLog('連線模式', '✅ 連線成功！');

      // ═══════════════════════════════════════════════════════════════════
      // 關鍵修改 A：連線參數協商 (解決 LINK_SUPERVISION_TIMEOUT)
      // ═══════════════════════════════════════════════════════════════════
      // if (Platform.isAndroid) {
      //   // 1. 請求高優先級 (降低延遲，減少超時機率)
      //   devLog('連線模式', '⚡ 請求高優先級連線...');
      //   try {
      //     await device.requestConnectionPriority(
      //       connectionPriorityRequest: ConnectionPriority.high,
      //     );
      //   } catch (e) {
      //     devLog('連線模式', '⚠️ 請求優先級失敗 (可忽略): $e');
      //   }

      //   await Future.delayed(const Duration(milliseconds: 500)); // 等待生效

      //   // 2. 請求較大的 MTU (解決 133 錯誤，提高吞吐量)
      //   devLog('連線模式', '📦 請求 MTU 512...');
      //   try {
      //     await device.requestMtu(512);
      //   } catch (e) {
      //     devLog('連線模式', '⚠️ 請求 MTU 失敗 (可忽略): $e');
      //   }

      //   await Future.delayed(const Duration(milliseconds: 500)); // 等待生效
      // }

      // ═══════════════════════════════════════════════════════════════════
      // 關鍵修改 B：增加緩衝時間 (解決 GATT 133)
      // ═══════════════════════════════════════════════════════════════════

      // 3. 探索服務
      devLog('連線模式', '🔍 探索服務...');
      final discoveredServices = await device.discoverServices();
      devLog('連線模式', '✅ 發現 ${discoveredServices.length} 個服務');

      // 4. 更新 UI (先不初始化 SDK)
      if (mounted) {
        setState(() {
          _connectedDevice = device;
          _services = discoveredServices;
          // ❌ 暫時移除這裡的 SDK 初始化，移到訂閱成功後
          // _healthCalculator = HealthCalculateDeviceID(3);
        });
      }

      // 5. 訂閱前的大緩衝 (Android 需要休息)
      // devLog('連線模式', '⏳ 等待 1.5 秒讓 GATT 穩定...');
      // await Future.delayed(const Duration(milliseconds: 1500));

      // 6. 訂閱特徵
      await _tryDiscoverAndSubscribe(device); // 這裡面會呼叫 _autoSubscribeFFF4

      // 7. ✅ 訂閱成功後才初始化 SDK (避免 SDK 在連線不穩時搶資源)
      // devLog('連線模式', '🛠️ 初始化 SDK...');
      // if (mounted) {
      //   setState(() {
      //     _healthCalculator = HealthCalculateDeviceID(3);
      //   });
      // }

      // 7. ✅ 改用 _getCalculator（會自動建立或取得現有的）
      // devLog('連線模式', '🛠️ 取得 SDK 計算器...');
      // _getCalculator(device.remoteId.str); // 確保計算器存在

      // 8. 完成連線
      _finishConnection(device);
      devLog('連線模式', '🎉 連線流程全部完成！');
    } catch (e, stackTrace) {
      devLog('連接失敗', '$stackTrace');
      devLog('連接失敗', '❌ $e');
      _isConnecting = false;

      // 失敗時確保斷線
      try {
        await device.disconnect();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _connectedDevice = null;
          _services = [];
          // _healthCalculator = null;
        });

        if (!isAutoConnect) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('連接失敗: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<bool> _tryDiscoverAndSubscribe(BluetoothDevice device) async {
    const maxRetries = 3;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        devLog('連線模式', '🔍 探索服務（嘗試 $attempt/$maxRetries）...');

        // 確認還在連線狀態
        final state = await device.connectionState.first;
        if (state != BluetoothConnectionState.connected) {
          devLog('連線模式', '❌ 連線已斷開，放棄本次嘗試');
          return false; // ✅ 立即返回，不再重試
        }

        // 探索服務
        final discoveredServices = await device.discoverServices();
        devLog('連線模式', '✅ 發現 ${discoveredServices.length} 個服務');

        // ✅ 增加等待時間：1000, 1500, 2000 ms
        // final stabilizeWait = 1000 + (attempt * 500);
        // devLog('連線模式', '⏳ 等待 ${stabilizeWait}ms 讓 GATT 穩定...');
        // await Future.delayed(Duration(milliseconds: stabilizeWait));

        // 再次確認連線狀態
        final stateAfterWait = await device.connectionState.first;
        if (stateAfterWait != BluetoothConnectionState.connected) {
          devLog('連線模式', '❌ 等待期間連線已斷開，放棄本次嘗試');
          return false; // ✅ 立即返回
        }

        // 更新 UI
        if (mounted) {
          setState(() {
            _connectedDevice = device;
            _services = discoveredServices;
          });
        }

        // 訂閱 FFF4
        final subscribeSuccess = await _subscribeToFFF4WithRetry(
          device,
          discoveredServices,
        );

        if (subscribeSuccess) {
          devLog('連線模式', '✅ FFF4 訂閱成功');
          return true;
        } else {
          throw Exception('FFF4 訂閱失敗');
        }
      } catch (e, stackTrace) {
        devLog('連線模式', '⚠️ 嘗試 $attempt 失敗: $e');
        devLog('連線模式', '堆疊追蹤: $stackTrace');

        // ✅ 檢查是否已斷線
        final currentState = await device.connectionState.first;
        if (currentState != BluetoothConnectionState.connected) {
          devLog('連線模式', '❌ 連線已斷開，放棄所有重試');
          return false; // 不再重試，直接返回讓上層處理重連
        }

        if (attempt < maxRetries) {
          final waitTime = 1000 + (attempt * 500); // 1500, 2000, 2500 ms
          devLog('連線模式', '⏳ 等待 ${waitTime}ms 後重試...');
          await Future.delayed(Duration(milliseconds: waitTime));
        }
      }
    }

    return false;
  }

  Future<bool> _subscribeToFFF4WithRetry(
    BluetoothDevice device,
    List<BluetoothService> services,
  ) async {
    const maxSubscribeRetries = 3;

    for (int subAttempt = 1; subAttempt <= maxSubscribeRetries; subAttempt++) {
      try {
        devLog('訂閱流程', '📡 訂閱 FFF4（嘗試 $subAttempt/$maxSubscribeRetries）...');

        // ✅ 每次嘗試前都確認連線狀態
        final state = await device.connectionState.first;
        if (state != BluetoothConnectionState.connected) {
          devLog('訂閱流程', '❌ 連線已斷開，放棄訂閱');
          return false; // 直接返回，讓上層處理重連
        }

        await _autoSubscribeFFF4(device, services);

        final hasFFF4Subscription = _notifySubscriptions.keys.any(
          (uuid) => uuid.toString().toLowerCase().contains('fff4'),
        );

        if (hasFFF4Subscription) {
          devLog('訂閱流程', '✅ FFF4 訂閱確認成功！');
          return true;
        } else {
          throw Exception('訂閱狀態未變更');
        }
      } catch (e, stackTrace) {
        devLog('訂閱流程', '⚠️ 訂閱嘗試 $subAttempt 失敗: $e');
        devLog('訂閱流程', '堆疊追蹤: $stackTrace');

        // ✅ 檢查是否已斷線
        final currentState = await device.connectionState.first;
        if (currentState != BluetoothConnectionState.connected) {
          devLog('訂閱流程', '❌ 連線已斷開，放棄所有訂閱重試');
          return false;
        }

        final isGattError =
            e.toString().contains('133') || e.toString().contains('GATT_ERROR');

        if (subAttempt < maxSubscribeRetries) {
          // ✅ 增加等待時間
          final waitTime = isGattError ? 2500 : 1500;
          devLog('訂閱流程', '⏳ 等待 ${waitTime}ms 後重試訂閱...');
          await Future.delayed(Duration(milliseconds: waitTime));

          // 再次確認連線
          final stateAfterWait = await device.connectionState.first;
          if (stateAfterWait != BluetoothConnectionState.connected) {
            devLog('訂閱流程', '❌ 等待期間連線已斷開，放棄');
            return false;
          }

          if (isGattError) {
            devLog('訂閱流程', '🔄 重新探索服務...');
            try {
              final newServices = await device.discoverServices();
              services = newServices;

              if (mounted) {
                setState(() {
                  _services = newServices;
                });
              }

              await Future.delayed(const Duration(milliseconds: 800));
            } catch (e) {
              devLog('訂閱流程', '⚠️ 重新探索服務失敗: $e');
            }
          }
        }
      }
    }

    return false;
  }

  /// 自動訂閱 fff4 特徵值
  /// 自動訂閱 fff4 特徵值
  Future<void> _autoSubscribeFFF4(
    BluetoothDevice device,
    List<BluetoothService> services,
  ) async {
    devLog('訂閱流程', '🔍 開始搜尋 fff4 特徵...');
    BluetoothCharacteristic? fff4Char;

    // 1. 遍歷服務尋找 fff4
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

    // 2. 如果沒找到，拋出錯誤
    if (fff4Char == null) {
      devLog('[訂閱流程]', '⚠️ 沒有找到 fff4 特徵');
      throw Exception('找不到 FFF4 特徵');
    }

    // ✅ 3. 訂閱前等待一下（關鍵！）
    devLog('[訂閱流程]', '⏳ 訂閱前等待 300ms...');
    await Future.delayed(const Duration(milliseconds: 300));

    // 4. 呼叫 _toggleNotify 進行訂閱
    devLog('[訂閱流程]', '📡 開始訂閱 fff4...');

    if (mounted) {
      await _toggleNotify(fff4Char);
    }

    // 5. 驗證訂閱狀態
    final isSubscribed = _notifySubscriptions.containsKey(fff4Char.uuid);

    if (isSubscribed) {
      devLog('[訂閱流程]', '✅ fff4 自動訂閱成功！');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 自動訂閱 FFF4 成功，開始接收數據'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      throw Exception('訂閱狀態未變更');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ✅ 完成連線（建立監聽器）
  // ═══════════════════════════════════════════════════════════════════════════

  void _finishConnection(BluetoothDevice device) {
    _reconnectAttempts = 0;
    _isConnecting = false;

    // 取消舊的監聽器
    _connectionStateSubscription?.cancel();

    // 建立新的斷線監聽器
    _connectionStateSubscription = device.connectionState.listen((state) {
      devLog('監聽器', '📡 連線狀態變化: $state');

      if (state == BluetoothConnectionState.disconnected) {
        devLog('監聽器', '❌ 裝置斷開');

        _lastConnectedDevice = device;

        // 清理 UI 狀態
        if (mounted) {
          setState(() {
            _connectedDevice = null;
            _services = [];
            _readValues.clear();
            _notifyValues.clear();
          });

          // 清理訂閱
          for (var sub in _notifySubscriptions.values) {
            sub.cancel();
          }
          _notifySubscriptions.clear();
        }

        // 自動重連
        if (!_isIntentionalDisconnect) {
          _handleUnexpectedDisconnect(device);
        } else {
          devLog('監聽器', '✋ 使用者手動斷線，不執行重連');
        }
      }
    });
  }

  // void _disconnectFromDevice({bool updateState = true}) {
  //   // ✅ 標記為故意斷線，這樣監聽器就不會觸發自動重連
  //   _isIntentionalDisconnect = true;

  //   // 首先取消狀態監聽，避免觸發不必要的重連或清理邏輯
  //   _connectionStateSubscription?.cancel();
  //   _connectionStateSubscription = null;

  //   // 執行斷開連接的操作（guard 例外）
  //   try {
  //     _connectedDevice?.disconnect();
  //   } catch (e) {
  //     devLog('斷開設備錯誤', '$e');
  //   }

  //   // ✅ 修改這裡：在清除前，先記住它是誰
  //   if (_connectedDevice != null) {
  //     _lastConnectedDevice = _connectedDevice;
  //   }

  //   // 清理 UI 狀態或直接更新內部狀態（當從 dispose 呼叫時，不做 setState）
  //   if (updateState && mounted) {
  //     setState(() {
  //       _connectedDevice = null;
  //       _healthCalculator = null; // <-- 新增這一行
  //     });
  //   } else {
  //     // 在非 UI 更新路徑下仍要清理變數，避免記憶體/狀態遺留
  //     _connectedDevice = null;
  //     _healthCalculator = null;
  //   }

  //   devLog('斷開設備', '已手動斷開連接');
  // }

  Future<void> _disconnectFromDevice({bool updateState = true}) async {
    devLog('斷線', '========== 開始斷線流程 ==========');
    devLog('斷線', '_connectedDevice: $_connectedDevice');
    devLog(
      '斷線',
      '_connectionStateSubscription 是否為 null: ${_connectionStateSubscription == null}',
    );
    devLog('斷線', '_notifySubscriptions 數量: ${_notifySubscriptions.length}');

    if (_isDisconnecting) {
      devLog('斷線', '⚠️ 已有斷線進行中，忽略');
      return;
    }

    _isDisconnecting = true;

    devLog('斷線', '🔌 開始手動斷線...');
    _isIntentionalDisconnect = true;

    // final deviceId = _connectedDevice?.remoteId.str;

    // 1. 取消監聽
    await _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;

    // 2. 取消訂閱
    // for (var sub in _notifySubscriptions.values) {
    //   await sub.cancel();
    // }
    _notifySubscriptions.clear();

    // 3. 記住裝置
    if (_connectedDevice != null) {
      _lastConnectedDevice = _connectedDevice;
    }

    // 4. 斷線
    try {
      await _connectedDevice?.disconnect();
      devLog('斷線', '✅ 已斷開');
    } catch (e) {
      devLog('斷線', '⚠️ 斷線錯誤: $e');
    }

    // 5. ❌ 不 dispose SDK，只從 Map 移除
    // if (deviceId != null) {
    //   final calc = _calculators.remove(deviceId); // 只移除，不呼叫 dispose
    //   // calc?.dispose(deviceId);
    //   devLog('斷線', '🗑️ 已從 Map 移除 SDK');
    // }

    // 6. 更新 UI
    if (updateState && mounted) {
      setState(() {
        _connectedDevice = null;
        _services = [];
        _readValues.clear();
        _notifyValues.clear();
      });
    }

    // 在最後加入
    devLog('斷線', '========== 斷線流程結束 ==========');
    devLog('斷線', '_connectedDevice: $_connectedDevice');
    devLog(
      '斷線',
      '_connectionStateSubscription 是否為 null: ${_connectionStateSubscription == null}',
    );

    devLog('斷線', '🎉 斷線流程完成');

    _isDisconnecting = false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔄 處理意外斷線（更保守的等待時間）
  // ═══════════════════════════════════════════════════════════════════════════

  void _handleUnexpectedDisconnect(BluetoothDevice device) {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      devLog('自動重連', '❌ 已達最大重連次數 ($_maxReconnectAttempts)，停止重連');
      _reconnectAttempts = 0;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ 重連失敗多次，請手動重新連線'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      }
      return;
    }

    _reconnectAttempts++;

    // ✅ 關鍵改動：更長的等待時間，讓裝置完全重置
    // 第一次：3秒，第二次：5秒，第三次：8秒
    final waitSeconds = 3 + (_reconnectAttempts * 2) + (_reconnectAttempts - 1);

    devLog(
      '自動重連',
      '🔄 $waitSeconds秒後重連（嘗試 $_reconnectAttempts/$_maxReconnectAttempts）...',
    );
    devLog('自動重連', '💡 等待較長時間讓裝置完全重置...');

    Future.delayed(Duration(seconds: waitSeconds), () {
      if (!_isIntentionalDisconnect && mounted && !_isConnecting) {
        _connectToDevice(device, isAutoConnect: true);
      }
    });
  }

  // 檢查藍牙是否可用且已開啟
  Future<bool> _checkBluetoothEnabled() async {
    try {
      final available = await FlutterBluePlus.isSupported;
      if (!available) return false;
      // 取得目前狀態（使用 stream 的第一個值，兼容不同版本）
      final state = await FlutterBluePlus.adapterState.first;
      return state == BluetoothAdapterState.on;
    } catch (e) {
      devLog('檢查藍牙錯誤', '$e');
      return false;
    }
  }

  void _toggleScan(BuildContext context) async {
    // 在最開頭加入
    devLog('掃描', '========== 開始掃描流程 ==========');
    devLog(
      '掃描',
      '_scanResultsSubscription 是否為 null: ${_scanResultsSubscription == null}',
    );
    devLog('掃描', '_connectedDevice: $_connectedDevice');
    devLog('掃描', '_lastConnectedDevice: $_lastConnectedDevice');

    bool permissionsGranted = await _requestPermissions();
    if (!permissionsGranted) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          const SnackBar(
            content: Text('需要藍牙和位置權限才能掃描'),
          ),
        );
      }
      return;
    }

    final btOn = await _checkBluetoothEnabled();
    if (!btOn) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('請開啟藍牙'),
            content: const Text('藍牙未開啟或不可用，請先到系統設定啟用藍牙後再掃描。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('關閉'),
              ),
            ],
          ),
        );
      }
      return;
    }

    // ✅ 等待斷線完成
    while (_isDisconnecting) {
      devLog('掃描', '⏳ 等待斷線完成...');
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // ✅ 如果還有連線，先斷開
    if (_connectedDevice != null) {
      devLog('掃描', '⚠️ 發現還有連線，先斷開...');
      await _disconnectFromDevice();
      devLog('掃描', '✅ 斷線完成，等待 2 秒...');
      await Future.delayed(const Duration(seconds: 2)); // 給裝置時間恢復
    }

    // ✅ 關鍵修改：掃描前的清理
    // 如果有上次連線的裝置，先檢查它是否還被系統認為是連線狀態
    if (_lastConnectedDevice != null) {
      // 檢查系統連線狀態
      var state = await _lastConnectedDevice!.connectionState.first;
      devLog('掃描', '目標裝置: ${_lastConnectedDevice!.remoteId}');
      devLog('掃描', '檢查幽靈連線狀態: $state');
      if (state == BluetoothConnectionState.connected) {
        devLog('掃描', '⚠️ 發現幽靈連線，強制斷開...');
        try {
          await _lastConnectedDevice!.disconnect();
          await Future.delayed(const Duration(seconds: 1)); // 等待斷線生效
        } catch (e) {
          devLog('掃描', '⚠️ 強制斷開失敗: $e');
        }
      }
    }

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        List<ScanResult> dialogScanResults = [];
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            if (_scanResultsSubscription == null) {
              dialogScanResults = [];
              _scanResultsSubscription = FlutterBluePlus.scanResults.listen((
                results,
              ) {
                // ✅ 新增：印出所有掃描到的裝置（包括被過濾的）
                devLog(
                  '掃描原始結果',
                  '========== 共掃到 ${results.length} 個裝置 ==========',
                );
                for (var r in results) {
                  final hasName = r.device.platformName.isNotEmpty;
                  final status = hasName ? '✅ 顯示' : '❌ 過濾（無名稱）';
                  devLog(
                    '掃描裝置',
                    '$status | 名稱: "${r.device.platformName}" | MAC: ${r.device.remoteId} | RSSI: ${r.rssi} dBm',
                  );
                }
                devLog(
                  '掃描原始結果',
                  '================================================',
                );

                dialogSetState(() {
                  dialogScanResults = results
                      .where((r) => r.device.platformName.isNotEmpty)
                      .toList();
                });
              });
              // FlutterBluePlus.cancelWhenScanComplete(_scanResultsSubscription!);
              FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
            }
            return AlertDialog(
              title: const Text('正在掃描藍牙裝置...'),
              content: SizedBox(
                width: double.maxFinite,
                child: dialogScanResults.isEmpty
                    ? const Center(/* ... Loading UI ... */)
                    : ListView.builder(
                        itemCount: dialogScanResults.length,
                        itemBuilder: (context, index) {
                          final result = dialogScanResults[index];
                          return ListTile(
                            title: Text(result.device.platformName),
                            subtitle: Text(result.device.remoteId.toString()),
                            trailing: Text('${result.rssi} dBm'),
                            onTap: () async {
                              await FlutterBluePlus.stopScan();
                              try {
                                // 使用手動連線模式，這樣連不上會拋出例外，UI 才能顯示 SnackBar
                                await _connectToDevice(
                                  result.device,
                                  isAutoConnect: false,
                                );
                                if (Navigator.of(context).canPop()) {
                                  Navigator.of(context).pop();
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('連接失敗: $e')),
                                  );
                                }
                              }
                            },
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  child: const Text('關閉'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      FlutterBluePlus.stopScan();
      _scanResultsSubscription?.cancel();
      _scanResultsSubscription = null;
    });
  }

  // --- 以下是新增的互動方法 ---

  // 讀取特徵值
  Future<void> _readCharacteristic(BluetoothCharacteristic c) async {
    try {
      List<int> value = await c.read();
      setState(() {
        _readValues[c.uuid] = value;
      });
      devLog('讀取特徵', 'UUID: ${c.uuid}, 值: $value');
    } catch (e) {
      devLog('讀取特徵錯誤', '$e');
    }
  }

  // 寫入特徵值
  Future<void> _writeCharacteristic(BluetoothCharacteristic c) async {
    // 這裡我們寫入一個簡單的UTF8字串作為範例
    // 實際應用中，您需要根據裝置的規格來建構 byte array
    try {
      await c.write(utf8.encode('Hello Flutter'), withoutResponse: true);
      devLog('寫入特徵', 'UUID: ${c.uuid}, 已寫入');
    } catch (e, stackTrace) {
      devLog('寫入特徵錯誤', '$e\n$stackTrace');
    }
  }

  Future<void> _toggleNotify(BluetoothCharacteristic c) async {
    // 如果已經在監聽，則取消
    if (_notifySubscriptions.containsKey(c.uuid)) {
      await _notifySubscriptions[c.uuid]!.cancel();
      await c.setNotifyValue(false);
      setState(() {
        _notifySubscriptions.remove(c.uuid);
      });
      devLog('取消通知', 'UUID: ${c.uuid}');
    } else {
      const maxSetNotifyRetries = 3;

      for (int retry = 1; retry <= maxSetNotifyRetries; retry++) {
        try {
          // ✅ 每次重試前檢查連線狀態
          final state = await c.device.connectionState.first;
          if (state != BluetoothConnectionState.connected) {
            devLog('啟用通知', '❌ 連線已斷開，無法訂閱');
            throw Exception('連線已斷開');
          }

          devLog('啟用通知', '嘗試 $retry/$maxSetNotifyRetries - UUID: ${c.uuid}');

          await c.setNotifyValue(true);

          // ✅ 成功！建立監聯器
          final sub = c.lastValueStream.listen((value) async {
            // ... 你現有的資料處理邏輯（保持不變）...

            // ✅ 改用 _getCalculator 取得計算器
            final calculator = _calculators[c.remoteId.str];

            // if (calculator != null) {
            //   devLog('收到的原始數據(未轉)', value.toString());
            //   await calculator.splitPackage(
            //     Uint8List.fromList(value),
            //     c.remoteId.str,
            //   );
            // }

            // ... 其他處理邏輯 ...

            // final newHR = calculator?.getHRValue() ?? 0;
            // final newBR = calculator?.getBRValue() ?? 0;
            // final newGYRO_X = calculator?.getGyroValueX() ?? 0;
            // final newGYRO_Y = calculator?.getGyroValueY() ?? 0;
            // final newGYRO_Z = calculator?.getGyroValueZ() ?? 0;
            // final newTEMP = calculator?.getTempValue() ?? 0;
            // final newHUM = calculator?.getHumValue() ?? 0;
            // final newSPO2 = calculator?.getSpO2Value() ?? 0;
            // final newSTEP = calculator?.getStepValue() ?? 0;
            // final newPOWER = calculator?.getPowerValue() ?? 0;
            // final newTIME = calculator?.getTimeStamp() ?? 0;
            // final new_hrFiltered = calculator?.getHRFiltered() ?? 0;
            // final new_brFiltered = calculator?.getBRFiltered() ?? 0;
            // final new_isWearing = calculator?.getIsWearing() ?? 0;
            // final new_RawData = calculator?.getRawData() ?? 0;
            // final new_type = calculator?.getType() ?? 0;
            // final _rawFFTOut = calculator?.getFFTOut();
            // final new_petPose = calculator?.getPetPoseValue();
            // final splitResult = calculator?.getLastSplitResult() ?? [];

            // if (mounted) {
            //   setState(() {
            //     HR = newHR;
            //     BR = newBR;
            //     GYRO_X = newGYRO_X;
            //     GYRO_Y = newGYRO_Y;
            //     GYRO_Z = newGYRO_Z;
            //     TEMP = newTEMP;
            //     HUM = newHUM;
            //     SPO2 = newSPO2;
            //     STEP = newSTEP;
            //     POWER = newPOWER;
            //     TIME = newTIME;
            //     hrFiltered = new_hrFiltered;
            //     brFiltered = new_brFiltered;
            //     isWearing = new_isWearing;
            //     RawData = new_RawData;
            //     type = new_type;
            //     FFTOut = _rawFFTOut;
            //     petPose = new_petPose;
            //   });
            // }

            // ref
            //     .read(healthDataProvider.notifier)
            //     .normalUpdate(
            //       hr: newHR,
            //       br: newBR,
            //       gyroX: newGYRO_X,
            //       gyroY: newGYRO_Y,
            //       gyroZ: newGYRO_Z,
            //       temp: (newTEMP is num) ? newTEMP.toDouble() : 0,
            //       hum: (newHUM is num) ? newHUM.toDouble() : 0,
            //       spO2: newSPO2,
            //       step: newSTEP,
            //       power: newPOWER,
            //       time: newTIME,
            //       hrFiltered: (new_hrFiltered is List)
            //           ? new_hrFiltered
            //                 .map((e) => (e as num).toDouble())
            //                 .toList()
            //           : const [],
            //       brFiltered: (new_brFiltered is List)
            //           ? new_brFiltered
            //                 .map((e) => (e as num).toDouble())
            //                 .toList()
            //           : const [],
            //       isWearing: new_isWearing == 1 || new_isWearing == true,
            //       rawData: (new_RawData is List)
            //           ? new_RawData.map((e) => (e as num).toInt()).toList()
            //           : const [],
            //       type: new_type,
            //       fftOut: _rawFFTOut is List
            //           ? _rawFFTOut?.map((e) => (e as num).toDouble()).toList()
            //           : null,
            //       petPose: new_petPose,
            //       splitRawData: splitResult,
            //     );

            // DateTime realTimeOrigin = DateTime.fromMillisecondsSinceEpoch(
            //   newTIME,
            // );
            // devLog('當前標準時間', realTimeOrigin.toString());
            // devLog('時間戳', newTIME.toString());

            // devLog('splitRawData', splitResult.toString());

            if (mounted) {
              setState(() {
                _notifyValues[c.uuid] = value;
              });
            }
          });

          setState(() {
            _notifySubscriptions[c.uuid] = sub;
          });

          devLog('啟用通知', '✅ 成功 - UUID: ${c.uuid}');

          // 發送時間同步指令
          if (c.uuid.toString().toUpperCase().contains('FFF4')) {
            try {
              final writeCharacteristic = _services
                  .expand((s) => s.characteristics)
                  .firstWhere(
                    (ch) => ch.uuid.toString().toUpperCase().contains('FFF5'),
                  );

              if (writeCharacteristic.properties.write) {
                await writeCharacteristic.write(
                  getTimeSyncCommand(),
                  withoutResponse: false,
                );
                devLog('時間同步', '成功發送時間指令到 FFF5');
              }
            } catch (e) {
              devLog('時間同步錯誤', '找不到 FFF5 特徵或寫入失敗: $e');
              // ✅ 時間同步失敗不應該阻止訂閱成功
              // 不要 rethrow
            }
          }

          return; // 成功，退出
        } catch (e, stackTrace) {
          devLog('啟用通知錯誤', '嘗試 $retry 失敗: $e');
          devLog('啟用通知錯誤', '堆疊追蹤: $stackTrace');

          // ✅ 如果是斷線錯誤，不再重試
          if (e.toString().contains('not connected') ||
              e.toString().contains('disconnected') ||
              e.toString().contains('連線已斷開')) {
            devLog('啟用通知', '❌ 連線已斷開，停止重試');
            rethrow;
          }

          if (retry < maxSetNotifyRetries) {
            // ✅ 增加等待時間
            final waitTime = 800 * retry; // 800, 1600, 2400 ms
            devLog('啟用通知', '⏳ 等待 ${waitTime}ms 後重試...');
            await Future.delayed(Duration(milliseconds: waitTime));
          } else {
            devLog('啟用通知錯誤', '❌ 已達最大重試次數');
            rethrow;
          }
        }
      }
    }
  }

  // // 開關特徵通知
  // // --- 修改後 ---
  // Future<void> _toggleNotify(BluetoothCharacteristic c) async {
  //   // 如果已經在監聽，則取消
  //   if (_notifySubscriptions.containsKey(c.uuid)) {
  //     await _notifySubscriptions[c.uuid]!.cancel();
  //     await c.setNotifyValue(false);
  //     setState(() {
  //       // 我們只移除訂閱的紀錄，這樣圖示狀態才會更新
  //       _notifySubscriptions.remove(c.uuid);
  //       // 我們不再移除 _notifyValues 中的資料，讓最後的數值保留在畫面上
  //       // _notifyValues.remove(c.uuid); // <--- 將此行移除或註解
  //     });
  //     devLog('取消通知', 'UUID: ${c.uuid}');
  //   } else {
  //     // 否則，開始監聽
  //     try {
  //       await c.setNotifyValue(true);
  //       final sub = c.lastValueStream.listen((value) async {
  //         // <--- 將此處改為 async
  //         // --- 在這裡加入我們的演算法邏輯 ---

  //         // 1. 將收到的原始 byte array (value) 餵給演算法
  //         //    現在這個方法是 Future，所以我們需要 await
  //         if (_healthCalculator != null) {
  //           // devLog(
  //           //   'Uint8List.fromList(value)長度',
  //           //   Uint8List.fromList(value).length.toString(),
  //           // );

  //           devLog('收到的原始數據(未轉)', value.toString());
  //           // devLog('收到的原始數據(Uint8List)', Uint8List.fromList(value).toString());

  //           await _healthCalculator!.splitPackage(
  //             Uint8List.fromList(value),
  //             c.remoteId.str,
  //           );
  //         }

  //         // 2. 從演算法中獲取最新的計算結果
  //         final newHR = _healthCalculator?.getHRValue() ?? 0;
  //         final newBR = _healthCalculator?.getBRValue() ?? 0;

  //         final newGYRO_X = _healthCalculator?.getGyroValueX() ?? 0;
  //         final newGYRO_Y = _healthCalculator?.getGyroValueY() ?? 0;
  //         final newGYRO_Z = _healthCalculator?.getGyroValueZ() ?? 0;

  //         final newTEMP = _healthCalculator?.getTempValue() ?? 0;
  //         final newHUM = _healthCalculator?.getHumValue() ?? 0;
  //         final newSPO2 = _healthCalculator?.getSpO2Value() ?? 0;
  //         final newSTEP = _healthCalculator?.getStepValue() ?? 0;
  //         final newPOWER = _healthCalculator?.getPowerValue() ?? 0;
  //         final newTIME = _healthCalculator?.getTimeStamp() ?? 0;

  //         final new_hrFiltered = _healthCalculator?.getHRFiltered() ?? 0;
  //         final new_brFiltered = _healthCalculator?.getBRFiltered() ?? 0;

  //         final new_isWearing = _healthCalculator?.getIsWearing() ?? 0;
  //         final new_RawData = _healthCalculator?.getRawData() ?? 0;
  //         final new_type = _healthCalculator?.getType() ?? 0;

  //         // Ensure FFT output is converted to List<double>? to match the provider's expected type
  //         final _rawFFTOut = _healthCalculator?.getFFTOut();

  //         final new_petPose = _healthCalculator?.getPetPoseValue();

  //         // 3. 更新 UI 狀態
  //         if (mounted) {
  //           setState(() {
  //             HR = newHR;
  //             BR = newBR;
  //             GYRO_X = newGYRO_X;
  //             GYRO_Y = newGYRO_Y;
  //             GYRO_Z = newGYRO_Z;
  //             TEMP = newTEMP; // 溫度
  //             HUM = newHUM; // 濕度
  //             SPO2 = newSPO2; // RRI數據
  //             STEP = newSTEP; // 步數數據
  //             POWER = newPOWER; // 電量數據
  //             TIME = newTIME; // 時間戳
  //             hrFiltered = new_hrFiltered; // 心率波動團表數據
  //             brFiltered = new_brFiltered; // 呼吸波動團表數據
  //             isWearing = new_isWearing; //
  //             RawData = new_RawData; //
  //             type = new_type; //
  //             FFTOut = _rawFFTOut; //
  //             petPose = new_petPose; // 寵物姿勢
  //           });
  //         }

  //         ref
  //             .read(healthDataProvider.notifier)
  //             .normalUpdate(
  //               hr: newHR,
  //               br: newBR,
  //               gyroX: newGYRO_X,
  //               gyroY: newGYRO_Y,
  //               gyroZ: newGYRO_Z,
  //               temp: (newTEMP is num) ? newTEMP.toDouble() : 0,
  //               hum: (newHUM is num) ? newHUM.toDouble() : 0,
  //               spO2: newSPO2,
  //               step: newSTEP,
  //               power: newPOWER,
  //               time: newTIME,
  //               hrFiltered: (new_hrFiltered is List)
  //                   ? new_hrFiltered.map((e) => (e as num).toDouble()).toList()
  //                   : const [],
  //               brFiltered: (new_brFiltered is List)
  //                   ? new_brFiltered.map((e) => (e as num).toDouble()).toList()
  //                   : const [],
  //               isWearing: new_isWearing == 1 || new_isWearing == true,
  //               rawData: (new_RawData is List)
  //                   ? new_RawData.map((e) => (e as num).toInt()).toList()
  //                   : const [],
  //               type: new_type,
  //               fftOut: _rawFFTOut is List
  //                   ? _rawFFTOut?.map((e) => (e as num).toDouble()).toList()
  //                   : null,
  //               petPose: new_petPose,
  //             );

  //         // 4. (可選) 在日誌中印出，方便觀察
  //         // devLog('演算法輸出', 'HR: $newHR, BR: $newBR');
  //         // devLog(
  //         //   '陀螺儀輸出',
  //         //   'GYRO_X: $newGYRO_X, GYRO_Y: $newGYRO_Y, GYRO_Z: $newGYRO_Z',
  //         // );
  //         // devLog('寵物姿勢', new_petPose.toString());

  //         DateTime realTimeOrigin = DateTime.fromMillisecondsSinceEpoch(
  //           newTIME,
  //         );

  //         devLog(
  //           '當前標準時間',
  //           realTimeOrigin.toString(),
  //         );

  //         devLog('時間戳', newTIME.toString());

  //         //devLog('原始數據', new_RawData.toString());

  //         // --- 演算法邏輯結束 ---

  //         setState(() {
  //           _notifyValues[c.uuid] = value;
  //         });
  //         // devLog('收到通知', 'UUID: ${c.uuid}, 值: $value');
  //       });
  //       setState(() {
  //         _notifySubscriptions[c.uuid] = sub;
  //       });
  //       devLog('啟用通知', 'UUID: ${c.uuid}');

  //       // --- 新增：發送時間同步指令 ---
  //       // 只有在訂閱 FFF4 時才觸發時間同步
  //       if (c.uuid.toString().toUpperCase().contains('FFF4')) {
  //         try {
  //           // 找到 FFF0 服務中的 FFF5 特徵
  //           final writeCharacteristic = _services
  //               .expand((s) => s.characteristics)
  //               .firstWhere(
  //                 (ch) => ch.uuid.toString().toUpperCase().contains('FFF5'),
  //               );

  //           // 檢查特徵是否可寫
  //           if (writeCharacteristic.properties.write) {
  //             await writeCharacteristic.write(
  //               getTimeSyncCommand(),
  //               withoutResponse: false, // 文件沒說，但時間同步通常需要回應以確保成功
  //             );
  //             devLog('時間同步', '成功發送時間指令到 FFF5');
  //           }
  //         } catch (e) {
  //           devLog('時間同步錯誤', '找不到 FFF5 特徵或寫入失敗: $e');
  //         }
  //       }
  //       // --- 時間同步指令結束 ---
  //     } catch (e, stackTrace) {
  //       devLog('啟用通知錯誤', '$e\n$stackTrace');
  //     }
  //   }
  // }

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

  // --- 以下是新增的 UI Builder 方法 ---

  // 建立顯示單個特徵的 Tile
  Widget _buildCharacteristicTile(BluetoothCharacteristic c) {
    String valueText = '';
    // 優先顯示通知的值，其次是讀取的值
    List<int>? value = _notifyValues[c.uuid] ?? _readValues[c.uuid];
    if (value != null) {
      // 將 byte array 轉換為可讀字串 (十六進制 和 UTF8)
      valueText =
          '[${value.join(', ')}]\n${utf8.decode(value, allowMalformed: true)}';
    }

    return ListTile(
      title: Text('特徵: ${c.uuid}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(valueText),
          // 顯示特徵的屬性
          Wrap(
            spacing: 8.0,
            children: [
              if (c.properties.read) Chip(label: Text('Read')),
              if (c.properties.write) Chip(label: Text('Write')),
              if (c.properties.notify) Chip(label: Text('Notify')),
              if (c.properties.indicate) Chip(label: Text('Indicate')),
            ],
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (c.properties.read)
            IconButton(
              icon: Icon(Icons.file_download),
              onPressed: () => _readCharacteristic(c),
            ),
          if (c.properties.write)
            IconButton(
              icon: Icon(Icons.file_upload),
              onPressed: () => _writeCharacteristic(c),
            ),
          if (c.properties.notify || c.properties.indicate)
            IconButton(
              icon: Icon(
                _notifySubscriptions.containsKey(c.uuid)
                    ? Icons.notifications_off
                    : Icons.notifications_active,
                color: _notifySubscriptions.containsKey(c.uuid)
                    ? Colors.blue
                    : Colors.grey,
              ),
              onPressed: () => _toggleNotify(c),
            ),
        ],
      ),
    );
  }

  // 建立顯示單個服務的 Tile
  Widget _buildServiceTile(BluetoothService service) {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(
        title: Text('服務: ${service.uuid}'),
        children: service.characteristics
            .map(_buildCharacteristicTile)
            .toList(),
      ),
    );
  }

  // 建立顯示已連線裝置資訊和服務列表的畫面
  // --- 修改後 ---
  Widget _buildConnectedDeviceView(WidgetRef ref) {
    // 直接返回 Column，它將成為 body 的主體
    final health = ref.watch(healthDataProvider); // 讀取目前狀態
    return SingleChildScrollView(
      child: Column(
        children: [
          SizedBox(height: 16), // 增加一點頂部間距
          const Text('心率'),
          Text(
            '${health.hr}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          const Text('呼吸'),
          Text(
            '${health.br}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 20),
          const Text('陀螺儀'),
          Text(
            'X: ${health.gyroX}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          Text(
            'Y: ${health.gyroY}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          Text(
            'Z: ${health.gyroZ}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),

          const Text('溫度'),
          Text(
            '${health.temp}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          const Text('濕度'),
          Text(
            '${health.hum}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          const Text('RRI'),
          Text(
            '${health.spO2}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          const Text('步數'),
          Text(
            '${health.step}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          const Text('電量'),
          Text(
            '${health.power}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          const Text('時間戳'),
          Text(
            '${health.time}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          const Text('心率波動團表'),
          // Text(
          //   '${health.hrFiltered}',
          //   style: Theme.of(context).textTheme.headlineMedium,
          // ),
          Text(
            'isNotEmpty: ${health.hrFiltered.isNotEmpty}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          const Text('呼吸波動團表'),
          // Text(
          //   '${health.brFiltered}',
          //   style: Theme.of(context).textTheme.headlineMedium,
          // ),
          Text(
            'isNotEmpty: ${health.brFiltered.isNotEmpty}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          const Text('穿戴狀態'),
          Text(
            '${health.isWearing}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          const Text('原始數據'),
          // Text(
          //   '${health.rawData}',
          //   style: Theme.of(context).textTheme.headlineMedium,
          // ),
          Text(
            'isNotEmpty: ${health.rawData.isNotEmpty}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          const Text('類型'),
          Text(
            '${health.type}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          const Text('FFT輸出'),
          // Text(
          //   '${health.fftOut}',
          //   style: Theme.of(context).textTheme.headlineMedium,
          // ),
          Text(
            'isNotEmpty: ${health.fftOut.isNotEmpty}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          const Text('寵物姿勢'),
          Text(
            '${health.petPose}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),

          Text(
            '已連接到: ${_connectedDevice!.platformName}',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          ElevatedButton(
            onPressed: () {
              _disconnectFromDevice(updateState: true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[400]),
            child: const Text('斷開藍芽裝置'),
          ),
          SizedBox(height: 8),
          // 這個 Expanded 是正確的，因為它在 Column 內部，會佔用剩餘的空間來顯示列表
          _services.isEmpty
              ? Center(child: Text('未發現服務'))
              : Container(
                  height: 400,
                  child: ListView.builder(
                    itemCount: _services.length,
                    itemBuilder: (context, index) =>
                        _buildServiceTile(_services[index]),
                  ),
                ),
        ],
      ),
    );
  }

  // 建立尚未連線時的畫面
  // Widget _buildDisconnectedView() {
  //   return Column(
  //     mainAxisAlignment: MainAxisAlignment.center,
  //     children: [
  //       ElevatedButton(
  //         onPressed: () => _toggleScan(context),
  //         child: const Text('掃描並連接藍牙裝置'),
  //       ),
  //     ],
  //   );
  // }

  // 建立尚未連線時的畫面
  Widget _buildDisconnectedView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: () => _toggleScan(context),
          child: const Text('掃描並連接藍牙裝置'),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _requestPermissions().then((granted) {
      if (granted) {
        devLog('藍芽權限', 'Bluetooth permissions granted');
      } else {
        devLog('藍芽權限', 'Bluetooth permissions denied');
      }
    });
  }

  @override
  void dispose() {
    devLog('頁面生命週期', '❗❗❗ NormalDataPage dispose() 被呼叫了！！！');
    // 1) 標記為故意斷線
    _isIntentionalDisconnect = true;

    // 2) 清理連線但不要呼叫 setState
    _disconnectFromDevice(updateState: false);

    // 3) 取消所有通知訂閱
    for (var sub in _notifySubscriptions.values) {
      sub.cancel();
    }
    _notifySubscriptions.clear();

    // 4) 取消掃描訂閱
    _scanResultsSubscription?.cancel();
    _scanResultsSubscription = null;

    // 5) ✅ 清理所有 SDK 計算器
    // for (var entry in _calculators.entries) {
    //   entry.value.dispose(entry.key);
    // }
    // _calculators.clear();

    // 6) 呼叫 super.dispose
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('藍牙服務瀏覽器')),
      body: SafeArea(
        child: Center(
          // 根據是否已連接裝置，顯示不同的畫面
          child: _connectedDevice == null
              ? _buildDisconnectedView()
              : _buildConnectedDeviceView(ref),
        ),
      ),
    );
  }
}
