import 'dart:async';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_itri_hrbr/helper/devLog.dart';
import 'package:flutter_itri_hrbr/model/broadcast_data.dart';
import 'package:flutter_itri_hrbr/model/health_data.dart';
import 'package:flutter_itri_hrbr/provider/broadcasr_provider.dart'; // 新增
import 'package:flutter_itri_hrbr/services/HealthCalculate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:permission_handler/permission_handler.dart';

/// 階段 1：廣播服務核心
class BroadcastMacService extends StateNotifier<BroadcastServiceState> {
  /// 階段 2.2：修改 Service 構造函數，注入 Ref
  BroadcastMacService(this._ref) : super(const BroadcastServiceState());

  final Ref _ref;

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;
  Timer? _scanTimer;

  HealthCalculate? _healthCalculator;

  /// 階段 1：開始掃描廣播
  Future<void> startScan({
    // 不設時間參數，改為手動停止
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      // 1. 檢查權限（複用 muti_mac 的邏輯）
      if (!await _requestPermissions()) {
        devLog('廣播掃描', '❌ 權限不足');
        return;
      }

      // 2. 檢查藍牙是否開啟
      if (!await _checkBluetoothEnabled()) {
        devLog('廣播掃描', '❌ 藍牙未開啟');
        return;
      }

      // 3. 停止舊掃描
      if (state.isScanning) {
        await stopScan();
      }

      // 4. 清空舊資料
      state = state.copyWith(devices: {}, isScanning: true);
      devLog('廣播掃描', '🔍 開始掃描...');

      // 5. 監聽掃描結果
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
        final updatedDevices = Map<String, BroadcastDevice>.from(state.devices);

        for (final result in results) {
          if (result.device.platformName.isEmpty) {
            devLog('廣播篩選', '跳過：無 platformName -> ${result.device.remoteId}');
            continue;
          }

          final deviceId = result.device.remoteId.toString();
          final advData = result.advertisementData;

          // === 診斷模式：印出所有廣播內容 ===
          devLog('廣播原始', '''
            [裝置] $deviceId (${result.device.platformName})
            [RSSI] ${result.rssi}
            [名稱] ${advData.advName}
            [可連線] ${advData.connectable}
            [Manufacturer Data] ${advData.manufacturerData}
            [Service Data] ${advData.serviceData}
            [Service UUIDs] ${advData.serviceUuids}
            [Tx Power] ${advData.txPowerLevel}
          ''');

          // === 方案 A：優先從 manufacturerData 找（保留原邏輯）===
          List<int>? rawData;

          // // 只篩選出 ipet_B0:B2:1C:21:34:76 這個mac
          // /// 在最後面的mac有個空格
          // if (result.device.platformName == 'ipet_B0:B2:1C:21:34:76 ') {
          //   devLog('廣播模式篩選MAC', '✅ [$deviceId] 符合篩選條件');

          //   devLog(
          //     '廣播模式篩選MAC',
          //     '[Manufacturer Data] ${advData.manufacturerData}',
          //   );
          // }

          if (advData.manufacturerData.isNotEmpty) {
            // 嘗試找到符合長度的項目（不再只取第一個）
            for (final entry in advData.manufacturerData.entries) {
              devLog(
                '廣播MFG',
                '  CompanyID=${entry.key.toRadixString(16)}, Len=${entry.value.length}, Data=${entry.value}',
              );

              // 改為：只要長度 >= 15 就接受（不限定 17）
              if (entry.value.length >= 15) {
                rawData = entry.value;
                devLog('廣播MFG', '  ✅ 採用此筆 (len=${rawData.length})');
                break;
              }
            }
          }

          // === 方案 B：從 serviceData 找（新版可能在這）===
          if (rawData == null && advData.serviceData.isNotEmpty) {
            devLog('廣播SVC', '  嘗試從 serviceData 解析...');
            for (final entry in advData.serviceData.entries) {
              devLog(
                '廣播SVC',
                '  UUID=${entry.key}, Len=${entry.value.length}, Data=${entry.value}',
              );

              if (entry.value.length >= 15) {
                rawData = entry.value;
                devLog('廣播SVC', '  ✅ 採用此筆 (len=${rawData.length})');
                break;
              }
            }
          }

          // === 如果還是沒找到，記錄但不跳過（改為顯示「無有效數據」）===
          if (rawData == null) {
            devLog(
              '廣播篩選',
              '⚠️ [$deviceId] 無符合的數據 (mfg=${advData.manufacturerData.length}筆, svc=${advData.serviceData.length}筆)',
            );
            // 仍然加入列表，但標記為「無數據」
            updatedDevices[deviceId] = BroadcastDevice(
              deviceId: deviceId,
              name: result.device.platformName.isNotEmpty
                  ? result.device.platformName
                  : advData.advName.isNotEmpty
                  ? advData.advName
                  : '未命名裝置',
              rssi: result.rssi,
              manufacturerData: null, // 標記無有效數據
              lastSeen: DateTime.now(),
            );
            continue;
          }

          // === 長度驗證（改為警告而非過濾）===
          if (rawData.length < 15) {
            devLog('廣播長度', '⚠️ [$deviceId] 數據過短 (len=${rawData.length})，仍保留');
          }

          // === 階段 2.2：針對目標裝置，推送到 Provider ===
          if (result.device.platformName == 'ipet_B0:B2:1C:21:34:76 ') {
            devLog('廣播模式篩選MAC', '✅ [$deviceId] 符合篩選條件');

            devLog(
              '廣播模式篩選MAC',
              '[Manufacturer Data] ${advData.manufacturerData}',
            );
            if (rawData.isNotEmpty && rawData.length >= 15) {
              // 推送到對應裝置的 provider
              if (_ref.mounted) {
                _ref
                    .read(broadcastHealthFamily(deviceId).notifier)
                    .updatePacket(
                      rawData,
                      result.device,
                    );

                // SDK 解析（模擬）
                // await _healthCalculator!.splitPackage(
                //   Uint8List.fromList(currentPacket),
                // );

                // await _updateUIAndProvider(
                //   _ref,
                //   updatedDevices[deviceId]!,
                // );

                devLog(
                  '廣播推送',
                  '✅ [$deviceId] 已推送到 Provider (len=${rawData.length}, count=${_ref.read(broadcastHealthFamily(deviceId)).packetCount})',
                );
              }
            } else {
              devLog('廣播推送', '⚠️ [$deviceId] 符合條件但無有效數據');
            }
          }

          // 建立/更新裝置
          updatedDevices[deviceId] = BroadcastDevice(
            deviceId: deviceId,
            name: result.device.platformName.isNotEmpty
                ? result.device.platformName
                : advData.advName.isNotEmpty
                ? advData.advName
                : '未命名裝置',
            rssi: result.rssi,
            manufacturerData: rawData,
            lastSeen: DateTime.now(),
          );

          devLog('廣播接受', '✅ [$deviceId] 已加入列表 (data_len=${rawData.length})');
        }

        state = state.copyWith(devices: updatedDevices);
      });

      // 6. 開始掃描（不自動停止，因為廣播模式需要持續監聽）
      await FlutterBluePlus.startScan(
        //timeout: timeout,
        // androidUsesFineLocation: false, // 廣播模式不需要精確位置
      );

      // 7. 設定超時自動停止（可選）
      // _scanTimer = Timer(timeout, () {
      //   if (state.isScanning) {
      //     devLog('廣播掃描', '⏰ 掃描超時，自動停止');
      //     stopScan();
      //   }
      // });
    } catch (e) {
      devLog('廣播掃描', '❌ 錯誤: $e');
      state = state.copyWith(isScanning: false);
    }
  }

  /// 階段 1：停止掃描
  Future<void> stopScan() async {
    try {
      _scanTimer?.cancel();
      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      state = state.copyWith(isScanning: false);
      devLog('廣播掃描', '⏹️ 已停止');
    } catch (e) {
      devLog('廣播掃描', '停止錯誤: $e');
    }
  }

  /// 清理資源
  void cleanup() {
    _scanTimer?.cancel();
    _scanSubscription?.cancel();
    _adapterSubscription?.cancel();
    devLog('廣播服務', '🧹 已清理');
  }

  // --- 私有輔助方法（複用 muti_mac 邏輯）---

  Future<bool> _requestPermissions() async {
    try {
      if (Platform.isAndroid) {
        final statuses = await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.locationWhenInUse,
        ].request();
        return statuses[Permission.bluetoothScan]!.isGranted;
      } else if (Platform.isIOS) {
        return await Permission.bluetooth.request().isGranted;
      }
      return false;
    } catch (e) {
      devLog('權限', '錯誤: $e');
      return false;
    }
  }

  Future<bool> _checkBluetoothEnabled() async {
    try {
      final state = await FlutterBluePlus.adapterState.first;
      return state == BluetoothAdapterState.on;
    } catch (e) {
      devLog('藍牙狀態', '錯誤: $e');
      return false;
    }
  }

  /// 統一的UI和Provider更新方法
  Future<void> _updateUIAndProvider(
    Ref ref,
    BroadcastDevice device,
  ) async {
    // 獲取SDK結果
    final results = _extractAllResults();

    // 更新Provider
    ref
        .read(broadcastHealthFamily(device.deviceId).notifier)
        .updateSdkHealthData(
          HealthData(
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
                ? results['hrFiltered']
                      .map((e) => (e as num).toDouble())
                      .toList()
                : const [],
            brFiltered: (results['brFiltered'] is List)
                ? results['brFiltered']
                      .map((e) => (e as num).toDouble())
                      .toList()
                : const [],
            isWearing:
                results['isWearing'] == 1 || results['isWearing'] == true,
            rawData: (results['rawData'] is List)
                ? results['rawData'].map((e) => (e as num).toInt()).toList()
                : const [],
            type: results['type'],
            fftOut: results['fftOut'] is List
                ? results['fftOut']?.map((e) => (e as num).toDouble()).toList()
                : null,
            petPose: results['petPose'],
          ),
        );
    devLog('廣播更新', '✅ 已更新 Provider 的健康數據');
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
}
