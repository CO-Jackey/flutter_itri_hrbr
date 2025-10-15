// lib/services/batch_data_processor.dart

import 'dart:isolate';
import 'dart:async';

import 'package:flutter_itri_hrbr/helper/devLog.dart';

/// 批次資料項
class BatchDataItem {
  final String deviceId;
  final List<int> bytes;
  final DateTime receivedTime;

  BatchDataItem({
    required this.deviceId,
    required this.bytes,
    required this.receivedTime,
  });

  /// 轉換為 Map（用於跨 Isolate 傳遞）
  Map<String, dynamic> toMap() {
    return {
      'deviceId': deviceId,
      'bytes': bytes,
      'receivedTime': receivedTime.millisecondsSinceEpoch,
    };
  }

  /// 從 Map 建立
  factory BatchDataItem.fromMap(Map<String, dynamic> map) {
    return BatchDataItem(
      deviceId: map['deviceId'] as String,
      bytes: List<int>.from(map['bytes'] as List),
      receivedTime: DateTime.fromMillisecondsSinceEpoch(
        map['receivedTime'] as int,
      ),
    );
  }
}

/// 批次資料處理器
///
/// 功能：
/// - 在背景 Isolate 累積藍牙資料
/// - 定時或達到批次大小時發送批次
/// - 提供統計資訊
class BatchDataProcessor {
  Isolate? _isolate;
  SendPort? _sendToIsolate;
  final ReceivePort _receiveFromIsolate = ReceivePort();

  // ✅ 使用 broadcast StreamController 解決多次訂閱問題
  late final StreamController<Map<String, List<BatchDataItem>>>
  _batchController;
  late final StreamController<Map<String, dynamic>> _statsController;

  bool _isInitialized = false;
  int _dataCount = 0;

  /// 建構子
  BatchDataProcessor() {
    // 初始化 broadcast controllers
    _batchController =
        StreamController<Map<String, List<BatchDataItem>>>.broadcast();
    _statsController = StreamController<Map<String, dynamic>>.broadcast();
  }

  /// 批次資料 Stream（可多次訂閱）
  Stream<Map<String, List<BatchDataItem>>> get batchStream =>
      _batchController.stream;

  /// 統計資訊 Stream（可多次訂閱）
  Stream<Map<String, dynamic>> get statsStream => _statsController.stream;

  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  /// 已接收的資料數量
  int get dataCount => _dataCount;

  /// 啟動批次處理 Isolate
  ///
  /// [batchInterval] - 批次發送間隔（預設 100ms）
  /// [batchSize] - 批次大小，達到此數量立即發送（預設 10 筆）
  Future<void> start({
    Duration batchInterval = const Duration(milliseconds: 100),
    int batchSize = 10,
  }) async {
    if (_isInitialized) {
      devLog('start','⚠️  [BatchProcessor] 已經啟動，跳過重複初始化');
      return;
    }

    devLog('start','🚀 [BatchProcessor] 啟動批次處理 Isolate...');
    devLog('start','   - 批次間隔: ${batchInterval.inMilliseconds}ms');
    devLog('start','   - 批次大小: $batchSize 筆');

    try {
      // 建立 Isolate
      _isolate = await Isolate.spawn(
        _isolateEntry,
        _IsolateConfig(
          sendToMain: _receiveFromIsolate.sendPort,
          batchInterval: batchInterval,
          batchSize: batchSize,
        ),
        debugName: 'BatchDataProcessor',
      );

      // ✅ 監聽來自 Isolate 的訊息，並轉發到 broadcast Stream
      _receiveFromIsolate.listen(
        (message) {
          _handleIsolateMessage(message);
        },
        onError: (error) {
          devLog('start','❌ [BatchProcessor] ReceivePort 錯誤: $error');
        },
        onDone: () {
          devLog('start','⚠️  [BatchProcessor] ReceivePort 已關閉');
        },
      );

      // 等待 Isolate 初始化完成（最多等待 5 秒）
      int retries = 0;
      while (!_isInitialized && retries < 50) {
        await Future.delayed(Duration(milliseconds: 100));
        retries++;
      }

      if (!_isInitialized) {
        throw TimeoutException('批次處理器初始化超時');
      }

      devLog('start','✅ [BatchProcessor] 批次處理 Isolate 已啟動');
    } catch (e, stackTrace) {
      devLog('start','❌ [BatchProcessor] 啟動失敗: $e');
      devLog('start','   堆疊追蹤: $stackTrace');

      // 清理失敗的初始化
      await dispose();

      rethrow;
    }
  }

  /// 處理來自 Isolate 的訊息
  void _handleIsolateMessage(dynamic message) {
    if (message is SendPort) {
      // Isolate 初始化完成，傳回 SendPort
      _sendToIsolate = message;
      _isInitialized = true;
    } else if (message is Map) {
      final type = message['type'] as String?;

      switch (type) {
        case 'batch':
          // 批次資料
          _handleBatchData(message['data'] as Map);
          break;

        case 'stats':
          // 統計資訊
          _handleStatsData(message['data'] as Map<String, dynamic>);
          break;

        case 'error':
          // 錯誤訊息
          devLog('_handleIsolateMessage','❌ [BatchProcessor Isolate] ${message['message']}');
          break;

        default:
          devLog('_handleIsolateMessage','⚠️  [BatchProcessor] 未知的訊息類型: $type');
      }
    }
  }

  /// 處理批次資料
  void _handleBatchData(Map batchMap) {
    try {
      final result = <String, List<BatchDataItem>>{};

      batchMap.forEach((deviceId, items) {
        result[deviceId as String] = (items as List)
            .map((item) => BatchDataItem.fromMap(item as Map<String, dynamic>))
            .toList();
      });

      // 轉發到 broadcast stream
      _batchController.add(result);
    } catch (e) {
      devLog('_handleBatchData','❌ [BatchProcessor] 處理批次資料錯誤: $e');
    }
  }

  /// 處理統計資訊
  void _handleStatsData(Map<String, dynamic> stats) {
    try {
      // 轉發到 broadcast stream
      _statsController.add(stats);
    } catch (e) {
      devLog('_handleStatsData','❌ [BatchProcessor] 處理統計資訊錯誤: $e');
    }
  }

  /// Isolate 進入點
  static void _isolateEntry(_IsolateConfig config) {
    devLog('_isolateEntry','📱 [BatchProcessor Isolate] 開始運行');

    final receiveInIsolate = ReceivePort();

    // 傳送 SendPort 給主執行緒
    config.sendToMain.send(receiveInIsolate.sendPort);

    // 批次緩衝區：deviceId -> List<BatchDataItem>
    final Map<String, List<Map<String, dynamic>>> batches = {};

    // 統計資訊
    int totalReceived = 0;
    int totalSent = 0;
    int totalBatches = 0;
    DateTime lastStatsTime = DateTime.now();

    // ✅ 定時器：定期發送批次
    Timer.periodic(config.batchInterval, (timer) {
      if (batches.isNotEmpty) {
        // 計算這批的總數
        final batchCount = batches.values.fold(
          0,
          (sum, list) => sum + list.length,
        );

        // 發送批次給主執行緒
        config.sendToMain.send({
          'type': 'batch',
          'data': Map<String, dynamic>.from(batches),
        });

        totalSent += batchCount;
        totalBatches++;

        // 清空緩衝區
        batches.clear();
      }

      // 每 5 秒發送統計資訊
      final now = DateTime.now();
      if (now.difference(lastStatsTime).inSeconds >= 5) {
        config.sendToMain.send({
          'type': 'stats',
          'data': {
            'totalReceived': totalReceived,
            'totalSent': totalSent,
            'totalBatches': totalBatches,
            'buffered': batches.values.fold(
              0,
              (sum, list) => sum + list.length,
            ),
            'devices': batches.keys.length,
            'avgBatchSize': totalBatches > 0
                ? (totalSent / totalBatches).toStringAsFixed(1)
                : '0',
          },
        });
        lastStatsTime = now;
      }
    });

    // ✅ 監聽來自主執行緒的指令
    receiveInIsolate.listen((message) {
      if (message is Map) {
        final type = message['type'] as String?;

        switch (type) {
          case 'data':
            // 收到新資料
            try {
              final item = BatchDataItem.fromMap(
                message['data'] as Map<String, dynamic>,
              );

              totalReceived++;

              // 加入批次緩衝區
              batches.putIfAbsent(item.deviceId, () => []).add(item.toMap());

              // ✅ 如果某個設備累積達到批次大小，立即發送
              if (batches[item.deviceId]!.length >= config.batchSize) {
                final deviceBatch = {item.deviceId: batches[item.deviceId]};
                final batchCount = batches[item.deviceId]!.length;

                config.sendToMain.send({
                  'type': 'batch',
                  'data': deviceBatch,
                });

                totalSent += batchCount;
                totalBatches++;
                batches.remove(item.deviceId);
              }
            } catch (e) {
              config.sendToMain.send({
                'type': 'error',
                'message': '處理資料錯誤: $e',
              });
            }
            break;

          case 'command':
            // 處理指令
            final command = message['command'] as String?;

            if (command == 'flush') {
              // 強制清空緩衝區
              if (batches.isNotEmpty) {
                final batchCount = batches.values.fold(
                  0,
                  (sum, list) => sum + list.length,
                );

                config.sendToMain.send({
                  'type': 'batch',
                  'data': Map<String, dynamic>.from(batches),
                });

                totalSent += batchCount;
                totalBatches++;
                batches.clear();
              }
            } else if (command == 'stats') {
              // 立即發送統計資訊
              config.sendToMain.send({
                'type': 'stats',
                'data': {
                  'totalReceived': totalReceived,
                  'totalSent': totalSent,
                  'totalBatches': totalBatches,
                  'buffered': batches.values.fold(
                    0,
                    (sum, list) => sum + list.length,
                  ),
                  'devices': batches.keys.length,
                  'avgBatchSize': totalBatches > 0
                      ? (totalSent / totalBatches).toStringAsFixed(1)
                      : '0',
                },
              });
            }
            break;

          default:
            config.sendToMain.send({
              'type': 'error',
              'message': '未知的訊息類型: $type',
            });
        }
      }
    });

    devLog('_handleStatsData','✅ [BatchProcessor Isolate] 準備完成，等待資料...');
  }

  /// 發送資料給 Isolate 處理
  ///
  /// [deviceId] - 設備 ID
  /// [bytes] - 原始資料 bytes
  void addData(String deviceId, List<int> bytes) {
    if (!_isInitialized) {
      devLog('addData','⚠️  [BatchProcessor] 尚未初始化，資料已忽略');
      return;
    }

    if (bytes.isEmpty) {
      devLog('addData','⚠️  [BatchProcessor] 收到空資料，已忽略');
      return;
    }

    _dataCount++;

    _sendToIsolate?.send({
      'type': 'data',
      'data': BatchDataItem(
        deviceId: deviceId,
        bytes: bytes,
        receivedTime: DateTime.now(),
      ).toMap(),
    });
  }

  /// 強制清空緩衝區（立即發送所有累積的資料）
  ///
  /// 使用場景：
  /// - 設備即將斷線
  /// - 需要立即處理所有資料
  void flush() {
    if (!_isInitialized) {
      devLog('flush','⚠️  [BatchProcessor] 尚未初始化，無法 flush');
      return;
    }

    _sendToIsolate?.send({
      'type': 'command',
      'command': 'flush',
    });

    devLog('flush','🔄 [BatchProcessor] 已發送 flush 指令');
  }

  /// 請求立即發送統計資訊
  void requestStats() {
    if (!_isInitialized) {
      devLog('requestStats','⚠️  [BatchProcessor] 尚未初始化，無法請求統計');
      return;
    }

    _sendToIsolate?.send({
      'type': 'command',
      'command': 'stats',
    });
  }

  /// 釋放資源
  Future<void> dispose() async {
    devLog('dispose','🛑 [BatchProcessor] 停止批次處理 Isolate');

    try {
      // 關閉 Isolate
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;

      // 關閉 ReceivePort
      _receiveFromIsolate.close();

      // 關閉 StreamControllers
      await _batchController.close();
      await _statsController.close();

      // 重置狀態
      _sendToIsolate = null;
      _isInitialized = false;
      _dataCount = 0;

      devLog('dispose','✅ [BatchProcessor] 已清理所有資源');
    } catch (e) {
      devLog('dispose','⚠️  [BatchProcessor] 清理時發生錯誤: $e');
    }
  }
}

/// Isolate 配置
class _IsolateConfig {
  final SendPort sendToMain;
  final Duration batchInterval;
  final int batchSize;

  _IsolateConfig({
    required this.sendToMain,
    required this.batchInterval,
    required this.batchSize,
  });
}
