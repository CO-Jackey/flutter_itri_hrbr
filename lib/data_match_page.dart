import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_itri_hrbr/helper/devLog.dart';
import 'package:flutter_itri_hrbr/model/inter_data.dart';
import 'package:flutter_itri_hrbr/provider/health_provider.dart';
import 'package:flutter_itri_hrbr/services/HealthCalculate.dart';
import 'package:flutter_itri_hrbr/services/data_Classifier_Service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

class DataMatchPage extends ConsumerStatefulWidget {
  const DataMatchPage({super.key});

  @override
  ConsumerState<DataMatchPage> createState() => _DataMatchPageState();
}

class _DataMatchPageState extends ConsumerState<DataMatchPage> {
  // --- 新增這一行，用來緩存上一筆收到的封包 ---
  List<int>? _previousPacket;

  // 新增統計變數
  int _originalPacketCount = 0;
  int _interpolatedPacketCount = 0;
  int _packetsInCurrentSecond = 0;
  int _currentSecond = 0;
  Timer? _statsTimer;
  DateTime? _statsStartTime;

  List<int>? _firstGroupPacket;
  int? _firstGroupTimestamp;
  bool _isWaitingForSecond = false;

  // --- 新增這一行 ---
  HealthCalculate? _healthCalculator;

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

  Future<void> _connectToDevice(BluetoothDevice device) async {
    // 1. 在發起連接前，先設定好狀態監聽
    //    這個監聽主要負責處理「意外斷線」的情況
    _connectionStateSubscription = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        devLog('監聽器', '裝置意外斷開，清理狀態...');
        // 如果裝置斷開，重置所有相關狀態
        if (mounted) {
          setState(() {
            _connectedDevice = null;
            _services = [];
            _readValues.clear();
            _notifyValues.clear();
            // 取消所有舊的通知訂閱
            for (var sub in _notifySubscriptions.values) {
              sub.cancel();
            }
            _notifySubscriptions.clear();
          });
        }
      }
    });

    try {
      // 2. 發起連接，並設定超時
      await device.connect(timeout: Duration(seconds: 15));

      // 3. 連接成功後，立刻探索服務
      List<BluetoothService> discoveredServices = await device
          .discoverServices();

      // 4. 所有操作都成功後，才一次性更新UI狀態
      if (mounted) {
        setState(() {
          _connectedDevice = device;
          _services = discoveredServices;

          //-------------------------

          // --- 新增這兩行：初始化演算法 ---
          // 假設我們要測試的是狗 (type: 3)
          _healthCalculator = HealthCalculate(3);

          //----------------------------
        });
        devLog(
          '連接流程',
          '成功連接到 ${device.platformName} 並發現 ${_services.length} 個服務',
        );
      }
    } catch (e) {
      devLog('連接失敗', '$e');
      // 連接失敗或超時，清理資源
      _disconnectFromDevice();
    }
  }

  void _disconnectFromDevice({bool updateState = true}) {
    // 首先取消狀態監聽，避免觸發不必要的重連或清理邏輯
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;

    // 執行斷開連接的操作（guard 例外）
    try {
      _connectedDevice?.disconnect();
    } catch (e) {
      devLog('斷開設備錯誤', '$e');
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
                                await _connectToDevice(result.device);
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

        // *** 核心修改點 ***
        // 將 listen 回呼中的邏輯替換為呼叫 _processAndUpsample
        final sub = c.lastValueStream.listen((value) async {
          devLog('原始數據', value.toString());

          // 現在 listen 回呼只做一件事：將收到的數據交給我們的升採樣處理器
          await _processAndUpsample(value);

          // 更新 UI 上顯示的原始值 (這部分可以保留)
          if (mounted) {
            setState(() {
              _notifyValues[c.uuid] = value;
            });
          }
        });
        // *** 修改結束 ***

        // final sub = c.lastValueStream.listen((value) async {
        //   // <--- 將此處改為 async
        //   // --- 在這裡加入我們的演算法邏輯 ---

        //   // 1. 將收到的原始 byte array (value) 餵給演算法
        //   //    現在這個方法是 Future，所以我們需要 await
        //   if (_healthCalculator != null) {
        //     // devLog(
        //     //   'Uint8List.fromList(value)長度',
        //     //   Uint8List.fromList(value).length.toString(),
        //     // );

        //     // ref
        //     //     .read(filteredFirstRawDataProvider.notifier)
        //     //     .filterData(value, ref);

        //     //ref.read(dataClassifierProvider).classify(Uint8List.fromList(value));

        //     // final dataValue = ref.read(filteredFirstRawDataProvider);

        //     //devLog('收到的原始數據(未轉)', value.toString());
        //     devLog('收到的原始數據(Uint8List)', Uint8List.fromList(value).toString());

        //     // 只讀取（不要用 watch，避免在 listener 中觸發 rebuild 錯誤）
        //     // final logEntries = ref.read(filteredRawLogProvider);

        //     // // 1) 若只想看最新一筆篩選後 rawData
        //     // if (logEntries.isNotEmpty) {
        //     //   devLog(
        //     //     'FilteredRawData(last)',
        //     //     logEntries.last.rawData.toString(),
        //     //   );
        //     // }

        //     // 第一次處理
        //     await _processSinglePacket(value);

        //     // 第二次處理 (使用完全相同的數據)
        //     await _processSinglePacket(value);

        //     // await _healthCalculator!.splitPackage(Uint8List.fromList(value));
        //     // await _healthCalculator!.splitPackage(
        //     //   Uint8List.fromList(dataValue.splitRawData),
        //     // );
        //   }

        //   // 4. (可選) 在日誌中印出，方便觀察
        //   // devLog('演算法輸出', 'HR: $newHR, BR: $newBR');
        //   // devLog(
        //   //   '陀螺儀輸出',
        //   //   'GYRO_X: $newGYRO_X, GYRO_Y: $newGYRO_Y, GYRO_Z: $newGYRO_Z',
        //   // );
        //   // devLog('寵物姿勢', new_petPose.toString());

        //   //devLog('原始數據', new_RawData.toString());

        //   // --- 演算法邏輯結束 ---

        //   setState(() {
        //     _notifyValues[c.uuid] = value;
        //   });
        //   //devLog('收到通知', 'UUID: ${c.uuid}, 值: $value');
        // });

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

  /// 輔助方法：將封包中的 5-byte 時間戳轉換為一個 Dart 的 int 類型
  // int _bytesToTimestamp(List<int> packet) {
  //   // 根據文件，時間戳在 index 1 到 5
  //   if (packet.length < 6) return 0;

  //   // 使用位元運算 (bitwise operations) 根據 Little Endian 順序組合整數
  //   // Dart 的 int 是 64-bit，足以容納 40-bit 的時間戳
  //   return packet[1] |
  //       (packet[2] << 8) |
  //       (packet[3] << 16) |
  //       (packet[4] << 24) |
  //       (packet[5] << 32);
  // }

  // 輔助：把 timestamp 轉成 5 字節 little-endian 陣列（對應 packet[1..5]）
  List<int> _tsTo5Bytes(int ts) => [
    ts & 0xFF,
    (ts >> 8) & 0xFF,
    (ts >> 16) & 0xFF,
    (ts >> 24) & 0xFF,
    (ts >> 32) & 0xFF,
  ];

  // 輔助：將 bytes 轉 Hex 字串
  String _bytesToHex(List<int> b) =>
      b.map((e) => e.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

  /// 輔助方法：將一個 int 類型的時間戳寫回到一個封包(List<int>)中
  void _updateTimestampInPacket(List<int> packet, int timestamp) {
    if (packet.length < 6) return;

    // 根據 Little Endian 順序，使用位元遮罩和位移將整數拆解回 5 個 bytes
    packet[1] = timestamp & 0xFF;
    packet[2] = (timestamp >> 8) & 0xFF;
    packet[3] = (timestamp >> 16) & 0xFF;
    packet[4] = (timestamp >> 24) & 0xFF;
    packet[5] = (timestamp >> 32) & 0xFF;
  }
  // /// 輔助方法：處理單一數據封包的完整流程
  // Future<void> _processSinglePacket(List<int> packetData) async {
  //   // --- 這裡是您原本 listen 回呼中的所有演算法邏輯 ---

  //   // 1. 將收到的原始 byte array (packetData) 餵給演算法
  //   if (_healthCalculator != null) {
  //     // 呼叫 filterData 進行分類並更新 Provider
  //     final dataType = ref
  //         .read(filteredFirstRawDataProvider.notifier)
  //         .filterData(packetData, ref);

  //     if (dataType == DataType.first) {
  //       // 讀取分類後的結果
  //       final dataValue = ref.read(filteredFirstRawDataProvider);

  //       devLog('處理中的數據 (Uint8List)', Uint8List.fromList(packetData).toString());

  //       // 將數據餵給 HealthCalculate SDK
  //       // 注意：這裡我們使用分類後 Provider 中的數據
  //       await _healthCalculator!.splitPackage(
  //         Uint8List.fromList(dataValue.splitRawData),
  //       );
  //       // 2. 從演算法中獲取最新的計算結果
  //       final newHR = _healthCalculator?.getHRValue() ?? 0;
  //       final newBR = _healthCalculator?.getBRValue() ?? 0;

  //       final newGYRO_X = _healthCalculator?.getGyroValueX() ?? 0;
  //       final newGYRO_Y = _healthCalculator?.getGyroValueY() ?? 0;
  //       final newGYRO_Z = _healthCalculator?.getGyroValueZ() ?? 0;

  //       final newTEMP = _healthCalculator?.getTempValue() ?? 0;
  //       final newHUM = _healthCalculator?.getHumValue() ?? 0;
  //       final newSPO2 = _healthCalculator?.getSpO2Value() ?? 0;
  //       final newSTEP = _healthCalculator?.getStepValue() ?? 0;
  //       final newPOWER = _healthCalculator?.getPowerValue() ?? 0;
  //       final newTIME = _healthCalculator?.getTimeStamp() ?? 0;

  //       final new_hrFiltered = _healthCalculator?.getHRFiltered() ?? 0;
  //       final new_brFiltered = _healthCalculator?.getBRFiltered() ?? 0;

  //       final new_isWearing = _healthCalculator?.getIsWearing() ?? 0;
  //       final new_RawData = _healthCalculator?.getRawData() ?? 0;
  //       final new_type = _healthCalculator?.getType() ?? 0;

  //       // Ensure FFT output is converted to List<double>? to match the provider's expected type
  //       final _rawFFTOut = _healthCalculator?.getFFTOut();

  //       final new_petPose = _healthCalculator?.getPetPoseValue();

  //       // 3. 更新 UI 狀態
  //       if (mounted) {
  //         setState(() {
  //           HR = newHR;
  //           BR = newBR;
  //           GYRO_X = newGYRO_X;
  //           GYRO_Y = newGYRO_Y;
  //           GYRO_Z = newGYRO_Z;
  //           TEMP = newTEMP; // 溫度
  //           HUM = newHUM; // 濕度
  //           SPO2 = newSPO2; // RRI數據
  //           STEP = newSTEP; // 步數數據
  //           POWER = newPOWER; // 電量數據
  //           TIME = newTIME; // 時間戳
  //           hrFiltered = new_hrFiltered; // 心率波動團表數據
  //           brFiltered = new_brFiltered; // 呼吸波動團表數據
  //           isWearing = new_isWearing; //
  //           RawData = new_RawData; //
  //           type = new_type; //
  //           FFTOut = _rawFFTOut; //
  //           petPose = new_petPose; // 寵物姿勢
  //         });
  //       }

  //       // 4. 更新 healthDataProvider
  //       ref
  //           .read(healthDataProvider.notifier)
  //           .normalUpdate(
  //             hr: newHR,
  //             br: newBR,
  //             gyroX: newGYRO_X,
  //             gyroY: newGYRO_Y,
  //             gyroZ: newGYRO_Z,
  //             temp: (newTEMP is num) ? newTEMP.toDouble() : 0,
  //             hum: (newHUM is num) ? newHUM.toDouble() : 0,
  //             spO2: newSPO2,
  //             step: newSTEP,
  //             power: newPOWER,
  //             time: newTIME,
  //             hrFiltered: (new_hrFiltered is List)
  //                 ? new_hrFiltered.map((e) => (e as num).toDouble()).toList()
  //                 : const [],
  //             brFiltered: (new_brFiltered is List)
  //                 ? new_brFiltered.map((e) => (e as num).toDouble()).toList()
  //                 : const [],
  //             isWearing: new_isWearing == 1 || new_isWearing == true,
  //             rawData: (new_RawData is List)
  //                 ? new_RawData.map((e) => (e as num).toInt()).toList()
  //                 : const [],
  //             type: new_type,
  //             fftOut: _rawFFTOut is List
  //                 ? _rawFFTOut?.map((e) => (e as num).toDouble()).toList()
  //                 : null,
  //             petPose: new_petPose,
  //           );
  //     }
  //   }
  // }

  /// 更智能的內插方法

  /// 改進的插值方法 - 實現更精確的時間戳分配
  /// 改進的處理方法 - 解決時間戳問題的數據倍增
  Future<void> _processAndUpsample(List<int> currentPacket) async {
    // 使用系統時間生成連續的時間戳，避免設備時間戳跳躍問題
    final baseTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 10;

    // 直接處理當前封包
    await _processSinglePacketWithTimestamp(currentPacket, baseTimestamp);
  }

  // /// 帶時間戳處理的單一封包處理方法
  // Future<void> _processSinglePacketWithTimestamp(
  //   List<int> packetData,
  //   int baseTimestamp,
  // ) async {
  //   if (_healthCalculator == null) return;

  //   // 進行分類
  //   final dataType = ref
  //       .read(filteredFirstRawDataProvider.notifier)
  //       .filterData(packetData, ref);

  //   if (dataType == DataType.first) {
  //     // 這是第一組數據，需要處理兩次實現倍增
  //     final dataValue = ref.read(filteredFirstRawDataProvider);

  //     // 準備兩個不同時間戳的封包
  //     final originalPacket = List<int>.from(dataValue.splitRawData);
  //     final duplicatedPacket = List<int>.from(dataValue.splitRawData);

  //     // 設定不同的時間戳
  //     final originalTimestamp = baseTimestamp;
  //     final duplicatedTimestamp = baseTimestamp + 2; // 加2個單位避免太接近

  //     // 更新封包中的時間戳
  //     _updateTimestampInPacket(originalPacket, originalTimestamp);
  //     _updateTimestampInPacket(duplicatedPacket, duplicatedTimestamp);

  //     // 第一次處理（原始時間戳）
  //     await _processFirstGroupDataWithTimestamp(
  //       originalPacket,
  //       originalTimestamp,
  //       "原始",
  //     );
  //     devLog('第一組數據倍增', '原始: $originalPacket');
  //     // 第二次處理（插值時間戳）
  //     await _processFirstGroupDataWithTimestamp(
  //       duplicatedPacket,
  //       duplicatedTimestamp,
  //       "插值",
  //     );
  //     devLog('第一組數據倍增', '插值: $duplicatedPacket');
  //   } else if (dataType == DataType.second) {
  //     devLog('第二組數據', '已忽略 - 封包: $packetData');
  //     // 第二組數據：什麼都不做
  //   } else {
  //     devLog('雜訊數據', '已忽略 - 封包: $packetData');
  //     // 雜訊：什麼都不做
  //   }
  // }

  // /// 優化版本 - 簡单固定增量插值，改善UI效能
  // Future<void> _processSinglePacketWithTimestamp(
  //   List<int> packetData,
  //   int baseTimestamp,
  // ) async {
  //   if (_healthCalculator == null) return;

  //   // 進行分類
  //   final dataType = ref
  //       .read(filteredFirstRawDataProvider.notifier)
  //       .filterData(packetData, ref);

  //   if (dataType == DataType.first) {
  //     // 這是第一組數據，需要處理兩次實現倍增
  //     final dataValue = ref.read(filteredFirstRawDataProvider);

  //     // 準備兩個不同時間戳的封包
  //     final originalPacket = List<int>.from(dataValue.splitRawData);
  //     final duplicatedPacket = List<int>.from(dataValue.splitRawData);

  //     // 使用簡單的固定增量：+3（基於您數據的觀察）
  //     final originalTimestamp = baseTimestamp;
  //     final duplicatedTimestamp = baseTimestamp + 30000; // 簡單的固定增量

  //     // // 更新封包中的時間戳
  //     _updateTimestampInPacket(originalPacket, originalTimestamp);
  //     devLog('原本時間戳', originalTimestamp.toString());
  //     _updateTimestampInPacket(duplicatedPacket, duplicatedTimestamp);

  //     // 讀回驗證
  //     final checkOriginal = _bytesToTimestamp(originalPacket);
  //     final checkDuplicated = _bytesToTimestamp(duplicatedPacket);

  //     devLog(
  //       '時間戳寫入(original)',
  //       'int=$originalTimestamp bytes=${originalPacket.sublist(1, 6)} readBack=$checkOriginal',
  //     );
  //     devLog(
  //       '時間戳寫入(duplicated)',
  //       'int=$duplicatedTimestamp bytes=${duplicatedPacket.sublist(1, 6)} readBack=$checkDuplicated',
  //     );

  //     // === 連續處理兩次，但只更新一次UI ===

  //     // 第一次處理（原始）
  //     await _healthCalculator!.splitPackage(
  //       Uint8List.fromList(originalPacket),
  //     );
  //     await _healthCalculator!.splitPackage(
  //       Uint8List.fromList(duplicatedPacket),
  //     );

  //     await _processFirstGroupDataWithTimestamp();
  //     _originalPacketCount++;
  //     _packetsInCurrentSecond++;

  //     // // 第二次處理（插值）
  //     // await _healthCalculator!.splitPackage(
  //     //   Uint8List.fromList(duplicatedPacket),
  //     // );
  //     // await _processFirstGroupDataWithTimestamp(duplicatedTimestamp);
  //     // _interpolatedPacketCount++;
  //     // _packetsInCurrentSecond++;

  //     // devLog(
  //     //   '簡單插值',
  //     //   '原始: $originalTimestamp → 插值: $duplicatedTimestamp (+300) }',
  //     // );
  //   } else {
  //     devLog('非第一組數據', '已忽略 - 類型: $dataType');
  //   }
  // }

  /// 修改後的處理方法 - 等待第二筆數據再開始插值
  // Future<void> _processSinglePacketWithTimestamp(
  //   List<int> packetData,
  //   int baseTimestamp,
  // ) async {
  //   if (_healthCalculator == null) return;

  //   // 進行分類
  //   final dataType = ref
  //       .read(filteredFirstRawDataProvider.notifier)
  //       .filterData(packetData, ref);

  //   if (dataType == DataType.first) {
  //     final dataValue = ref.read(filteredFirstRawDataProvider);
  //     final currentPacket = List<int>.from(dataValue.splitRawData);
  //     final currentTimestamp = _bytesToTimestamp(currentPacket);

  //     if (_firstGroupPacket == null) {
  //       // 這是第一筆第一組數據，先儲存起來等待
  //       _firstGroupPacket = currentPacket;
  //       _firstGroupTimestamp = currentTimestamp;
  //       _isWaitingForSecond = true;

  //       devLog('等待策略', '儲存第一筆數據，時間戳: $currentTimestamp');

  //       // 第一筆數據只處理一次，不插值
  //       await _healthCalculator!.splitPackage(
  //         Uint8List.fromList(currentPacket),
  //       );
  //       await _updateUIAndProvider();
  //       _originalPacketCount++;
  //       _packetsInCurrentSecond++;
  //     } else if (_isWaitingForSecond) {
  //       // 這是第二筆第一組數據，現在可以開始插值邏輯
  //       _isWaitingForSecond = false;

  //       // 計算時間差和中位數
  //       final timeDiff = currentTimestamp - _firstGroupTimestamp!;
  //       final midTimestamp = _firstGroupTimestamp! + (timeDiff / 2).round();

  //       devLog(
  //         '插值計算',
  //         '第一筆: ${_firstGroupTimestamp!}, 第二筆: $currentTimestamp, '
  //             '差異: $timeDiff, 中位數: $midTimestamp',
  //       );

  //       // 從這筆開始，每筆第一組數據都要插值處理
  //       await _processWithInterpolation(
  //         _firstGroupPacket!,
  //         _firstGroupTimestamp!,
  //         midTimestamp,
  //       );
  //       await _processWithInterpolation(
  //         currentPacket,
  //         currentTimestamp,
  //         currentTimestamp + (timeDiff / 2).round(),
  //       );
  //     } else {
  //       // 第三筆之後的第一組數據，繼續插值處理
  //       // 使用前一次的時間差來推算插值點
  //       final estimatedDiff = currentTimestamp - _firstGroupTimestamp!;
  //       final interpolatedTimestamp =
  //           _firstGroupTimestamp! + (estimatedDiff / 2).round();

  //       await _processWithInterpolation(
  //         currentPacket,
  //         currentTimestamp,
  //         interpolatedTimestamp,
  //       );

  //       // 更新記錄供下次使用
  //       _firstGroupTimestamp = currentTimestamp;
  //     }
  //   } else {
  //     devLog('非第一組數據', '已忽略 - 類型: $dataType');
  //   }
  // }

  /// 改進的處理方法 - 實現 [1] → [1,1',2] → [2,2',3] 的插值邏輯
  ///
  /// 核心策略：
  /// 1. 第1筆第一組數據：只儲存，送1筆給SDK [1]
  /// 2. 第2筆第一組數據：補送第1筆插值，再送第2筆原始 [1,1',2]
  /// 3. 第3筆之後：每次都送插值+原始 [prev,prev',current]
  ///
  /// Provider陣列顯示模式：
  /// - 時間T1: [1]               → SDK收到: 1
  /// - 時間T2: [1,1',2]          → SDK收到: 1',2 (補送1')
  /// - 時間T3: [1,1',2,2',3]     → SDK收到: 2',3
  /// - 時間T4: [...,3,3',4]      → SDK收到: 3',4
  Future<void> _processSinglePacketWithTimestamp(
    List<int> packetData,
    int baseTimestamp,
  ) async {
    if (_healthCalculator == null) return;

    // ======= 步驟1: 數據分類篩選 =======
    // 使用你現有的智慧篩選器，自動區分第一組/第二組/雜訊
    final dataType = ref
        .read(filteredFirstRawDataProvider.notifier)
        .filterData(packetData, ref);

    // ======= 步驟2: 只處理第一組數據 =======
    if (dataType == DataType.first) {
      // 從Provider取得篩選後的第一組數據
      final dataValue = ref.read(filteredFirstRawDataProvider);
      final currentPacket = List<int>.from(dataValue.splitRawData);
      final currentTimestamp = _bytesToTimestamp(currentPacket);

      if (_firstGroupPacket == null) {
        // ============================================
        // 情境1: 第1筆第一組數據到達
        // Provider陣列: [] → [1]
        // SDK處理: 送出1筆原始數據
        // ============================================

        // 儲存第1筆數據，等待第2筆來決定插值點
        _firstGroupPacket = currentPacket;
        _firstGroupTimestamp = currentTimestamp;
        _isWaitingForSecond = true; // 標記正在等待第2筆

        devLog('插值流程', '[1] 第1筆第一組數據 ts=$currentTimestamp');

        // === SDK處理 ===
        // 第1筆只送原始數據，不做插值
        await _healthCalculator!.splitPackage(
          Uint8List.fromList(currentPacket),
        );

        // === Provider陣列更新 ===
        // 將第1筆原始數據加入陣列
        ref
            .read(interpolatedDataProvider.notifier)
            .addPacket(
              InterpolatedPacket(
                data: currentPacket,
                timestamp: currentTimestamp,
                isInterpolated: false, // 標記為原始數據
              ),
            );

        // 更新UI和健康數據Provider
        await _updateUIAndProvider();
        _originalPacketCount++;
        _packetsInCurrentSecond++;
      } else if (_isWaitingForSecond) {
        // ============================================
        // 情境2: 第2筆第一組數據到達
        // Provider陣列: [1] → [1,1',2]
        // SDK處理: 送出2筆 (第1筆的插值 + 第2筆原始)
        // ============================================

        _isWaitingForSecond = false; // 結束等待狀態

        // 計算時間差和中點（用於插值）
        final timeDiff = currentTimestamp - _firstGroupTimestamp!;
        // 原先的
        //final midpoint = _firstGroupTimestamp! + (timeDiff ~/ 2);
        // 對第三位 +138
        //final midpoint = (_firstGroupTimestamp! + (16777216 / 2)).toInt();

        // 對第三位 + 2
        final midpoint = _firstGroupTimestamp! + (2 << 16);

        devLog('插值計算', '[1,1\',2] 第2筆第一組數據 ts=$currentTimestamp');
        devLog(
          '插值計算',
          '前一筆=$_firstGroupTimestamp, 當前=$currentTimestamp, 中點=$midpoint',
        );

        // === SDK處理部分 ===

        // 1️⃣ 補送第1筆的插值數據 (1')
        // 複製第1筆的內容，但修改時間戳為中點
        final interp1 = List<int>.from(_firstGroupPacket!);
        _updateTimestampInPacket(interp1, midpoint);
        await _healthCalculator!.splitPackage(Uint8List.fromList(interp1));
        devLog('SDK送出', '第1筆插值 ts=$midpoint');

        // Provider陣列：加入第1筆的插值
        ref
            .read(interpolatedDataProvider.notifier)
            .addPacket(
              InterpolatedPacket(
                data: interp1,
                timestamp: midpoint,
                isInterpolated: true, // 標記為插值數據
              ),
            );
        _interpolatedPacketCount++;
        _packetsInCurrentSecond++;

        // 2️⃣ 送第2筆原始數據 (2)
        await _healthCalculator!.splitPackage(
          Uint8List.fromList(currentPacket),
        );
        devLog('SDK送出', '第2筆原始 ts=$currentTimestamp');

        // Provider陣列：加入第2筆原始
        ref
            .read(interpolatedDataProvider.notifier)
            .addPacket(
              InterpolatedPacket(
                data: currentPacket,
                timestamp: currentTimestamp,
                isInterpolated: false, // 標記為原始數據
              ),
            );
        _originalPacketCount++;
        _packetsInCurrentSecond++;

        // 更新UI
        await _updateUIAndProvider();

        // 儲存當前數據作為下一次插值的基準
        _firstGroupPacket = currentPacket;
        _firstGroupTimestamp = currentTimestamp;
      } else {
        // ============================================
        // 情境3: 第3筆及之後的第一組數據
        // Provider陣列: [...,prev] → [...,prev,prev',current]
        // SDK處理: 送出2筆 (前一筆與當前筆的插值 + 當前筆原始)
        // ============================================

        // 計算前一筆與當前筆之間的中點
        final timeDiff = currentTimestamp - _firstGroupTimestamp!;
        // 原先的
        //final midpoint = _firstGroupTimestamp! + (timeDiff ~/ 2);

        // 105
        // final midpoint = (_firstGroupTimestamp! + (16777216 / 2)).toInt();

        // 對第三位 + 2
        // final midpoint = _firstGroupTimestamp! + (2 << 24);

        // 安全常數
        const int index3Increase =
            2 << 16; // 對應把 packet[3] +2 -> 加 2 * 65536 單位

        int midpoint;
        if (timeDiff > 0 && timeDiff < 243000) {
          // 正常：使用真實中點
          midpoint = _firstGroupTimestamp! + (timeDiff ~/ 2);
        } else {
          // 非法或過大：不要用負或巨量 timeDiff 做中點，改用 index(3)+2 的 fallback
          midpoint = _firstGroupTimestamp! + index3Increase;
          devLog(
            '插值警告',
            'timeDiff 非法/異常: $timeDiff；使用 fallback index3+2 => 加 ${index3Increase} (0.1ms 單位)',
          );
        }

        // devLog('插值流程', '[prev,prev\',current] 第N筆第一組數據');
        // devLog(
        //   '插值計算',
        //   '前一筆=$_firstGroupTimestamp, 當前=$currentTimestamp, 中點=$midpoint',
        // );

        final prevBytes = _tsTo5Bytes(_firstGroupTimestamp!);
        final midBytes = _tsTo5Bytes(midpoint);
        final currBytes = _tsTo5Bytes(currentTimestamp);

        devLog('timeDiff', timeDiff.toString());
        devLog(
          '插值計算',
          '前一筆=int=${_firstGroupTimestamp} bytes=${prevBytes} hex=${_bytesToHex(prevBytes)}',
        );
        devLog(
          '插值計算',
          '中點=int=$midpoint bytes=${midBytes} hex=${_bytesToHex(midBytes)}',
        );
        devLog(
          '插值計算',
          '當前=int=$currentTimestamp bytes=${currBytes} hex=${_bytesToHex(currBytes)}',
        );

        // === SDK處理部分 ===

        // 1️⃣ 送插值數據 (prev')
        // 使用前一筆的內容，時間戳設為中點
        final interp = List<int>.from(_firstGroupPacket!);
        _updateTimestampInPacket(interp, midpoint);
        await _healthCalculator!.splitPackage(Uint8List.fromList(interp));
        devLog('SDK送出', '插值 ts=$midpoint');

        // Provider陣列：加入插值
        ref
            .read(interpolatedDataProvider.notifier)
            .addPacket(
              InterpolatedPacket(
                data: interp,
                timestamp: midpoint,
                isInterpolated: true, // 標記為插值數據
              ),
            );
        _interpolatedPacketCount++;
        _packetsInCurrentSecond++;

        // 2️⃣ 送當前筆原始數據 (current)
        await _healthCalculator!.splitPackage(
          Uint8List.fromList(currentPacket),
        );
        devLog('SDK送出', '原始 ts=$currentTimestamp');

        // Provider陣列：加入原始
        ref
            .read(interpolatedDataProvider.notifier)
            .addPacket(
              InterpolatedPacket(
                data: currentPacket,
                timestamp: currentTimestamp,
                isInterpolated: false, // 標記為原始數據
              ),
            );
        _originalPacketCount++;
        _packetsInCurrentSecond++;

        // 更新UI
        await _updateUIAndProvider();

        // 更新緩存供下次使用
        _firstGroupPacket = currentPacket;
        _firstGroupTimestamp = currentTimestamp;
      }
    } else if (dataType == DataType.second) {
      // 第二組數據：完全忽略，不送SDK，不加Provider
      devLog('數據過濾', '第二組數據已自動忽略');
    } else if (dataType == DataType.noise) {
      // 過渡期雜訊：完全忽略
      devLog('數據過濾', '過渡期雜訊已自動忽略');
    }
  }

  // Future<void> _processSinglePacketWithTimestamp(
  //   List<int> packetData,
  //   int baseTimestamp,
  // ) async {
  //   if (_healthCalculator == null) return;

  //   // ======= 步驟1: 數據分類篩選 =======
  //   // 使用你現有的智慧篩選器，自動區分第一組/第二組/雜訊
  //   final dataType = ref
  //       .read(filteredFirstRawDataProvider.notifier)
  //       .filterData(packetData, ref);

  //   // ======= 步驟2: 只處理第一組數據 =======
  //   if (dataType == DataType.first) {
  //     // 從Provider取得篩選後的第一組數據
  //     final dataValue = ref.read(filteredFirstRawDataProvider);
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

  //     // await _healthCalculator!.splitPackage(
  //     //   Uint8List.fromList(currentPacket),
  //     // );
  //     // await _healthCalculator!.splitPackage(
  //     //   Uint8List.fromList(currentPacket),
  //     // );
  //     // //傳四筆 => HR 52

  //     // await _healthCalculator!.splitPackage(
  //     //   Uint8List.fromList(currentPacket),
  //     // );

  //     // await _healthCalculator!.splitPackage(
  //     //   Uint8List.fromList(currentPacket),
  //     // );
  //     // 傳6筆 => HR 105

  //     // await _healthCalculator!.splitPackage(
  //     //   Uint8List.fromList(currentPacket),
  //     // );

  //     // await _healthCalculator!.splitPackage(
  //     //   Uint8List.fromList(currentPacket),
  //     // );
  //     // 傳8筆 => HR 58~67

  //     devLog('SDK送出', '原始數據=$currentPacket');
  //     devLog('SDK送出', '原始 ts=$currentTimestamp');

  //     // Provider陣列：加入原始
  //     ref
  //         .read(interpolatedDataProvider.notifier)
  //         .addPacket(
  //           InterpolatedPacket(
  //             data: currentPacket,
  //             timestamp: currentTimestamp,
  //             isInterpolated: false, // 標記為原始數據
  //           ),
  //         );
  //     _originalPacketCount++;
  //     _packetsInCurrentSecond++;

  //     // 更新UI
  //     await _updateUIAndProvider();

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

  /// 帶插值的處理方法
  // Future<void> _processWithInterpolation(
  //   List<int> originalPacket,
  //   int originalTimestamp,
  //   int interpolatedTimestamp,
  // ) async {
  //   // 處理原始數據
  //   await _healthCalculator!.splitPackage(Uint8List.fromList(originalPacket));
  //   _originalPacketCount++;
  //   _packetsInCurrentSecond++;

  //   // 創建插值數據
  //   final interpolatedPacket = List<int>.from(originalPacket);
  //   _updateTimestampInPacket(interpolatedPacket, interpolatedTimestamp);

  //   // 處理插值數據
  //   await _healthCalculator!.splitPackage(
  //     Uint8List.fromList(interpolatedPacket),
  //   );
  //   _interpolatedPacketCount++;
  //   _packetsInCurrentSecond++;

  //   // 更新UI（使用插值後的結果）
  //   await _updateUIAndProvider();

  //   devLog(
  //     '插值處理',
  //     '原始: $originalTimestamp → 插值: $interpolatedTimestamp → 成功處理',
  //   );
  // }

  /// 統一的UI和Provider更新方法
  Future<void> _updateUIAndProvider() async {
    // 獲取SDK結果
    final results = _extractAllResults();

    // 更新Provider
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

  /// 需要新增這個輔助方法來提取時間戳
  int _bytesToTimestamp(List<int> packet) {
    if (packet.length < 6) return 0;
    return packet[1] |
        (packet[2] << 8) |
        (packet[3] << 16) |
        (packet[4] << 24) |
        (packet[5] << 32);
  }

  /// 輔助方法：提取所有SDK結果
  Map<String, dynamic> _extractAllResults() {
    final timestamp =
        _healthCalculator?.getTimeStamp() ??
        DateTime.now().millisecondsSinceEpoch ~/ 10;

    devLog('hr', _healthCalculator?.getHRValue().toString() ?? '0');
    devLog('br', _healthCalculator?.getBRValue().toString() ?? '0');

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
      'hrFiltered': _healthCalculator?.getHRFiltered() ?? 0,
      'brFiltered': _healthCalculator?.getBRFiltered() ?? 0,
      'isWearing': _healthCalculator?.getIsWearing() ?? 0,
      'rawData': _healthCalculator?.getRawData() ?? 0,
      'type': _healthCalculator?.getType() ?? 0,
      'fftOut': _healthCalculator?.getFFTOut(),
      'petPose': _healthCalculator?.getPetPoseValue(),
    };
  }

  /// 處理第一組數據的核心邏輯（帶時間戳參數）
  // Future<void> _processFirstGroupDataWithTimestamp(
  //   //int timestamp,
  // ) async {
  //   // 獲取計算結果
  //   final newHR = _healthCalculator?.getHRValue() ?? 0;
  //   final newBR = _healthCalculator?.getBRValue() ?? 0;

  //   final newGYRO_X = _healthCalculator?.getGyroValueX() ?? 0;
  //   final newGYRO_Y = _healthCalculator?.getGyroValueY() ?? 0;
  //   final newGYRO_Z = _healthCalculator?.getGyroValueZ() ?? 0;

  //   final newTEMP = _healthCalculator?.getTempValue() ?? 0;
  //   final newHUM = _healthCalculator?.getHumValue() ?? 0;
  //   final newSPO2 = _healthCalculator?.getSpO2Value() ?? 0;
  //   final newSTEP = _healthCalculator?.getStepValue() ?? 0;
  //   final newPOWER = _healthCalculator?.getPowerValue() ?? 0;
  //   final newTIME = _healthCalculator?.getTimeStamp() ?? 0;
  //   final new_hrFiltered = _healthCalculator?.getHRFiltered() ?? 0;
  //   final new_brFiltered = _healthCalculator?.getBRFiltered() ?? 0;

  //   final new_isWearing = _healthCalculator?.getIsWearing() ?? 0;
  //   final new_RawData = _healthCalculator?.getRawData() ?? 0;
  //   final new_type = _healthCalculator?.getType() ?? 0;
  //   final _rawFFTOut = _healthCalculator?.getFFTOut();
  //   final new_petPose = _healthCalculator?.getPetPoseValue();

  //   // 更新 healthDataProvider
  //   ref
  //       .read(healthDataProvider.notifier)
  //       .normalUpdate(
  //         hr: newHR,
  //         br: newBR,
  //         gyroX: newGYRO_X,
  //         gyroY: newGYRO_Y,
  //         gyroZ: newGYRO_Z,
  //         temp: (newTEMP is num) ? newTEMP.toDouble() : 0,
  //         hum: (newHUM is num) ? newHUM.toDouble() : 0,
  //         spO2: newSPO2,
  //         step: newSTEP,
  //         power: newPOWER,
  //         time: newTIME, // timestamp, // 使用我們設定的時間戳
  //         hrFiltered: (new_hrFiltered is List)
  //             ? new_hrFiltered.map((e) => (e as num).toDouble()).toList()
  //             : const [],
  //         brFiltered: (new_brFiltered is List)
  //             ? new_brFiltered.map((e) => (e as num).toDouble()).toList()
  //             : const [],
  //         isWearing: new_isWearing == 1 || new_isWearing == true,
  //         rawData: (new_RawData is List)
  //             ? new_RawData.map((e) => (e as num).toInt()).toList()
  //             : const [],
  //         type: new_type,
  //         fftOut: _rawFFTOut is List
  //             ? _rawFFTOut?.map((e) => (e as num).toDouble()).toList()
  //             : null,
  //         petPose: new_petPose,
  //       );

  //   devLog('HR', newHR.toString());
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

  // ===== 3. UI顯示部分 =====
  Widget _buildInterpolationStats() {
    final interpolatedData = ref.watch(interpolatedDataProvider);
    final filterStatus = ref.read(dataClassifierProvider).getFilterStatus();

    return Card(
      margin: EdgeInsets.all(16),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '插值統計',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Divider(),

            // 篩選器狀態
            Text('篩選器基準值: ${filterStatus['基準值'] ?? "學習中"}'),
            if (filterStatus['候選值'] != null)
              Text(
                '候選值: ${filterStatus['候選值']} (連續${filterStatus['候選連續次數']}次)',
              ),
            SizedBox(height: 8),

            // 插值統計
            Text('原始數據: ${interpolatedData.totalOriginal} 筆'),
            Text('插值數據: ${interpolatedData.totalInterpolated} 筆'),
            Text(
              '總計: ${interpolatedData.totalOriginal + interpolatedData.totalInterpolated} 筆',
            ),
            Text(
              '倍增率: ${interpolatedData.totalOriginal > 0 ? ((interpolatedData.totalOriginal + interpolatedData.totalInterpolated) / interpolatedData.totalOriginal).toStringAsFixed(2) : "0.00"}x',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
            ),
            SizedBox(height: 16),

            // 最近數據流
            Text('最近數據流 (${interpolatedData.packets.length} 筆緩衝):'),
            Container(
              height: 100,
              child: ListView.builder(
                reverse: true, // 最新的在上面
                itemCount: interpolatedData.packets.length.clamp(0, 10),
                itemBuilder: (context, index) {
                  final reversedIndex =
                      interpolatedData.packets.length - 1 - index;
                  final packet = interpolatedData.packets[reversedIndex];
                  return Text(
                    '${packet.isInterpolated ? "📊" : "📦"} '
                    'ts=${packet.timestamp} '
                    '[${packet.data.take(3).join(',')}...]',
                    style: TextStyle(
                      fontSize: 11,
                      color: packet.isInterpolated ? Colors.blue : Colors.green,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
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
          _buildInterpolationStats(),

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

  /// 統計方法
  void _recordPacketsPerSecond() {
    if (_packetsInCurrentSecond > 0) {
      devLog('每秒統計', '第${_currentSecond + 1}秒: $_packetsInCurrentSecond 個封包');
    }

    _packetsInCurrentSecond = 0;
    _currentSecond++;

    // 每10秒輸出一次詳細統計
    if (_currentSecond % 10 == 0) {
      _printDetailedStats();
    }
  }

  /// 詳細統計報告
  void _printDetailedStats() {
    final elapsed = DateTime.now().difference(_statsStartTime!);
    final totalPackets = _originalPacketCount + _interpolatedPacketCount;
    final packetsPerSecond = elapsed.inSeconds > 0
        ? totalPackets / elapsed.inSeconds
        : 0;
    final interpolationRatio = _originalPacketCount > 0
        ? totalPackets / _originalPacketCount
        : 0;

    devLog('插值統計報告', '''
=== 簡單插值效果統計 (${elapsed.inSeconds}秒) ===
原始封包: $_originalPacketCount 個
插值封包: $_interpolatedPacketCount 個
總封包: $totalPackets 個
平均每秒: ${packetsPerSecond.toStringAsFixed(1)} 個
插值比例: ${interpolationRatio.toStringAsFixed(2)}:1
目標比例: 2.0:1 (16Hz → 32Hz)
達成率: ${(interpolationRatio / 2.0 * 100).toStringAsFixed(1)}%
  ''');
  }

  @override
  void initState() {
    super.initState();

    // 初始化統計
    _statsStartTime = DateTime.now();
    _statsTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      _recordPacketsPerSecond();
    });

    _requestPermissions().then((granted) {
      if (granted) {
        devLog('藍芽權限', 'Bluetooth permissions granted');
      } else {
        devLog('藍芽權限', 'Bluetooth permissions denied');
      }
    });
  }

  // @override
  // void dispose() {
  //   // 清理統計定時器
  //   _statsTimer?.cancel();

  //   // 1) 清理連線但不要呼叫 setState（避免在 dispose 期間觸發 rebuild 錯誤）
  //   _disconnectFromDevice(updateState: false);

  //   // 2) 取消所有通知訂閱與掃描訂閱
  //   for (var sub in _notifySubscriptions.values) {
  //     sub.cancel();
  //   }
  //   _notifySubscriptions.clear();

  //   _scanResultsSubscription?.cancel();
  //   _scanResultsSubscription = null;

  //   // 3) 呼叫 super.dispose
  //   super.dispose();
  // }

  // 在 dispose 時清理
  @override
  void dispose() {
    // 清理Provider數據
    ref.read(interpolatedDataProvider.notifier).clear();

    // 重置插值狀態
    _firstGroupPacket = null;
    _firstGroupTimestamp = null;
    _isWaitingForSecond = false;

    // 其他清理...
    _statsTimer?.cancel();
    _disconnectFromDevice(updateState: false);
    for (var sub in _notifySubscriptions.values) {
      sub.cancel();
    }
    _notifySubscriptions.clear();
    _scanResultsSubscription?.cancel();
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
