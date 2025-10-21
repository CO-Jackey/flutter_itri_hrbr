import 'package:flutter_itri_hrbr/model/health_data.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 🎯 核心 Provider：每個裝置獨立的 Family Provider
// ═══════════════════════════════════════════════════════════════════════════

/// 多裝置健康資料 Provider（Family 模式）
/// 
/// 📋 使用方式：
/// - 讀取：`ref.watch(multiDeviceHealthProvider(deviceId))`
/// - 更新：`ref.read(multiDeviceHealthProvider(deviceId).notifier).update(data)`
/// - 清理：`ref.invalidate(multiDeviceHealthProvider(deviceId))`
final multiDeviceHealthProvider = StateNotifierProvider.family<
    MultiDeviceHealthNotifier,
    HealthData,
    DeviceIdentifier  // ← Family 參數：裝置 ID
>((ref, deviceId) => MultiDeviceHealthNotifier(deviceId));

// ═══════════════════════════════════════════════════════════════════════════
// 🏭 批次操作管理器（集中管理多裝置更新）
// ═══════════════════════════════════════════════════════════════════════════

/// 批次健康資料更新管理器
/// 
/// 📋 功能：
/// - `batchUpdate()`：批次更新多個裝置
/// - `removeDevice()`：移除單一裝置資料
/// - `clearAll()`：清空所有裝置資料
final batchHealthUpdaterProvider = Provider((ref) => BatchHealthUpdater(ref));

// ═══════════════════════════════════════════════════════════════════════════
// 📦 輔助工具：預設空資料
// ═══════════════════════════════════════════════════════════════════════════

/// 建立一個「全 0 / 空」的預設 HealthData
HealthData _zeroHealthData() => HealthData(
  hr: 0,
  br: 0,
  gyroX: 0,
  gyroY: 0,
  gyroZ: 0,
  temp: 0.0,
  hum: 0.0,
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
  splitRawData: const [],
);

// ═══════════════════════════════════════════════════════════════════════════
// 🧠 單一裝置的健康資料管理器
// ═══════════════════════════════════════════════════════════════════════════

/// 單一裝置的健康資料狀態管理
/// 
/// 📋 提供方法：
/// - `update()`：完整更新
/// - `patch()`：部分更新
/// - `reset()`：重置為空資料
class MultiDeviceHealthNotifier extends StateNotifier<HealthData> {
  final DeviceIdentifier deviceId;

  /// 建構子：初始化為空資料
  MultiDeviceHealthNotifier(this.deviceId) : super(_zeroHealthData());

  // ─────────────────────────────────────────────────────────────────────────
  // ✅ 完整更新：替換整個 HealthData
  // ─────────────────────────────────────────────────────────────────────────
  
  /// 完整更新健康資料
  /// 
  /// 使用時機：從藍牙接收到完整的新資料
  void update(HealthData newData) {
    state = newData;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 🔧 部分更新：只更新指定欄位
  // ─────────────────────────────────────────────────────────────────────────
  
  /// 部分更新健康資料（patch）
  /// 
  /// 使用時機：只需更新特定欄位時
  /// 
  /// 範例：
  /// ```dart
  /// notifier.patch(hr: 75, temp: 36.5);
  /// ```
  void patch({
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
    List<int>? splitRawData,
  }) {
    state = state.copyWith(
      hr: hr ?? state.hr,
      br: br ?? state.br,
      gyroX: gyroX ?? state.gyroX,
      gyroY: gyroY ?? state.gyroY,
      gyroZ: gyroZ ?? state.gyroZ,
      temp: temp ?? state.temp,
      hum: hum ?? state.hum,
      spO2: spO2 ?? state.spO2,
      step: step ?? state.step,
      power: power ?? state.power,
      time: time ?? state.time,
      hrFiltered: hrFiltered ?? state.hrFiltered,
      brFiltered: brFiltered ?? state.brFiltered,
      isWearing: isWearing ?? state.isWearing,
      rawData: rawData ?? state.rawData,
      type: type ?? state.type,
      fftOut: fftOut ?? state.fftOut,
      petPose: petPose ?? state.petPose,
      splitRawData: splitRawData ?? state.splitRawData,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 🗑️ 重置資料
  // ─────────────────────────────────────────────────────────────────────────
  
  /// 重置為初始空資料
  /// 
  /// 使用時機：裝置斷線後清空資料
  void reset() {
    state = _zeroHealthData();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🎛️ 批次操作管理器實作
// ═══════════════════════════════════════════════════════════════════════════

/// 批次健康資料更新管理器
/// 
/// 📋 職責：
/// - 提供批次操作的統一介面
/// - 避免在 Service 層直接操作 provider
class BatchHealthUpdater {
  final Ref _ref;

  BatchHealthUpdater(this._ref);

  // ─────────────────────────────────────────────────────────────────────────
  // 📤 批次更新多個裝置
  // ─────────────────────────────────────────────────────────────────────────
  
  /// 批次更新多個裝置的健康資料
  /// 
  /// 📋 使用時機：
  /// - Service 累積多個裝置的資料後統一送出
  /// - 減少 UI rebuild 次數
  /// 
  /// 範例：
  /// ```dart
  /// final updates = {
  ///   deviceId1: healthData1,
  ///   deviceId2: healthData2,
  /// };
  /// batchUpdater.batchUpdate(updates);
  /// ```
  void batchUpdate(Map<DeviceIdentifier, HealthData> updates) {
    for (final entry in updates.entries) {
      _ref
          .read(multiDeviceHealthProvider(entry.key).notifier)
          .update(entry.value);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 🗑️ 移除單一裝置
  // ─────────────────────────────────────────────────────────────────────────
  
  /// 移除單一裝置的健康資料
  /// 
  /// 📋 使用時機：
  /// - 裝置斷線時清理資料
  /// 
  /// 🔧 實作方式：
  /// 1. 先重置為空資料（可選）
  /// 2. 完全 invalidate 該 provider（釋放記憶體）
  void removeDevice(DeviceIdentifier id) {
    // 步驟 1：重置資料（可選，視需求決定是否保留）
    // _ref.read(multiDeviceHealthProvider(id).notifier).reset();

    // 步驟 2：完全移除該 family instance（釋放記憶體）
    _ref.invalidate(multiDeviceHealthProvider(id));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 🧹 清空所有裝置
  // ─────────────────────────────────────────────────────────────────────────
  
  /// 清空所有裝置的健康資料
  /// 
  /// 📋 使用時機：
  /// - 批次斷線時一次性清理所有裝置
  /// - App 重置時清空所有資料
  /// 
  /// ⚠️ 注意：
  /// - 需要傳入所有裝置 ID 列表
  /// - 會 invalidate 所有 family instance
  void clearAll(List<DeviceIdentifier> deviceIds) {
    for (final id in deviceIds) {
      _ref.invalidate(multiDeviceHealthProvider(id));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 🔍 輔助方法：檢查裝置是否有資料（可選）
  // ─────────────────────────────────────────────────────────────────────────
  
  /// 檢查裝置是否有非空資料
  /// 
  /// 📋 判斷邏輯：
  /// - 心率 > 0 或體溫 > 0 視為有效資料
  bool hasValidData(DeviceIdentifier id) {
    try {
      final data = _ref.read(multiDeviceHealthProvider(id));
      return data.hr > 0 || data.temp > 0;
    } catch (e) {
      // Provider 不存在
      return false;
    }
  }

  /// 取得所有有資料的裝置 ID（可選）
  /// 
  /// ⚠️ 限制：
  /// - Family provider 無法直接列舉所有 instance
  /// - 必須由外部傳入 deviceIds 列表
  List<DeviceIdentifier> getActiveDevices(List<DeviceIdentifier> allDeviceIds) {
    return allDeviceIds.where((id) => hasValidData(id)).toList();
  }
}
