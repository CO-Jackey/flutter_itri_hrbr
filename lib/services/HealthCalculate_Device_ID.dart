import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_itri_hrbr/helper/devLog.dart';

class HealthCalculateDeviceID {
  static const MethodChannel _channel = MethodChannel(
    'com.example.flutter_itri_hrbr/health_calculate',
  );

  final int type;

  // 快取最後一次的結果
  Map<String, dynamic>? _lastResult;

  HealthCalculateDeviceID(this.type) {
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _channel.invokeMethod('initialize', {'type': type});
      devLog('SDK', '✅ HealthCalculateDeviceID 初始化完成 (type: $type)');
    } catch (e) {
      devLog('SDK 錯誤', '初始化失敗: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 主要方法
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>?> splitPackage(
    Uint8List data,
    String deviceId,
  ) async {
    try {
      final result = await _channel.invokeMethod('splitPackage', {
        'data': data,
        'deviceId': deviceId,
      });

      if (result != null) {
        _lastResult = Map<String, dynamic>.from(result);
        return _lastResult;
      }
      return null;
    } catch (e) {
      devLog('SDK 錯誤', 'splitPackage 失敗: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 清理方法
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> dispose(String deviceId) async {
    try {
      await _channel.invokeMethod('dispose', {'deviceId': deviceId});
      _lastResult = null;
      devLog('SDK', '✅ 已清理設備 $deviceId 的 SDK 實例');
    } catch (e) {
      devLog('SDK 錯誤', 'dispose 失敗: $e');
    }
  }

  // ✅ 新增：重置特定設備（不用 dispose，直接重建）
  Future<bool> reset(String deviceId) async {
    try {
      final result = await _channel.invokeMethod('reset', {
        'deviceId': deviceId,
      });
      _lastResult = null;
      devLog('SDK', '✅ 已重置設備 $deviceId 的 SDK 實例');
      return result == true;
    } catch (e) {
      devLog('SDK 錯誤', 'reset 失敗: $e');
      return false;
    }
  }

  // ✅ 新增：檢查 SDK 實例狀態
  Future<Map<String, dynamic>?> getStatus({String? deviceId}) async {
    try {
      final result = await _channel.invokeMethod('getStatus', {
        'deviceId': deviceId,
      });
      return result != null ? Map<String, dynamic>.from(result) : null;
    } catch (e) {
      devLog('SDK 錯誤', 'getStatus 失敗: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Getter 方法（從快取取得）
  // ═══════════════════════════════════════════════════════════════════════════

  int getHRValue() => _lastResult?['HRValue'] ?? 0;
  int getBRValue() => _lastResult?['BRValue'] ?? 0;
  int getGyroValueX() => _lastResult?['GyroValueX'] ?? 0;
  int getGyroValueY() => _lastResult?['GyroValueY'] ?? 0;
  int getGyroValueZ() => _lastResult?['GyroValueZ'] ?? 0;
  double getTempValue() => (_lastResult?['TempValue'] ?? 0).toDouble();
  double getHumValue() => (_lastResult?['HumValue'] ?? 0).toDouble();
  int getSpO2Value() => _lastResult?['SpO2Value'] ?? 0;
  int getStepValue() => _lastResult?['StepValue'] ?? 0;
  int getPowerValue() => _lastResult?['PowerValue'] ?? 0;
  int getTimeStamp() => _lastResult?['TimeStamp'] ?? 0;
  int getType() => _lastResult?['Type'] ?? 0;
  bool getIsWearing() => _lastResult?['IsWearing'] ?? false;
  int getPetPoseValue() => _lastResult?['PetPoseValue'] ?? 0;

  List<double> getHRFiltered() {
    final data = _lastResult?['HRFiltered'];
    if (data is List) {
      return data.map((e) => (e as num).toDouble()).toList();
    }
    return [];
  }

  List<double> getBRFiltered() {
    final data = _lastResult?['BRFiltered'];
    if (data is List) {
      return data.map((e) => (e as num).toDouble()).toList();
    }
    return [];
  }

  List<int> getRawData() {
    final data = _lastResult?['RawData'];
    if (data is List) {
      return data.map((e) => (e as num).toInt()).toList();
    }
    return [];
  }

  List<double>? getFFTOut() {
    final data = _lastResult?['FFTOut'];
    if (data is List) {
      return data.map((e) => (e as num).toDouble()).toList();
    }
    return null;
  }

  // // ✅ 新增：取得 splitResult 狀態碼
  // int getSplitResult() => _lastResult?['splitResult'] ?? 0;
  // String getSplitResultMessage() =>
  //     _lastResult?['splitResultMessage'] ?? 'UNKNOWN';

  // // ✅ 新增：取得最後處理的 deviceId
  // String? getLastDeviceId() => _lastResult?['deviceId'];

  // // ✅ 新增：取得最後的原始 split 結果
  // List<int> getLastSplitResult() {
  //   final rawData = _lastResult?['RawData'];
  //   if (rawData is List) {
  //     return rawData.map((e) => (e as num).toInt()).toList();
  //   }
  //   return [];
  // }
}
