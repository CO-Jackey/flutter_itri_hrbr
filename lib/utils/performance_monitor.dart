import 'package:flutter_itri_hrbr/helper/devLog.dart';

class PerformanceMonitor {
  static final PerformanceMonitor _instance = PerformanceMonitor._internal();
  factory PerformanceMonitor() => _instance;
  PerformanceMonitor._internal();
  
  final Map<String, _MetricData> _metrics = {};
  
  void logUpdate(String category) {
    final metric = _metrics.putIfAbsent(
      category, 
      () => _MetricData(),
    );
    
    metric.count++;
    final elapsed = DateTime.now().difference(metric.lastReset);
    
    if (elapsed > const Duration(seconds: 5)) {
      final rate = metric.count / elapsed.inSeconds;
      devLog(
        '效能監控', 
        '$category: ${rate.toStringAsFixed(1)} updates/sec (總計: ${metric.count})',
      );
      metric.count = 0;
      metric.lastReset = DateTime.now();
    }
  }
}

class _MetricData {
  int count = 0;
  DateTime lastReset = DateTime.now();
}