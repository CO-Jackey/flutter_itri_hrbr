/// 檔案: lib/logic/dynamic_baseline_filter.dart

/// 定義過濾器的決策結果，提供比 bool 更豐富的資訊。
/// 這讓我們可以知道數據被接受或拒絕的確切「理由」。
enum FilterDecision {
  /// 數據符合當前基準，被接受。
  accepted,

  /// 因不滿足 value13 < 5 等硬性預篩選規則而被拒絕。
  /// 這種數據明確不屬於第一組。
  rejectedByPreFilter,

  /// 基準值穩定，但數據因偏離基準值 (drift) 而被拒絕。
  /// 這種數據有可能是「真正的第二組」數據。
  rejectedByStableDrift,

  /// 在基準值正在「奪權」切換的過程中，數據被拒絕。
  /// 這種數據很可能是學習過程中的「過渡期雜訊」。
  rejectedDuringTakeover,
}

/// 一個動態數據過濾器，它能從數據流中自我學習基準值，
/// 並能快速適應基準值的突然變化。
///
/// 核心思想是「雙軌學習」：
/// 1. 【穩定軌】：處理符合當前基準的數據。
/// 2. 【候選軌】：監控被拒絕的數據，尋找可能的新基準值。
class DynamicBaselineFilter {
  // --- 可配置的常數 ---

  /// 最小信心度閾值。
  /// 在建立初始基準值之前，需要收集的最小樣本數量。
  final int minConfidence;

  /// 奪權閾值。
  /// 一個新的候選值需要連續出現幾次，才能被確認為新的基準值。
  final int takeoverThreshold;

  // --- 穩定軌 (Stable Track) 的內部狀態 ---

  /// 【穩定軌】當前被系統信任的基準值 (例如 49)。
  /// 初始為 null，表示系統處於初始學習階段。
  int? _targetBaseValue;

  /// 【穩定軌】統計各個 value6 出現的次數，用於學習和觀察。
  final Map<int, int> _value6Counts = {};

  /// 【穩定軌】已收集的有效樣本總數。
  int _totalValidSamples = 0;

  // --- 候選軌 (Candidate Track) 的內部狀態 ---

  /// 【候選軌】當前的「候選」基準值 (例如 52)。
  /// 當一個數據被穩定軌拒絕時，它就可能成為候選值。
  int? _takeoverCandidateValue;

  /// 【候選軌】候選值連續出現的次數。
  int _takeoverConsecutiveCount = 0;

  /// 構造函數，允許在創建實例時自定義配置。
  DynamicBaselineFilter({
    this.minConfidence = 3,
    this.takeoverThreshold = 3,
  });

  /// 核心過濾方法，處理傳入的每一筆數據，並返回詳細的決策結果。
  /// [array]: 來自數據源的原始數據列表。
  /// 返回: 一個 [FilterDecision] 枚舉，詳細說明判斷結果。
  FilterDecision filter(List<int> array) {
    // 步驟 1: 預篩選 (硬規則)，過濾掉明確不符的數據。
    if (array.length < 13 || array[12] >= 5) {
      return FilterDecision.rejectedByPreFilter;
    }

    // 提取我們關心的第 6 位 (index 5) 的值。
    final int value6 = array[5];

    // 步驟 2: 初始學習階段。當還沒有建立基準值時執行。
    if (_targetBaseValue == null) {
      // 將當前的 value6 納入統計。
      _value6Counts[value6] = (_value6Counts[value6] ?? 0) + 1;
      _totalValidSamples++;

      // 根據已有的統計數據，嘗試更新基準值。
      _updateBaseValue();

      // 在學習期，我們總是接受數據，以盡快建立基準。
      return FilterDecision.accepted;
    }

    // 步驟 3: 穩定軌驗證。當已存在基準值時執行。
    // 檢查當前的 value6 是否在基準值的容忍範圍內 (±1)。
    if ((value6 - _targetBaseValue!).abs() <= 1) {
      // 數據符合基準，是正常的「第一組」數據。

      // *** 關鍵修正 ***
      // 即使在穩定階段，我們仍然要持續學習，更新我們的統計數據。
      // 這樣 getStatus() 才能反映真實、持續的數據分佈。
      _value6Counts[value6] = (_value6Counts[value6] ?? 0) + 1;
      _totalValidSamples++;

      // 在每次更新計數後，都重新計算一次基準值
      // 這樣如果 91 的計數超過 90，基準值就會自動漂移過去
      _updateBaseValue(); // <--- 新增這一行

      // 因為來了一筆正常數據，所以重置任何正在進行中的「奪權」嘗試。
      // 這能有效防止系統被短期的連續雜訊誤導。
      _resetTakeoverAttempt();

      // 返回「接受」的決策。
      return FilterDecision.accepted;
    } else {
      // 數據不符合基準，是異常數據，需要判斷拒絕的理由。

      // 在處理奪權邏輯前，先記錄下當前是否已經在奪權過程中。
      final bool isDuringTakeover = _takeoverCandidateValue != null;

      // 將這筆被拒絕的數據交給「候選軌」處理。
      _handleTakeoverAttempt(value6);

      // 根據是否在奪權過程中，回傳不同的拒絕理由。
      if (isDuringTakeover) {
        // 如果拒絕時，系統已在觀察一個候選值，那麼這次拒絕很可能是過渡期的混亂。
        return FilterDecision.rejectedDuringTakeover;
      } else {
        // 如果系統很穩定（沒有候選值），但數據仍然不符，這更有可能是真正的「另一種」數據。
        return FilterDecision.rejectedByStableDrift;
      }
    }
  }

  // --- 以下為內部輔助方法 ---

  /// 處理「候選軌」的邏輯，管理奪權嘗試。
  void _handleTakeoverAttempt(int candidateValue) {
    // 檢查這個新的異常值，是否和我們正在觀察的候選值相同。
    if (candidateValue == _takeoverCandidateValue) {
      // 相同，說明候選值連續出現了，計數加一。
      _takeoverConsecutiveCount++;
    } else {
      // 不相同，說明來了一個全新的挑戰者，重置候選軌並從 1 開始計數。
      _takeoverCandidateValue = candidateValue;
      _takeoverConsecutiveCount = 1;
    }

    // 檢查候選值的連續出現次數是否已達到「奪權」的閾值。
    if (_takeoverConsecutiveCount >= takeoverThreshold) {
      // 滿足條件，執行奪權！
      _promoteCandidateToBaseline();
    }
  }

  /// 將成功的候選值提升為新的基準值，完成「奪權」。
  void _promoteCandidateToBaseline() {
    // 將穩定軌的基準值更新為新的候選值。
    _targetBaseValue = _takeoverCandidateValue;

    // 重置整個學習狀態，讓系統圍繞新的基準值重新建立信心。
    // 這避免了舊的大量統計數據干擾新的基準。
    _value6Counts.clear();
    _totalValidSamples = 0;

    // 為新的基準值設定初始計數。
    _value6Counts[_targetBaseValue!] = 1;
    _totalValidSamples = 1;

    // 重置候選軌，因為它的任務已經完成。
    _resetTakeoverAttempt();
  }

  /// 重置「候選軌」的狀態。
  void _resetTakeoverAttempt() {
    _takeoverCandidateValue = null;
    _takeoverConsecutiveCount = 0;
  }

  /// 在初始學習階段，從 `_value6Counts` 中找出最常見的值來更新基準。
  void _updateBaseValue() {
    if (_value6Counts.isEmpty) return;

    int mostCommonValue = _value6Counts.keys.first;
    int maxCount = 0;
    _value6Counts.forEach((value, count) {
      if (count > maxCount) {
        maxCount = count;
        mostCommonValue = value;
      }
    });

    // 直接更新基準值為當前統計中次數最多的那個
    _targetBaseValue = mostCommonValue;
  }

  /// 獲取過濾器當前的內部狀態，方便外部調試或在UI上顯示。
  Map<String, dynamic> getStatus() {
    return {
      '基準值': _targetBaseValue,
      '候選值': _takeoverCandidateValue,
      '候選連續次數': _takeoverConsecutiveCount,
      '計數統計': _value6Counts,
    };
  }
}
