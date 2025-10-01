import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_itri_hrbr/helper/devLog.dart';
import 'package:flutter_itri_hrbr/model/inter_data.dart';
import 'package:flutter_itri_hrbr/services/data_Classifier_Service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../model/health_data.dart';

// 為 DataClassifierService 創建一個全局的 Provider
// 讓 App 中任何地方都能取用同一個分類服務實例
final dataClassifierProvider = Provider<DataClassifierService>((ref) {
  return DataClassifierService();
});

final healthDataProvider =
    StateNotifierProvider<HealthDataNotifier, HealthData>(
      (ref) => HealthDataNotifier(),
    );

final filteredFirstRawDataProvider =
    StateNotifierProvider<HealthDataNotifier, HealthData>(
      (ref) => HealthDataNotifier(),
    );

final filteredSecondRawDataProvider =
    StateNotifierProvider<HealthDataNotifier, HealthData>(
      (ref) => HealthDataNotifier(),
    );

// Provider定義
final interpolatedDataProvider =
    StateNotifierProvider<InterpolatedDataNotifier, InterpolatedDataState>(
      (ref) => InterpolatedDataNotifier(),
    );

// 新增：依裝置分離的第一組 / 第二組 raw data (仍沿用 HealthDataNotifier 結構)
final mutiFilteredFirstRawDataFamily =
    StateNotifierProvider.family<
      HealthDataNotifier,
      HealthData,
      DeviceIdentifier
    >((ref, id) {
      return HealthDataNotifier();
    });

final mutiFilteredSecondRawDataFamily =
    StateNotifierProvider.family<
      HealthDataNotifier,
      HealthData,
      DeviceIdentifier
    >((ref, id) {
      return HealthDataNotifier();
    });

class HealthDataNotifier extends StateNotifier<HealthData> {
  HealthDataNotifier() : super(const HealthData());

  void normalUpdate({
    List<int>? splitRawData,
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
    List<dynamic>? hrFiltered,
    List<dynamic>? brFiltered,
    bool? isWearing,
    List<dynamic>? rawData,
    int? type,
    List<dynamic>? fftOut,
    int? petPose,
  }) {
    state = state.copyWith(
      splitRawData: splitRawData,
      rawData: rawData,
      hr: hr,
      br: br,
      gyroX: gyroX,
      gyroY: gyroY,
      gyroZ: gyroZ,
      temp: temp,
      hum: hum,
      spO2: spO2,
      step: step,
      power: power,
      time: time,
      hrFiltered: hrFiltered,
      brFiltered: brFiltered,
      isWearing: isWearing,
      type: type,
      fftOut: fftOut,
      petPose: petPose,
    );
  }

  /// 新需求：
  /// 1. 只在「第一次有效封包」時記住第 6 位 (baseline)。
  /// 2. 之後若封包第 6 位 == baseline，就存進 filteredFirstRawDataProvider。
  /// 3. 不再每次更新 baseline，也不需要比較「上一筆」。
  /// 4. petPose (<5) 條件如果仍要保留就一起判斷；若不要可移除 petPoseOk。
  DataType filterData(List<int> splitRawData, WidgetRef ref) {
    // 長度不足：當成無法判斷，直接丟 second 並記錄

    final dataType = ref
        .read(dataClassifierProvider)
        .classify(Uint8List.fromList(splitRawData));

    switch (dataType) {
      case DataType.first:
        devLog('filterData', "分類結果：✅ 第一組 -> $splitRawData");
        ref
            .read(filteredFirstRawDataProvider.notifier)
            .normalUpdate(splitRawData: splitRawData);
        break;

      case DataType.second:
        devLog('filterData', "分類結果：💠 第二組 -> $splitRawData");
        ref
            .read(filteredSecondRawDataProvider.notifier)
            .normalUpdate(splitRawData: splitRawData);
        break;

      case DataType.noise:
        devLog('filterData', "分類結果：🗑️ 過渡期雜訊 -> 已忽略，不更新任何 Provider");
        // 故意不做任何事，成功過濾掉雜訊
        break;

      case DataType.unknown:
        devLog('filterData', "分類結果：❓ 無法分類 -> 已忽略");
        break;
    }
    // 將分類結果回傳出去
    return dataType;
  }

  DataType mutiFilterData(
    List<int> splitRawData,
    DeviceIdentifier deviceId,
    Ref ref,
  ) {
    // 長度不足：當成無法判斷，直接丟 second 並記錄

    final dataType = ref
        .read(dataClassifierProvider)
        .classify(Uint8List.fromList(splitRawData));

    switch (dataType) {
      case DataType.first:
        devLog('filterData', "裝置ID: $deviceId, 分類結果：✅ 第一組 -> $splitRawData");
        ref
            .read(mutiFilteredFirstRawDataFamily(deviceId).notifier)
            .normalUpdate(splitRawData: splitRawData);
        break;

      case DataType.second:
        devLog('filterData', "裝置ID: $deviceId, 分類結果：💠 第二組 -> $splitRawData");
        ref
            .read(mutiFilteredSecondRawDataFamily(deviceId).notifier)
            .normalUpdate(splitRawData: splitRawData);
        break;

      case DataType.noise:
        devLog('filterData', "分類結果：🗑️ 過渡期雜訊 -> 已忽略，不更新任何 Provider");
        // 故意不做任何事，成功過濾掉雜訊
        break;

      case DataType.unknown:
        devLog('filterData', "分類結果：❓ 無法分類 -> 已忽略");
        break;
    }
    // 將分類結果回傳出去
    return dataType;
  }
}

// 插值數據管理器
class InterpolatedDataNotifier extends StateNotifier<InterpolatedDataState> {
  InterpolatedDataNotifier() : super(const InterpolatedDataState());

  void addPacket(InterpolatedPacket packet) {
    final newPackets = [...state.packets, packet];
    // 保持最多100筆避免記憶體問題
    if (newPackets.length > 100) {
      newPackets.removeAt(0);
    }

    state = state.copyWith(
      packets: newPackets,
      totalOriginal: packet.isInterpolated
          ? state.totalOriginal
          : state.totalOriginal + 1,
      totalInterpolated: packet.isInterpolated
          ? state.totalInterpolated + 1
          : state.totalInterpolated,
    );
  }

  void clear() {
    state = const InterpolatedDataState();
  }
}
