import 'package:flutter_itri_hrbr/model/health_data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/legacy.dart';

final perDeviceHealthProvider =
    StateNotifierProvider<
      PerDeviceHealthNotifier,
      Map<DeviceIdentifier, HealthData>
    >((ref) => PerDeviceHealthNotifier());

/// 建立一個「全 0 / 空」的預設 HealthData
/// 依你的 HealthData 建構子參數名稱調整 (若名稱不同請同步修改)
HealthData _zeroHealthData() => HealthData(
  hr: 0,
  br: 0,
  gyroX: 0,
  gyroY: 0,
  gyroZ: 0,
  temp: 0,
  hum: 0,
  spO2: 0,
  step: 0,
  power: 0,
  time: 0,
  hrFiltered: const [],
  brFiltered: const [],
  isWearing: false,
  rawData: const [],
  type: 0,
  fftOut: const [],
  petPose: 0,
);

/// 狀態為：每個 DeviceIdentifier 對應一份 HealthData
class PerDeviceHealthNotifier
    extends StateNotifier<Map<DeviceIdentifier, HealthData>> {
  PerDeviceHealthNotifier() : super({});

  void updateDevice(DeviceIdentifier id, HealthData newData) {
    final map = Map<DeviceIdentifier, HealthData>.from(state);
    map[id] = newData;
    state = map;
  }

  void patchDevice({
    required DeviceIdentifier id,
    int? hr,
    int? br,
    int? gyroX,
    int? gyroY,
    int? gyroZ,
    double? temp,
    double? hum,
    int? spO2,
    int? step,
    int? power,
    int? time,
    List<double>? hrFiltered,
    List<double>? brFiltered,
    bool? isWearing,
    List<int>? rawData,
    int? type,
    List<double>? fftOut,
    int? petPose,
  }) {
    final prev = state[id] ?? _zeroHealthData();
    final updated = prev.copyWith(
      hr: hr ?? prev.hr,
      br: br ?? prev.br,
      gyroX: gyroX ?? prev.gyroX,
      gyroY: gyroY ?? prev.gyroY,
      gyroZ: gyroZ ?? prev.gyroZ,
      temp: temp ?? prev.temp,
      hum: hum ?? prev.hum,
      spO2: spO2 ?? prev.spO2,
      step: step ?? prev.step,
      power: power ?? prev.power,
      time: time ?? prev.time,
      hrFiltered: hrFiltered ?? prev.hrFiltered,
      brFiltered: brFiltered ?? prev.brFiltered,
      isWearing: isWearing ?? prev.isWearing,
      rawData: rawData ?? prev.rawData,
      type: type ?? prev.type,
      fftOut: fftOut ?? prev.fftOut,
      petPose: petPose ?? prev.petPose,
    );
    updateDevice(id, updated);
  }

  // 批次更新多個裝置
  void batchUpdate(Map<DeviceIdentifier, HealthData> updates) {
    state = {...state, ...updates};
  }

  void removeDevice(DeviceIdentifier id) {
    if (!state.containsKey(id)) return;
    final map = Map<DeviceIdentifier, HealthData>.from(state)..remove(id);
    state = map;
  }

  void clearAll() {
    state = {};
  }
}
