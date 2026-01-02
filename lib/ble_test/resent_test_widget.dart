import 'package:flutter/material.dart';
import 'package:flutter_itri_hrbr/ble_test/resent_test_service.dart';

/// 補傳測試 UI 元件
/// 可獨立使用於任何需要測試補傳功能的頁面
class ReSentTestWidget extends StatefulWidget {
  /// 測試服務實例
  final ReSentTestService testService;

  /// 是否已連線（用於控制按鈕狀態）
  final bool isConnected;

  /// 斷線回調
  final Future<void> Function() onDisconnect;

  /// 重連回調
  final Future<bool> Function() onReconnect;

  /// ⭐ 取消訂閱回調（補傳結束時呼叫）
  final Future<void> Function()? onUnsubscribe;
  
  /// ⭐ 時間戳追蹤（用於除錯）
  final DateTime? lastDisconnectTime;
  final DateTime? lastConnectTime;
  final DateTime? lastTimeSyncWriteTime;

  const ReSentTestWidget({
    super.key,
    required this.testService,
    required this.isConnected,
    required this.onDisconnect,
    required this.onReconnect,
    this.onUnsubscribe,
    this.lastDisconnectTime,
    this.lastConnectTime,
    this.lastTimeSyncWriteTime,
  });

  @override
  State<ReSentTestWidget> createState() => _ReSentTestWidgetState();
}

class _ReSentTestWidgetState extends State<ReSentTestWidget> {
  final TextEditingController _testDurationController = TextEditingController(
    text: '10',
  );

  bool _isTestRunning = false;
  int _remainingSeconds = 0;
  bool _isWaitingForReSent = false; // ⭐ 等待補傳結束狀態

  @override
  void initState() {
    super.initState();

    // 設定回調
    widget.testService.onStateChanged = (isRunning, remaining) {
      if (mounted) {
        setState(() {
          _isTestRunning = isRunning;
          _remainingSeconds = remaining;
          _isWaitingForReSent = widget.testService.isWaitingForReSentComplete;
        });
      }
    };

    // ⭐ 設定補傳結束回調
    widget.testService.onReSentComplete = () async {
      if (mounted) {
        // 自動取消訂閱
        if (widget.onUnsubscribe != null) {
          await widget.onUnsubscribe!();
        }
        setState(() {
          _isWaitingForReSent = false;
        });
        // 顯示完成提示
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 補傳資料傳輸完畢，已自動取消訂閱'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    };
  }

  @override
  void dispose() {
    _testDurationController.dispose();
    widget.testService.onStateChanged = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.testService.getRealtimeStats();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 標題
            const Row(
              children: [
                Icon(Icons.science, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  '🧪 補傳測試',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // ⭐ 時間戳追蹤顯示
            _buildTimeTrackingInfo(),
            
            const SizedBox(height: 16),

            // 定時斷線設定
            Row(
              children: [
                const Text('斷線時間：'),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _testDurationController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(),
                    ),
                    enabled: !_isTestRunning && !_isWaitingForReSent,
                  ),
                ),
                const SizedBox(width: 8),
                const Text('秒'),
                const Spacer(),
                if (_isTestRunning)
                  ElevatedButton(
                    onPressed: () {
                      widget.testService.cancelTimedTest();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                    ),
                    child: Text('取消 ($_remainingSeconds s)'),
                  )
                else if (_isWaitingForReSent)
                  // ⭐ 等待補傳結束狀態
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.orange,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Text('等待補傳...', style: TextStyle(color: Colors.orange)),
                      ],
                    ),
                  )
                else
                  ElevatedButton(
                    onPressed: widget.isConnected
                        ? () async {
                            final duration = int.parse(
                              _testDurationController.text,
                            );
                            await widget.testService.startTimedDisconnectTest(
                              durationSeconds: duration,
                              disconnectCallback: widget.onDisconnect,
                              reconnectCallback: widget.onReconnect,
                            );
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                    ),
                    child: const Text('開始測試'),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // 即時統計
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📊 即時統計',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(
                        '補傳',
                        stats['reSentCount'] ?? 0,
                        Colors.orange,
                      ),
                      _buildStatItem(
                        '即時',
                        stats['realtimeCount'] ?? 0,
                        Colors.green,
                      ),
                      _buildStatItem(
                        '總計',
                        stats['totalCount'] ?? 0,
                        Colors.blue,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 操作按鈕
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    widget.testService.clearTestRecords();
                    setState(() {});
                  },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('清空記錄'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _showTestReport(context),
                  icon: const Icon(Icons.assessment, size: 18),
                  label: const Text('產生報告'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, int value, Color color) {
    return Column(
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(color: Colors.grey[600])),
      ],
    );
  }

  void _showTestReport(BuildContext context) {
    final report = widget.testService.generateTestReport();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.assessment, color: Colors.blue),
            SizedBox(width: 8),
            Text('測試報告'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: DefaultTabController(
            length: 4,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const TabBar(
                  labelColor: Colors.blue,
                  unselectedLabelColor: Colors.grey,
                  isScrollable: true,
                  tabs: [
                    Tab(text: '摘要'),
                    Tab(text: '補傳詳細'),
                    Tab(text: '即時詳細'),
                    Tab(text: '全部資料'),
                  ],
                ),
                SizedBox(
                  height: 400,
                  child: TabBarView(
                    children: [
                      // 摘要
                      _buildReportTab(report.toFormattedString()),
                      // 補傳詳細
                      _buildReportTab(report.getReSentDetailString()),
                      // 即時詳細
                      _buildReportTab(report.getRealtimeDetailString()),
                      // 全部資料
                      _buildReportTab(report.getAllDataDetailString()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              widget.testService.getTestReportString();
              // 複製到剪貼簿（摘要+補傳詳細）
              final fullReport =
                  '${report.toFormattedString()}\n\n${report.getReSentDetailString()}';
              // Clipboard.setData(ClipboardData(text: fullReport));
              // 這裡可以用 Clipboard 但需要 import，先用 print
              print(fullReport);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('報告已輸出到 Console')),
              );
            },
            child: const Text('輸出到 Console'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }

  Widget _buildReportTab(String content) {
    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: SelectableText(
          content,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
          ),
        ),
      ),
    );
  }
  
  /// 格式化時間
  String _formatTime(DateTime? dt) {
    if (dt == null) return "---";
    return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}.${dt.millisecond.toString().padLeft(3, '0')}";
  }
  
  /// 時間戳追蹤顯示
  Widget _buildTimeTrackingInfo() {
    final now = DateTime.now();
    
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '⏰ 本地時間：${_formatTime(now)}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            '🔌 上次斷線：${_formatTime(widget.lastDisconnectTime)}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          Text(
            '🔗 這次連線：${_formatTime(widget.lastConnectTime)}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          Text(
            '📝 時間戳寫入：${_formatTime(widget.lastTimeSyncWriteTime)}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
    );
  }
}
