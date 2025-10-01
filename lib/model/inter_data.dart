// 插值數據包結構
class InterpolatedPacket {
  final List<int> data;
  final int timestamp;
  final bool isInterpolated;
  
  InterpolatedPacket({
    required this.data,
    required this.timestamp,
    required this.isInterpolated,
  });
}

// 插值數據狀態
class InterpolatedDataState {
  final List<InterpolatedPacket> packets;
  final int totalOriginal;
  final int totalInterpolated;
  
  const InterpolatedDataState({
    this.packets = const [],
    this.totalOriginal = 0,
    this.totalInterpolated = 0,
  });
  
  InterpolatedDataState copyWith({
    List<InterpolatedPacket>? packets,
    int? totalOriginal,
    int? totalInterpolated,
  }) {
    return InterpolatedDataState(
      packets: packets ?? this.packets,
      totalOriginal: totalOriginal ?? this.totalOriginal,
      totalInterpolated: totalInterpolated ?? this.totalInterpolated,
    );
  }
}