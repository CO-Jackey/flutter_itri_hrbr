import 'package:flutter_itri_hrbr/helper/devLog.dart';
import 'package:flutter_itri_hrbr/services/bluetooth_itri_service.dart';

/// 定義最終的數據分類結果
enum DataType {
  first,
  second,
  noise, // 過渡期雜訊
  unknown,
}

/// 數據分類服務，封裝了所有分類邏輯。
class DataClassifierService {
  // 服務內部持有一個第一組數據的專屬過濾器。
  final DynamicBaselineFilter _firstFilter = DynamicBaselineFilter();

  /// 接收原始數據，並回傳最終的分類結果。
  DataType classify(List<int> rawData) {
    // 獲取第一組過濾器的詳細決策
    final FilterDecision decision = _firstFilter.filter(rawData);

    //devLog('filterData', _firstFilter.getStatus().toString());

    // 根據過濾器的決策「理由」，來進行最終的業務分類
    switch (decision) {
      case FilterDecision.accepted:
        // 過濾器接受了，這明確是「第一組」數據
        return DataType.first;

      case FilterDecision.rejectedByPreFilter:
      case FilterDecision.rejectedByStableDrift:
        // 這兩種情況被我們視為「真正的第二組」數據
        return DataType.second;

      case FilterDecision.rejectedDuringTakeover:
        // 這種情況被我們視為「過渡期雜訊」，需要被忽略
        return DataType.noise;
    }
  }

  /// 提供獲取過濾器內部狀態的方法，方便調試
  Map<String, dynamic> getFilterStatus() {
    return _firstFilter.getStatus();
  }
}
