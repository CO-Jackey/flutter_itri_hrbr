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
  HealthCalculateDeviceID? _healthCalculator;

  BluetoothDevice? _lastConnectedDevice; // ✅ 新增：用來記住剛斷線的裝置

  // ✅ 新增：用來標記是否為「手動」斷線
  bool _isIntentionalDisconnect = false;

  // ✅ 新增：標記是否正在連線過程中
  bool _isConnecting = false;

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

  // 修改方法簽名，加入 isAutoConnect 參數，預設為 false (手動連線)
  Future<void> _connectToDevice(
    BluetoothDevice device, {
    bool isAutoConnect = false,
  }) async {
    // 0. 防止重複監聽，先取消舊的
    await _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null; // ✅ 新增：確保清空

    _isIntentionalDisconnect = false;
    _isConnecting = true;

    // ❌ 移除這裡的監聽器建立
    // _connectionStateSubscription = device.connectionState.listen(...);

    try {
      // 2. 根據模式選擇連線方式
      if (isAutoConnect) {
        devLog('連線模式', '啟動自動連線 (等待裝置出現...)');
        await device.connect(autoConnect: true, mtu: null);

        devLog('連線模式', '正在等待連線建立...');
        await device.connectionState
            .where((val) {
              devLog('連線狀況', '$val');
              return val == BluetoothConnectionState.connected;
            })
            .first;
        devLog('連線模式', '裝置已成功連線！');
      } else {
        devLog('連線模式', '啟動手動連線 (超時設定 15秒)');
        await device.connect(
          autoConnect: true,
          // timeout: const Duration(seconds: 15),
          mtu: null,
        );
      }

      // 3. 連接成功後，探索服務
      devLog('連線模式', '開始探索服務...');
      List<BluetoothService> discoveredServices = await device.discoverServices();
      devLog('連線模式', '服務探索完成');

      // 4. 更新 UI
      if (mounted) {
        setState(() {
          _connectedDevice = device;
          _services = discoveredServices;
          _healthCalculator = HealthCalculateDeviceID(3);
        });

        await _autoSubscribeFFF4(device, discoveredServices);
      }

      // ✅ 所有流程完成後，才建立斷線監聽器
      _isConnecting = false;
      devLog('連線模式', '✅ 連線流程完成，開始監聽斷線事件');

      _connectionStateSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          devLog('監聽器', '裝置斷開');

          _lastConnectedDevice = device;

          if (mounted) {
            setState(() {
              _connectedDevice = null;
              _services = [];
              _readValues.clear();
              _notifyValues.clear();
              for (var sub in _notifySubscriptions.values) {
                sub.cancel();
              }
              _notifySubscriptions.clear();
            });
          }

          if (!_isIntentionalDisconnect) {
            devLog('自動重連', '偵測到意外斷線，3秒後啟動背景重連...');
            Future.delayed(const Duration(seconds: 3), () {
              if (!_isIntentionalDisconnect && mounted) {
                _connectToDevice(_lastConnectedDevice!, isAutoConnect: true);
              }
            });
          } else {
            devLog('監聯器', '使用者手動斷線，不執行重連。');
          }
        }
      });

    } catch (e, stackTrace) {
      _isConnecting = false;
      devLog('Strace', '$stackTrace');
      devLog('連接失敗', '$e');

      // if (isAutoConnect && !_isIntentionalDisconnect) {
      //   devLog('自動重連', '連線過程發生錯誤，3秒後重試...');
      //   await Future.delayed(const Duration(seconds: 3));
      //   if (!_isIntentionalDisconnect && mounted) {
      //     _connectToDevice(_lastConnectedDevice!, isAutoConnect: true);
      //   }
      // }
    }
  }

  // ...existing code...

  /// 自動訂閱 fff4 特徵值
  Future<void> _autoSubscribeFFF4(
    BluetoothDevice device,
    List<BluetoothService> services,
  ) async {
    try {
      devLog('[訂閱流程]', '🔍 開始搜尋 fff4 特徵...');
      BluetoothCharacteristic? fff4Char;

      // 1. 遍歷服務尋找 fff4
      for (final service in services) {
        for (final char in service.characteristics) {
          final uuidStr = char.uuid.toString().toLowerCase();

          // 檢查 UUID 是否包含 fff4 且具備 Notify 或 Indicate 屬性
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
        // 列出所有特徵幫助 debug (可選)
        // for (final service in services) {
        //   for (final char in service.characteristics) {
        //     devLog('[訂閱流程]', '  - ${char.uuid}');
        //   }
        // }
        return;
      }

      // 3. 呼叫現有的 _toggleNotify 方法進行訂閱
      devLog('[訂閱流程]', '📡 開始訂閱 fff4...');

      // 確保在 UI 執行緒操作 (雖然 _toggleNotify 內部有 setState，但保險起見)
      if (mounted) {
        await _toggleNotify(fff4Char);
      }

      // 4. 驗證訂閱狀態 (檢查本地 Map 是否有紀錄)
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
    } catch (e) {
      devLog('[訂閱流程]', '❌ 自動訂閱失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 自動訂閱失敗: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ...existing code...

  void _disconnectFromDevice({bool updateState = true}) {
    // ✅ 標記為故意斷線，這樣監聽器就不會觸發自動重連
    _isIntentionalDisconnect = true;

    // 首先取消狀態監聽，避免觸發不必要的重連或清理邏輯
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;

    // 執行斷開連接的操作（guard 例外）
    try {
      _connectedDevice?.disconnect();
    } catch (e) {
      devLog('斷開設備錯誤', '$e');
    }

    // ✅ 修改這裡：在清除前，先記住它是誰
    if (_connectedDevice != null) {
      _lastConnectedDevice = _connectedDevice;
    }

    // 清理 UI 狀態或直接更新內部狀態（當從 dispose 呼叫時，不做 setState）
    if (updateState && mounted) {
      setState(() {
        _connectedDevice = null;
        _healthCalculator = null; // <-- 新增這一行
      });
    } else {
      // 在非 UI 更新路徑下仍要清理變數，避免記憶體/狀態遺留
      _connectedDevice = null;
      _healthCalculator = null;
    }

    devLog('斷開設備', '已手動斷開連接');
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
    // ... 您的掃描 Dialog 程式碼 ...
    // (此處省略以保持簡潔)
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
                dialogSetState(() {
                  dialogScanResults = results
                      .where((r) => r.device.platformName.isNotEmpty)
                      .toList();
                });
              });
              FlutterBluePlus.cancelWhenScanComplete(_scanResultsSubscription!);
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
    } catch (e) {
      devLog('寫入特徵錯誤', '$e');
    }
  }

  // 開關特徵通知
  // --- 修改後 ---
  Future<void> _toggleNotify(BluetoothCharacteristic c) async {
    // 如果已經在監聽，則取消
    if (_notifySubscriptions.containsKey(c.uuid)) {
      await _notifySubscriptions[c.uuid]!.cancel();
      await c.setNotifyValue(false);
      setState(() {
        // 我們只移除訂閱的紀錄，這樣圖示狀態才會更新
        _notifySubscriptions.remove(c.uuid);
        // 我們不再移除 _notifyValues 中的資料，讓最後的數值保留在畫面上
        // _notifyValues.remove(c.uuid); // <--- 將此行移除或註解
      });
      devLog('取消通知', 'UUID: ${c.uuid}');
    } else {
      // 否則，開始監聽
      try {
        await c.setNotifyValue(true);
        final sub = c.lastValueStream.listen((value) async {
          // <--- 將此處改為 async
          // --- 在這裡加入我們的演算法邏輯 ---

          // 1. 將收到的原始 byte array (value) 餵給演算法
          //    現在這個方法是 Future，所以我們需要 await
          if (_healthCalculator != null) {
            // devLog(
            //   'Uint8List.fromList(value)長度',
            //   Uint8List.fromList(value).length.toString(),
            // );

            devLog('收到的原始數據(未轉)', value.toString());
            // devLog('收到的原始數據(Uint8List)', Uint8List.fromList(value).toString());

            await _healthCalculator!.splitPackage(
              Uint8List.fromList(value),
              c.remoteId.str,
            );
          }

          // 2. 從演算法中獲取最新的計算結果
          final newHR = _healthCalculator?.getHRValue() ?? 0;
          final newBR = _healthCalculator?.getBRValue() ?? 0;

          final newGYRO_X = _healthCalculator?.getGyroValueX() ?? 0;
          final newGYRO_Y = _healthCalculator?.getGyroValueY() ?? 0;
          final newGYRO_Z = _healthCalculator?.getGyroValueZ() ?? 0;

          final newTEMP = _healthCalculator?.getTempValue() ?? 0;
          final newHUM = _healthCalculator?.getHumValue() ?? 0;
          final newSPO2 = _healthCalculator?.getSpO2Value() ?? 0;
          final newSTEP = _healthCalculator?.getStepValue() ?? 0;
          final newPOWER = _healthCalculator?.getPowerValue() ?? 0;
          final newTIME = _healthCalculator?.getTimeStamp() ?? 0;

          final new_hrFiltered = _healthCalculator?.getHRFiltered() ?? 0;
          final new_brFiltered = _healthCalculator?.getBRFiltered() ?? 0;

          final new_isWearing = _healthCalculator?.getIsWearing() ?? 0;
          final new_RawData = _healthCalculator?.getRawData() ?? 0;
          final new_type = _healthCalculator?.getType() ?? 0;

          // Ensure FFT output is converted to List<double>? to match the provider's expected type
          final _rawFFTOut = _healthCalculator?.getFFTOut();

          final new_petPose = _healthCalculator?.getPetPoseValue();

          // 3. 更新 UI 狀態
          if (mounted) {
            setState(() {
              HR = newHR;
              BR = newBR;
              GYRO_X = newGYRO_X;
              GYRO_Y = newGYRO_Y;
              GYRO_Z = newGYRO_Z;
              TEMP = newTEMP; // 溫度
              HUM = newHUM; // 濕度
              SPO2 = newSPO2; // RRI數據
              STEP = newSTEP; // 步數數據
              POWER = newPOWER; // 電量數據
              TIME = newTIME; // 時間戳
              hrFiltered = new_hrFiltered; // 心率波動團表數據
              brFiltered = new_brFiltered; // 呼吸波動團表數據
              isWearing = new_isWearing; //
              RawData = new_RawData; //
              type = new_type; //
              FFTOut = _rawFFTOut; //
              petPose = new_petPose; // 寵物姿勢
            });
          }

          ref
              .read(healthDataProvider.notifier)
              .normalUpdate(
                hr: newHR,
                br: newBR,
                gyroX: newGYRO_X,
                gyroY: newGYRO_Y,
                gyroZ: newGYRO_Z,
                temp: (newTEMP is num) ? newTEMP.toDouble() : 0,
                hum: (newHUM is num) ? newHUM.toDouble() : 0,
                spO2: newSPO2,
                step: newSTEP,
                power: newPOWER,
                time: newTIME,
                hrFiltered: (new_hrFiltered is List)
                    ? new_hrFiltered.map((e) => (e as num).toDouble()).toList()
                    : const [],
                brFiltered: (new_brFiltered is List)
                    ? new_brFiltered.map((e) => (e as num).toDouble()).toList()
                    : const [],
                isWearing: new_isWearing == 1 || new_isWearing == true,
                rawData: (new_RawData is List)
                    ? new_RawData.map((e) => (e as num).toInt()).toList()
                    : const [],
                type: new_type,
                fftOut: _rawFFTOut is List
                    ? _rawFFTOut?.map((e) => (e as num).toDouble()).toList()
                    : null,
                petPose: new_petPose,
              );

          // 4. (可選) 在日誌中印出，方便觀察
          // devLog('演算法輸出', 'HR: $newHR, BR: $newBR');
          // devLog(
          //   '陀螺儀輸出',
          //   'GYRO_X: $newGYRO_X, GYRO_Y: $newGYRO_Y, GYRO_Z: $newGYRO_Z',
          // );
          // devLog('寵物姿勢', new_petPose.toString());

          DateTime realTimeOrigin = DateTime.fromMillisecondsSinceEpoch(
            newTIME,
          );

          devLog(
            '當前標準時間',
            realTimeOrigin.toString(),
          );

          devLog('時間戳', newTIME.toString());

          //devLog('原始數據', new_RawData.toString());

          // --- 演算法邏輯結束 ---

          setState(() {
            _notifyValues[c.uuid] = value;
          });
          // devLog('收到通知', 'UUID: ${c.uuid}, 值: $value');
        });
        setState(() {
          _notifySubscriptions[c.uuid] = sub;
        });
        devLog('啟用通知', 'UUID: ${c.uuid}');

        // --- 新增：發送時間同步指令 ---
        // 只有在訂閱 FFF4 時才觸發時間同步
        if (c.uuid.toString().toUpperCase().contains('FFF4')) {
          try {
            // 找到 FFF0 服務中的 FFF5 特徵
            final writeCharacteristic = _services
                .expand((s) => s.characteristics)
                .firstWhere(
                  (ch) => ch.uuid.toString().toUpperCase().contains('FFF5'),
                );

            // 檢查特徵是否可寫
            if (writeCharacteristic.properties.write) {
              await writeCharacteristic.write(
                getTimeSyncCommand(),
                withoutResponse: false, // 文件沒說，但時間同步通常需要回應以確保成功
              );
              devLog('時間同步', '成功發送時間指令到 FFF5');
            }
          } catch (e) {
            devLog('時間同步錯誤', '找不到 FFF5 特徵或寫入失敗: $e');
          }
        }
        // --- 時間同步指令結束 ---
      } catch (e) {
        devLog('啟用通知錯誤', '$e');
      }
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
            onPressed: _disconnectFromDevice,
            child: const Text('斷開藍芽裝置'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[400]),
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

        // ✅ 新增：如果有上一次連線的裝置，顯示重連按鈕
        if (_lastConnectedDevice != null) ...[
          const SizedBox(height: 20),
          const Text('或者'),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text(
                  '上次連線: ${_lastConnectedDevice!.platformName}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新連線'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    // 🔥 呼叫連線方法，這裡看您要用手動還是自動模式
                    // 建議用 false (手動模式) 這樣有 timeout 比較好除錯
                    _connectToDevice(
                      _lastConnectedDevice!,
                      isAutoConnect: true,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
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
    // 1) 清理連線但不要呼叫 setState（避免在 dispose 期間觸發 rebuild 錯誤）
    _disconnectFromDevice(updateState: false);

    // 2) 取消所有通知訂閱與掃描訂閱
    for (var sub in _notifySubscriptions.values) {
      sub.cancel();
    }
    _notifySubscriptions.clear();

    _scanResultsSubscription?.cancel();
    _scanResultsSubscription = null;

    // 3) 呼叫 super.dispose
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
