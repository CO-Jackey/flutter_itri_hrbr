import 'dart:async';
import 'package:flutter_itri_hrbr/helper/devLog.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 測試資料記錄類別
// ═══════════════════════════════════════════════════════════════════════════

/// 單筆資料記錄
class TestDataRecord {
  final bool isReSent;              // 是否為補傳資料 (0xFA)
  final DateTime deviceTime;        // 裝置時間戳（從 data[1]~[5] 解析）
  final DateTime appReceivedTime;   // App 收到時間
  final int delayMs;                // 延遲毫秒
  final List<int> rawData;          // 原始資料

  TestDataRecord({
    required this.isReSent,
    required this.deviceTime,
    required this.appReceivedTime,
    required this.delayMs,
    required this.rawData,
  });
  
  @override
  String toString() {
    return 'TestDataRecord(isReSent: $isReSent, deviceTime: $deviceTime, appReceivedTime: $appReceivedTime, delayMs: $delayMs)';
  }
}

/// 測試報告
class TestReport {
  final DateTime? disconnectTime;
  final DateTime? reconnectTime;
  final int disconnectDurationSeconds;
  
  final int reSentCount;
  final int realtimeCount;
  final DateTime? reSentFirstTimestamp;
  final DateTime? reSentLastTimestamp;
  
  final double reSentAvgDelayMs;
  final double realtimeAvgDelayMs;
  final int realtimeMaxDelayMs;
  
  final int expectedReSentCount;
  final double completionRate;
  final List<String> timestampGaps;
  
  // 詳細資料
  final List<TestDataRecord> allReSentRecords;
  final List<TestDataRecord> allRealtimeRecords;

  TestReport({
    this.disconnectTime,
    this.reconnectTime,
    this.disconnectDurationSeconds = 0,
    this.reSentCount = 0,
    this.realtimeCount = 0,
    this.reSentFirstTimestamp,
    this.reSentLastTimestamp,
    this.reSentAvgDelayMs = 0,
    this.realtimeAvgDelayMs = 0,
    this.realtimeMaxDelayMs = 0,
    this.expectedReSentCount = 0,
    this.completionRate = 0,
    this.timestampGaps = const [],
    this.allReSentRecords = const [],
    this.allRealtimeRecords = const [],
  });
  
  /// 格式化時間為易讀格式
  String _formatTime(DateTime? dt) {
    if (dt == null) return "N/A";
    return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}.${dt.millisecond.toString().padLeft(3, '0')}";
  }
  
  /// 格式化完整日期時間
  String _formatDateTime(DateTime? dt) {
    if (dt == null) return "N/A";
    return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${_formatTime(dt)}";
  }
  
  String toFormattedString() {
    final buffer = StringBuffer();
    buffer.writeln('========== 測試報告 ==========');
    buffer.writeln('斷線時間：${_formatDateTime(disconnectTime)}');
    buffer.writeln('重連時間：${_formatDateTime(reconnectTime)}');
    buffer.writeln('斷線時長：$disconnectDurationSeconds 秒');
    buffer.writeln('');
    buffer.writeln('--- 補傳資料統計 ---');
    buffer.writeln('補傳筆數：$reSentCount 筆');
    buffer.writeln('補傳時間範圍：${_formatTime(reSentFirstTimestamp)} ~ ${_formatTime(reSentLastTimestamp)}');
    buffer.writeln('預期筆數：$expectedReSentCount 筆');
    buffer.writeln('完整率：${completionRate.toStringAsFixed(1)}%');
    buffer.writeln('');
    buffer.writeln('--- 即時資料統計 ---');
    buffer.writeln('即時筆數：$realtimeCount 筆');
    buffer.writeln('補傳平均延遲：${reSentAvgDelayMs.toStringAsFixed(1)} ms');
    buffer.writeln('即時平均延遲：${realtimeAvgDelayMs.toStringAsFixed(1)} ms');
    buffer.writeln('即時最大延遲：$realtimeMaxDelayMs ms');
    buffer.writeln('');
    buffer.writeln('--- 時間戳缺口分析 ---');
    buffer.writeln('缺口數量：${timestampGaps.length}');
    if (timestampGaps.isNotEmpty) {
      buffer.writeln('缺口位置：');
      for (var gap in timestampGaps.take(10)) {
        buffer.writeln('  - $gap');
      }
      if (timestampGaps.length > 10) {
        buffer.writeln('  ... 還有 ${timestampGaps.length - 10} 個缺口');
      }
    }
    buffer.writeln('================================');
    return buffer.toString();
  }
  
  /// 取得補傳資料詳細列表字串
  String getReSentDetailString() {
    if (allReSentRecords.isEmpty) return "無補傳資料";
    
    final buffer = StringBuffer();
    buffer.writeln('======= 補傳資料詳細列表 (共 ${allReSentRecords.length} 筆) =======');
    buffer.writeln('格式：[序號] 裝置時間 | App收到時間 | 延遲(ms)');
    buffer.writeln('');
    
    for (int i = 0; i < allReSentRecords.length; i++) {
      final r = allReSentRecords[i];
      buffer.writeln('[${(i + 1).toString().padLeft(4)}] ${_formatTime(r.deviceTime)} | ${_formatTime(r.appReceivedTime)} | ${r.delayMs.toString().padLeft(6)} ms');
    }
    
    buffer.writeln('');
    buffer.writeln('================================================');
    return buffer.toString();
  }
  
  /// 取得即時資料詳細列表字串
  String getRealtimeDetailString() {
    if (allRealtimeRecords.isEmpty) return "無即時資料";
    
    final buffer = StringBuffer();
    buffer.writeln('======= 即時資料詳細列表 (共 ${allRealtimeRecords.length} 筆) =======');
    buffer.writeln('格式：[序號] 裝置時間 | App收到時間 | 延遲(ms)');
    buffer.writeln('');
    
    for (int i = 0; i < allRealtimeRecords.length; i++) {
      final r = allRealtimeRecords[i];
      buffer.writeln('[${(i + 1).toString().padLeft(4)}] ${_formatTime(r.deviceTime)} | ${_formatTime(r.appReceivedTime)} | ${r.delayMs.toString().padLeft(6)} ms');
    }
    
    buffer.writeln('');
    buffer.writeln('================================================');
    return buffer.toString();
  }
  
  /// 取得所有資料（按 App 收到時間排序）的詳細列表
  String getAllDataDetailString() {
    final allRecords = [...allReSentRecords, ...allRealtimeRecords];
    if (allRecords.isEmpty) return "無資料";
    
    // 按 App 收到時間排序
    allRecords.sort((a, b) => a.appReceivedTime.compareTo(b.appReceivedTime));
    
    final buffer = StringBuffer();
    buffer.writeln('======= 所有資料（按收到時間排序）(共 ${allRecords.length} 筆) =======');
    buffer.writeln('格式：[序號] 類型 | 裝置時間 | App收到時間 | 延遲(ms)');
    buffer.writeln('');
    
    for (int i = 0; i < allRecords.length; i++) {
      final r = allRecords[i];
      final type = r.isReSent ? '🔄補傳' : '✅即時';
      buffer.writeln('[${(i + 1).toString().padLeft(4)}] $type | ${_formatTime(r.deviceTime)} | ${_formatTime(r.appReceivedTime)} | ${r.delayMs.toString().padLeft(6)} ms');
    }
    
    buffer.writeln('');
    buffer.writeln('================================================');
    return buffer.toString();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 補傳測試服務
// ═══════════════════════════════════════════════════════════════════════════

/// 補傳測試服務
/// 提供資料補傳測試的核心功能
class ReSentTestService {
  // 測試相關變數
  DateTime? _disconnectTime;
  DateTime? _reconnectTime;
  DateTime? _lastTimestampBeforeDisconnect;
  final List<TestDataRecord> _testRecords = [];
  Timer? _timedTestTimer;
  
  // 狀態
  bool _isTimedTestRunning = false;
  int _timedTestRemainingSeconds = 0;
  
  // ⭐ 補傳結束偵測
  bool _isWaitingForReSentComplete = false;  // 是否正在等待補傳結束
  int _consecutiveRealtimeCount = 0;         // 連續即時資料計數
  static const int _reSentCompleteThreshold = 10; // 連續收到幾筆即時資料視為補傳結束
  
  // 回調
  Function(int remainingSeconds)? onCountdownTick;
  Function()? onTestComplete;
  Function(bool isRunning, int remaining)? onStateChanged;
  Function()? onReSentComplete;  // ⭐ 補傳結束回調
  
  // Getters
  bool get isTimedTestRunning => _isTimedTestRunning;
  int get timedTestRemainingSeconds => _timedTestRemainingSeconds;
  DateTime? get disconnectTime => _disconnectTime;
  DateTime? get reconnectTime => _reconnectTime;
  bool get isWaitingForReSentComplete => _isWaitingForReSentComplete;
  
  /// 從原始資料解析裝置時間戳
  /// data[1]~[5] 為時間戳，單位為 10ms
  /// 注意：寫入時已加上時區偏移，所以回傳的是「本地時間的毫秒數」
  DateTime parseDeviceTimestamp(List<int> data) {
    if (data.length < 6) {
      return DateTime.now();
    }
    
    // 還原時間戳（參考廠商 sendTimestamp1 和 sendTimestamp2 的反向操作）
    int timestamp = data[1]              // TS1 (第 0-7 位)
                  + (data[2] << 8)       // TS2 (第 8-15 位)
                  + (data[3] << 16)      // TS3 (第 16-23 位)
                  + (data[4] << 24)      // TS4 (第 24-31 位)
                  + (data[5] << 32);     // TS5 (第 32-39 位)
    
    // timestamp 是 10ms 單位，轉回毫秒
    int milliseconds = timestamp * 10;
    
    // ✅ 修正：寫入時已加時區偏移，所以這裡要減掉才能正確比較
    // 因為 DateTime.fromMillisecondsSinceEpoch 預設把毫秒當 UTC 解析
    final now = DateTime.now();
    milliseconds -= now.timeZoneOffset.inMilliseconds;
    
    // 轉成 DateTime（本地時間）
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  /// 判斷資料是否為補傳資料
  bool isReSentData(List<int> data) {
    if (data.isEmpty) return false;
    return data[0] == 0xFA; // 250 = 補傳資料
  }

  /// 記錄測試資料
  /// 回傳 true 表示補傳已結束（連續收到即時資料達到門檻）
  bool recordTestData(List<int> data) {
    if (data.length < 6) return false;
    
    final appReceivedTime = DateTime.now();
    final deviceTime = parseDeviceTimestamp(data);
    final isReSent = isReSentData(data);
    final delayMs = appReceivedTime.difference(deviceTime).inMilliseconds;
    
    final record = TestDataRecord(
      isReSent: isReSent,
      deviceTime: deviceTime,
      appReceivedTime: appReceivedTime,
      delayMs: delayMs,
      rawData: List.from(data),
    );
    
    _testRecords.add(record);
    
    // 更新斷線前最後時間戳（僅記錄即時資料）
    if (!isReSent) {
      _lastTimestampBeforeDisconnect = deviceTime;
    }
    
    devLog('測試記錄', '${isReSent ? "🔄補傳" : "✅即時"} 裝置時間: $deviceTime, 延遲: ${delayMs}ms');
    
    // ⭐ 補傳結束偵測
    if (_isWaitingForReSentComplete) {
      if (isReSent) {
        // 收到補傳資料，重置計數
        _consecutiveRealtimeCount = 0;
      } else {
        // 收到即時資料
        _consecutiveRealtimeCount++;
        devLog('測試', '連續即時資料: $_consecutiveRealtimeCount / $_reSentCompleteThreshold');
        
        if (_consecutiveRealtimeCount >= _reSentCompleteThreshold) {
          // 補傳結束！
          devLog('測試', '🎉 補傳資料傳輸完畢！');
          _isWaitingForReSentComplete = false;
          _consecutiveRealtimeCount = 0;
          onReSentComplete?.call();
          return true; // 回傳 true 表示補傳結束
        }
      }
    }
    
    return false;
  }

  /// 開始定時斷線測試
  /// [durationSeconds] 斷線時長（秒）
  /// [disconnectCallback] 斷線回調
  /// [reconnectCallback] 重連回調
  Future<void> startTimedDisconnectTest({
    required int durationSeconds,
    required Future<void> Function() disconnectCallback,
    required Future<bool> Function() reconnectCallback,
  }) async {
    // 清空上次測試記錄
    clearTestRecords();
    
    devLog('測試', '🧪 開始定時斷線測試，時長: $durationSeconds 秒');
    
    // 記錄斷線時間
    _disconnectTime = DateTime.now();
    
    // 更新狀態
    _isTimedTestRunning = true;
    _timedTestRemainingSeconds = durationSeconds;
    onStateChanged?.call(_isTimedTestRunning, _timedTestRemainingSeconds);
    
    // 執行斷線
    await disconnectCallback();
    
    // 開始倒數計時
    int remaining = durationSeconds;
    _timedTestTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      remaining--;
      _timedTestRemainingSeconds = remaining;
      onCountdownTick?.call(remaining);
      onStateChanged?.call(_isTimedTestRunning, _timedTestRemainingSeconds);
      
      devLog('測試', '⏱️ 剩餘 $remaining 秒');
      
      if (remaining <= 0) {
        timer.cancel();
        _timedTestTimer = null;
        
        // 記錄重連時間
        _reconnectTime = DateTime.now();
        
        devLog('測試', '🔌 時間到，開始重連...');
        
        // ⭐ 啟動補傳結束偵測
        _isWaitingForReSentComplete = true;
        _consecutiveRealtimeCount = 0;
        
        // 重新連線
        final success = await reconnectCallback();
        if (success) {
          devLog('測試', '✅ 重連成功，等待補傳資料結束...');
        } else {
          devLog('測試', '❌ 重連失敗');
          _isWaitingForReSentComplete = false;
        }
        
        _isTimedTestRunning = false;
        onStateChanged?.call(_isTimedTestRunning, _timedTestRemainingSeconds);
        // ⭐ 不在這裡呼叫 onTestComplete，等補傳結束再呼叫
      }
    });
  }

  /// 取消定時測試
  void cancelTimedTest() {
    _timedTestTimer?.cancel();
    _timedTestTimer = null;
    _isTimedTestRunning = false;
    _timedTestRemainingSeconds = 0;
    _isWaitingForReSentComplete = false;
    _consecutiveRealtimeCount = 0;
    onStateChanged?.call(_isTimedTestRunning, _timedTestRemainingSeconds);
    devLog('測試', '❌ 定時測試已取消');
  }

  /// 清空測試記錄
  void clearTestRecords() {
    _testRecords.clear();
    _disconnectTime = null;
    _reconnectTime = null;
    _lastTimestampBeforeDisconnect = null;
    _isWaitingForReSentComplete = false;
    _consecutiveRealtimeCount = 0;
    devLog('測試', '🗑️ 測試記錄已清空');
  }

  /// 取得即時統計
  Map<String, int> getRealtimeStats() {
    final reSentCount = _testRecords.where((r) => r.isReSent).length;
    final realtimeCount = _testRecords.where((r) => !r.isReSent).length;
    return {
      'reSentCount': reSentCount,
      'realtimeCount': realtimeCount,
      'totalCount': _testRecords.length,
    };
  }

  /// 產生測試報告
  TestReport generateTestReport() {
    final reSentRecords = _testRecords.where((r) => r.isReSent).toList();
    final realtimeRecords = _testRecords.where((r) => !r.isReSent).toList();
    
    // 計算斷線時長
    int disconnectDuration = 0;
    if (_disconnectTime != null && _reconnectTime != null) {
      disconnectDuration = _reconnectTime!.difference(_disconnectTime!).inSeconds;
    }
    
    // 補傳時間範圍（按裝置時間排序）
    DateTime? reSentFirst;
    DateTime? reSentLast;
    final sortedReSent = List<TestDataRecord>.from(reSentRecords);
    if (sortedReSent.isNotEmpty) {
      sortedReSent.sort((a, b) => a.deviceTime.compareTo(b.deviceTime));
      reSentFirst = sortedReSent.first.deviceTime;
      reSentLast = sortedReSent.last.deviceTime;
    }
    
    // 計算延遲
    double reSentAvgDelay = 0;
    if (reSentRecords.isNotEmpty) {
      reSentAvgDelay = reSentRecords.map((r) => r.delayMs).reduce((a, b) => a + b) / reSentRecords.length;
    }
    
    double realtimeAvgDelay = 0;
    int realtimeMaxDelay = 0;
    if (realtimeRecords.isNotEmpty) {
      realtimeAvgDelay = realtimeRecords.map((r) => r.delayMs).reduce((a, b) => a + b) / realtimeRecords.length;
      realtimeMaxDelay = realtimeRecords.map((r) => r.delayMs).reduce((a, b) => a > b ? a : b);
    }
    
    // 預期補傳筆數（1秒32筆）
    int expectedReSent = disconnectDuration * 32;
    
    // 完整率
    double completionRate = 0;
    if (expectedReSent > 0) {
      completionRate = (reSentRecords.length / expectedReSent) * 100;
      if (completionRate > 100) completionRate = 100;
    }
    
    // 分析時間戳缺口
    List<String> gaps = _analyzeTimestampGaps(sortedReSent);
    
    return TestReport(
      disconnectTime: _disconnectTime,
      reconnectTime: _reconnectTime,
      disconnectDurationSeconds: disconnectDuration,
      reSentCount: reSentRecords.length,
      realtimeCount: realtimeRecords.length,
      reSentFirstTimestamp: reSentFirst,
      reSentLastTimestamp: reSentLast,
      reSentAvgDelayMs: reSentAvgDelay,
      realtimeAvgDelayMs: realtimeAvgDelay,
      realtimeMaxDelayMs: realtimeMaxDelay,
      expectedReSentCount: expectedReSent,
      completionRate: completionRate,
      timestampGaps: gaps,
      allReSentRecords: sortedReSent,
      allRealtimeRecords: realtimeRecords,
    );
  }

  /// 分析時間戳缺口
  List<String> _analyzeTimestampGaps(List<TestDataRecord> records) {
    if (records.length < 2) return [];
    
    List<String> gaps = [];
    const expectedIntervalMs = 31; // 約 31.25ms (1秒/32筆)
    const toleranceMs = 15; // 容許誤差
    
    for (int i = 1; i < records.length; i++) {
      final prev = records[i - 1];
      final curr = records[i];
      final interval = curr.deviceTime.difference(prev.deviceTime).inMilliseconds;
      
      if (interval > expectedIntervalMs + toleranceMs) {
        // 計算缺了幾筆
        final missedCount = (interval / expectedIntervalMs).round() - 1;
        if (missedCount > 0) {
          gaps.add('第 $i 筆前缺 $missedCount 筆 (間隔 ${interval}ms)');
        }
      }
    }
    
    return gaps;
  }

  /// 取得測試報告字串
  String getTestReportString() {
    // devLog('測試報告', generateTestReport().toFormattedString());
    return generateTestReport().toFormattedString();
  }
  
  /// 釋放資源
  void dispose() {
    _timedTestTimer?.cancel();
    _timedTestTimer = null;
  }
}
