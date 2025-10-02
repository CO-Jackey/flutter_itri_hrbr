import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_itri_hrbr/helper/devLog.dart';

class HealthCalculate {
  // 定義平台通道的名稱，這個名稱在 Dart 和 Java/Kotlin 中必須完全一樣
  static const MethodChannel _channel = MethodChannel(
    'com.example.flutter_itri_hrbr/health_calculate',
  );

  // 私有變數，用於緩存從原生端獲取的最新數據
  int _hr = 0;
  int _br = 0;
  int _gyroX = 0;
  int _gyroY = 0;
  int _gyroZ = 0;
  dynamic _temp = 0;
  int _hum = 0;
  int _spO2 = 0;
  int _step = 0;
  int _power = 0;
  int _time = 0;
  int _type = 0; // pet type
  // 將 _FFTOut 改為陣列型態
  List<double> _FFTOut = []; // FFT輸出數據
  // 將 _hrFiltered/_brFiltered 型別指定為 List<double>
  List<double> _hrFiltered = [];
  List<double> _brFiltered = [];
  bool _isWearing = false;
  List _rawData = [];
  int _petPose = -2; // 寵物姿勢

  // 初始化時，呼叫原生端的初始化方法
  HealthCalculate(int type) {
    _channel.invokeMethod('initialize', {'type': type});
  }

  /// 將從藍牙收到的數據包發送到原生端進行解析
  Future<void> splitPackage(Uint8List data) async {
    // 🔥 增加檢查
    if (data.isEmpty || data.length < 17) {
      devLog('HealthCalculate', '⚠️ 收到不完整資料 (長度: ${data.length})，已忽略');
      return;
    }

    try {
      // 呼叫原生端的 'splitPackage' 方法，並傳遞 byte array
      // invokeMapMethod 會等待原生端返回一個 Map
      final Map<dynamic, dynamic>? result = await _channel.invokeMapMethod(
        'splitPackage',
        {'data': data},
      );

      if (result != null) {
        // helper: 依序嘗試多個可能的 key（對應 Kotlin 回傳的大小寫差異）
        dynamic _get(Map m, List<String> keys) {
          for (final k in keys) {
            if (m.containsKey(k)) return m[k];
          }
          return null;
        }

        _hr = (_get(result, ['HRValue', 'hr', 'HR']) as num?)?.toInt() ?? _hr;
        _br = (_get(result, ['BRValue', 'br', 'BR']) as num?)?.toInt() ?? _br;

        _gyroX =
            (_get(result, ['GyroValueX', 'gyroX']) as num?)?.toInt() ?? _gyroX;
        _gyroY =
            (_get(result, ['GyroValueY', 'gyroY']) as num?)?.toInt() ?? _gyroY;
        _gyroZ =
            (_get(result, ['GyroValueZ', 'gyroZ']) as num?)?.toInt() ?? _gyroZ;

        _temp = (_get(result, ['TempValue', 'temp']) as num?) ?? _temp;
        _hum =
            (_get(result, ['HumValue', 'hum', 'Hum']) as num?)?.toInt() ?? _hum;
        _spO2 =
            (_get(result, ['SpO2Value', 'spO2', 'SPO2']) as num?)?.toInt() ??
            _spO2;
        _step = (_get(result, ['StepValue', 'step']) as num?)?.toInt() ?? _step;
        _power =
            (_get(result, ['PowerValue', 'power']) as num?)?.toInt() ?? _power;
        _time =
            (_get(result, ['TimeStamp', 'time', 'Time']) as num?)?.toInt() ??
            _time;
        _type = (_get(result, ['Type', 'type']) as num?)?.toInt() ?? _type;

        // 陣列欄位（嘗試大小寫多個 key）
        final hrFiltRaw = _get(result, ['HRFiltered', 'hrFiltered']);
        if (hrFiltRaw is List) {
          _hrFiltered = hrFiltRaw.map((e) => (e as num).toDouble()).toList();
        }

        final brFiltRaw = _get(result, ['BRFiltered', 'brFiltered']);
        if (brFiltRaw is List) {
          _brFiltered = brFiltRaw.map((e) => (e as num).toDouble()).toList();
        }

        final fftRaw = _get(result, ['FFTOut', 'fftOut']);
        if (fftRaw is List) {
          _FFTOut = fftRaw.map((e) => (e as num).toDouble()).toList();
        }

        final rawRaw = _get(result, ['RawData', 'rawData']);
        if (rawRaw is List) {
          _rawData = rawRaw.map((e) => (e as num).toInt()).toList();
        }

        _isWearing =
            (_get(result, ['IsWearing', 'isWearing']) as bool?) ?? _isWearing;
        _petPose =
            (_get(result, ['PetPoseValue', 'petPose']) as num?)?.toInt() ??
            _petPose;
      }
    } on PlatformException catch (e) {
      devLog('呼叫原生 splitPackage 失敗:', '${e.message}');
    }
  }

  // 提供獲取數據的方法，直接返回緩存的值
  int getHRValue() => _hr;
  int getBRValue() => _br;
  int getGyroValueX() => _gyroX;
  int getGyroValueY() => _gyroY;
  int getGyroValueZ() => _gyroZ;
  dynamic getTempValue() => _temp;
  dynamic getHumValue() => _hum;
  dynamic getSpO2Value() => _spO2;
  dynamic getStepValue() => _step;
  dynamic getPowerValue() => _power;
  dynamic getTimeStamp() => _time;
  dynamic getType() => _type;
  List<double> getHRFiltered() => _hrFiltered;
  List<double> getBRFiltered() => _brFiltered;
  bool getIsWearing() => _isWearing;
  List getRawData() => _rawData;
  List<double> getFFTOut() => _FFTOut;
  int getPetPoseValue() => _petPose;

  void dispose() {
    _channel.invokeMethod('dispose');
  }
}
