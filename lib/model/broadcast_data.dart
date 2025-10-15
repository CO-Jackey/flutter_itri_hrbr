import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_itri_hrbr/model/health_data.dart';

/// 階段 1：廣播裝置資料模型
class BroadcastDevice {
  final String deviceId; // MAC address
  final String name;
  final int rssi;
  final List<int>? manufacturerData; // 原始廣播數據
  final DateTime lastSeen;

  const BroadcastDevice({
    required this.deviceId,
    required this.name,
    required this.rssi,
    this.manufacturerData,
    required this.lastSeen,
  });

  BroadcastDevice copyWith({
    String? deviceId,
    String? name,
    int? rssi,
    List<int>? manufacturerData,
    DateTime? lastSeen,
  }) {
    return BroadcastDevice(
      deviceId: deviceId ?? this.deviceId,
      name: name ?? this.name,
      rssi: rssi ?? this.rssi,
      manufacturerData: manufacturerData ?? this.manufacturerData,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

/// 階段 1：廣播服務狀態
class BroadcastServiceState {
  final Map<String, BroadcastDevice> devices; // key = deviceId
  final bool isScanning;

  const BroadcastServiceState({
    this.devices = const {},
    this.isScanning = false,
  });

  BroadcastServiceState copyWith({
    Map<String, BroadcastDevice>? devices,
    bool? isScanning,
  }) {
    return BroadcastServiceState(
      devices: devices ?? this.devices,
      isScanning: isScanning ?? this.isScanning,
    );
  }
}

/// 階段 2.1：單台裝置的廣播健康數據狀態
class BroadcastHealthState {
  final List<int>? latestRawPacket; // 最新一筆原始廣播封包
  final DateTime? lastUpdateTime; // 最後更新時間
  final int packetCount; // 累積收到的封包數
  final BluetoothDevice? device; // 對應的 BluetoothDevice 物件 (可選)
  final HealthData? sdkHealthData; // 解析後的健康數據 (可選)

  const BroadcastHealthState({
    this.latestRawPacket,
    this.lastUpdateTime,
    this.packetCount = 0,
    this.device,
    this.sdkHealthData,
  });

  BroadcastHealthState copyWith({
    List<int>? latestRawPacket,
    DateTime? lastUpdateTime,
    int? packetCount,
    BluetoothDevice? device,
    HealthData? sdkHealthData,
  }) {
    return BroadcastHealthState(
      latestRawPacket: latestRawPacket ?? this.latestRawPacket,
      lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
      packetCount: packetCount ?? this.packetCount,
      device: device ?? this.device,
      sdkHealthData: sdkHealthData ?? this.sdkHealthData,
    );
  }
}
