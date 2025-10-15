import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_itri_hrbr/model/broadcast_data.dart';
import 'package:flutter_itri_hrbr/model/health_data.dart';
import 'package:flutter_itri_hrbr/services/broadcast_mac_service.dart';
import 'package:flutter_riverpod/legacy.dart';

/// 階段 1：掃描服務 Provider（已有）
final broadcastServiceProvider =
    StateNotifierProvider<BroadcastMacService, BroadcastServiceState>((ref) {
      final service = BroadcastMacService(ref);
      ref.onDispose(service.cleanup);
      return service;
    });

/// 階段 2.1：Per-Device Provider（依 deviceId 分離）
final broadcastHealthFamily =
    StateNotifierProvider.family<
      BroadcastHealthNotifier,
      BroadcastHealthState,
      String // deviceId (MAC address)
    >((ref, deviceId) {
      return BroadcastHealthNotifier();
    });

// ========== 階段 2.1：新增 Per-Device 健康數據 Provider ==========

/// 階段 2.1：管理單台裝置的廣播數據
class BroadcastHealthNotifier extends StateNotifier<BroadcastHealthState> {
  BroadcastHealthNotifier() : super(const BroadcastHealthState());

  /// 更新最新封包（會在 service 中被呼叫）
  void updatePacket(
    List<int> rawPacket,
    BluetoothDevice? device,
  ) {
    state = state.copyWith(
      latestRawPacket: rawPacket,
      lastUpdateTime: DateTime.now(),
      packetCount: state.packetCount + 1,
      device: device,
    );
  }

  void updateSdkHealthData(HealthData sdkHealthData) {
    state = state.copyWith(sdkHealthData: sdkHealthData);
  }

  /// 清空數據（裝置離線時呼叫）
  void clear() {
    state = const BroadcastHealthState();
  }
}
