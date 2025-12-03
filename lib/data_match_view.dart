import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_itri_hrbr/provider/health_provider.dart';
import 'package:flutter_itri_hrbr/services/data_match_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DataMatchViewPage extends ConsumerStatefulWidget {
  const DataMatchViewPage({super.key});

  @override
  ConsumerState<DataMatchViewPage> createState() => _DataMatchViewPageState();
}

class _DataMatchViewPageState extends ConsumerState<DataMatchViewPage> {
  // 掃描訂閱（跟原本 data_match_page 一樣）
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;

  // 新增一個狀態來追蹤重連中
  bool _isReconnecting = false;

  // ✅ 新增：按鈕冷卻狀態
  bool _isButtonCooldown = false;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    ref.read(dataMatchServiceProvider.notifier).requestPermissions();
  }

  @override
  void dispose() {
    _scanResultsSubscription?.cancel();
    ref.read(dataMatchServiceProvider.notifier).cleanup();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ✅ 新增：帶冷卻的操作執行器
  // ═══════════════════════════════════════════════════════════════════════════

  Future<T?> _executeWithCooldown<T>(
    Future<T> Function() action, {
    int cooldownSeconds = 3,
  }) async {
    if (_isButtonCooldown) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('操作過於頻繁，請稍候再試'),
          duration: Duration(seconds: 2),
        ),
      );
      return null;
    }

    setState(() => _isButtonCooldown = true);

    try {
      return await action();
    } finally {
      _cooldownTimer?.cancel();
      _cooldownTimer = Timer(Duration(seconds: cooldownSeconds), () {
        if (mounted) {
          setState(() => _isButtonCooldown = false);
        }
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 掃描 Dialog（跟原本 data_match_page.dart 完全一樣）
  // ═══════════════════════════════════════════════════════════════════════════

  void _toggleScan(BuildContext context) async {
    final service = ref.read(dataMatchServiceProvider.notifier);

    // ✅ 使用新的準備方法，確保乾淨狀態
    await service.prepareForScan();

    // 權限檢查
    bool permissionsGranted = await service.requestPermissions();
    if (!permissionsGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要藍牙和位置權限才能掃描')),
        );
      }
      return;
    }

    final btOn = await service.checkBluetoothEnabled();
    if (!btOn) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('請開啟藍牙'),
            content: const Text('藍牙未開啟或不可用'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('關閉'),
              ),
            ],
          ),
        );
      }
      return;
    }

    // ✅ 跟原本 data_match_page.dart 一樣的邏輯
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        List<ScanResult> dialogScanResults = [];
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            // ✅ 只在第一次建立時訂閱
            if (_scanResultsSubscription == null) {
              dialogScanResults = [];
              _scanResultsSubscription = FlutterBluePlus.scanResults.listen((
                results,
              ) {
                dialogSetState(() {
                  dialogScanResults = results
                      .where((r) => r.device.platformName.isNotEmpty)
                      .toList();
                });
              });
              FlutterBluePlus.cancelWhenScanComplete(_scanResultsSubscription!);
              FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
            }

            return AlertDialog(
              title: const Text('正在掃描藍牙裝置...'),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: dialogScanResults.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: dialogScanResults.length,
                        itemBuilder: (context, index) {
                          final result = dialogScanResults[index];
                          return ListTile(
                            title: Text(result.device.platformName),
                            subtitle: Text(result.device.remoteId.toString()),
                            trailing: Text('${result.rssi} dBm'),
                            onTap: () async {
                              await FlutterBluePlus.stopScan();
                              try {
                                await service.connectToDevice(result.device);
                                if (Navigator.of(context).canPop()) {
                                  Navigator.of(context).pop();
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('連接失敗: $e')),
                                  );
                                }
                              }
                            },
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  child: const Text('關閉'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      FlutterBluePlus.stopScan();
      _scanResultsSubscription?.cancel();
      _scanResultsSubscription = null;
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 特徵 Tile
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCharacteristicTile(BluetoothCharacteristic c) {
    final serviceState = ref.watch(dataMatchServiceProvider);
    final service = ref.read(dataMatchServiceProvider.notifier);

    String valueText = '';
    List<int>? value =
        serviceState.notifyValues[c.uuid] ?? serviceState.readValues[c.uuid];
    if (value != null) {
      valueText =
          '[${value.join(', ')}]\n${utf8.decode(value, allowMalformed: true)}';
    }

    return ListTile(
      title: Text('特徵: ${c.uuid}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(valueText),
          Wrap(
            spacing: 8.0,
            children: [
              if (c.properties.read) const Chip(label: Text('Read')),
              if (c.properties.write) const Chip(label: Text('Write')),
              if (c.properties.notify) const Chip(label: Text('Notify')),
              if (c.properties.indicate) const Chip(label: Text('Indicate')),
            ],
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (c.properties.read)
            IconButton(
              icon: const Icon(Icons.file_download),
              onPressed: () => service.readCharacteristic(c),
            ),
          if (c.properties.write)
            IconButton(
              icon: const Icon(Icons.file_upload),
              onPressed: () => service.writeCharacteristic(c),
            ),
          if (c.properties.notify || c.properties.indicate)
            IconButton(
              icon: Icon(
                service.isNotifying(c.uuid)
                    ? Icons.notifications_off
                    : Icons.notifications_active,
                color: service.isNotifying(c.uuid) ? Colors.blue : Colors.grey,
              ),
              onPressed: () => service.toggleNotify(c),
            ),
        ],
      ),
    );
  }

  Widget _buildServiceTile(BluetoothService service) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(
        title: Text('服務: ${service.uuid}'),
        children: service.characteristics
            .map(_buildCharacteristicTile)
            .toList(),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 插值統計
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildInterpolationStats() {
    final interpolatedData = ref.watch(interpolatedDataProvider);
    final filterStatus = ref.read(dataClassifierProvider).getFilterStatus();

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('插值統計', style: Theme.of(context).textTheme.headlineSmall),
            const Divider(),
            Text('篩選器基準值: ${filterStatus['基準值'] ?? "學習中"}'),
            if (filterStatus['候選值'] != null)
              Text(
                '候選值: ${filterStatus['候選值']} (連續${filterStatus['候選連續次數']}次)',
              ),
            const SizedBox(height: 8),
            Text('原始數據: ${interpolatedData.totalOriginal} 筆'),
            Text('插值數據: ${interpolatedData.totalInterpolated} 筆'),
            Text(
              '總計: ${interpolatedData.totalOriginal + interpolatedData.totalInterpolated} 筆',
            ),
            Text(
              '倍增率: ${interpolatedData.totalOriginal > 0 ? ((interpolatedData.totalOriginal + interpolatedData.totalInterpolated) / interpolatedData.totalOriginal).toStringAsFixed(2) : "0.00"}x',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 16),
            Text('最近數據流 (${interpolatedData.packets.length} 筆緩衝):'),
            SizedBox(
              height: 100,
              child: ListView.builder(
                reverse: true,
                itemCount: interpolatedData.packets.length.clamp(0, 10),
                itemBuilder: (context, index) {
                  final reversedIndex =
                      interpolatedData.packets.length - 1 - index;
                  final packet = interpolatedData.packets[reversedIndex];
                  return Text(
                    '${packet.isInterpolated ? "📊" : "📦"} ts=${packet.timestamp} [${packet.data.take(3).join(',')}...]',
                    style: TextStyle(
                      fontSize: 11,
                      color: packet.isInterpolated ? Colors.blue : Colors.green,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 已連線畫面
  // ═══════════════════════════════════════════════════════════════════════════

  // Widget _buildConnectedDeviceView() {
  //   final serviceState = ref.watch(dataMatchServiceProvider);
  //   final service = ref.read(dataMatchServiceProvider.notifier);
  //   final health = ref.watch(healthDataProvider);

  //   return SingleChildScrollView(
  //     child: Column(
  //       children: [
  //         // _buildAutoReconnectSwitch(), // 新增自動重連開關
  //         _buildInterpolationStats(),
  //         const SizedBox(height: 16),
  //         const Text('心率'),
  //         Text(
  //           '${health.hr}',
  //           style: Theme.of(context).textTheme.headlineMedium,
  //         ),
  //         const SizedBox(height: 10),
  //         const Text('呼吸'),
  //         Text(
  //           '${health.br}',
  //           style: Theme.of(context).textTheme.headlineMedium,
  //         ),
  //         const SizedBox(height: 20),
  //         const Text('陀螺儀'),
  //         Text(
  //           'X: ${health.gyroX}',
  //           style: Theme.of(context).textTheme.headlineMedium,
  //         ),
  //         Text(
  //           'Y: ${health.gyroY}',
  //           style: Theme.of(context).textTheme.headlineMedium,
  //         ),
  //         Text(
  //           'Z: ${health.gyroZ}',
  //           style: Theme.of(context).textTheme.headlineMedium,
  //         ),
  //         const SizedBox(height: 10),
  //         const Text('溫度'),
  //         Text(
  //           '${health.temp}',
  //           style: Theme.of(context).textTheme.headlineMedium,
  //         ),
  //         const Text('濕度'),
  //         Text(
  //           '${health.hum}',
  //           style: Theme.of(context).textTheme.headlineMedium,
  //         ),
  //         const Text('電量'),
  //         Text(
  //           '${health.power}',
  //           style: Theme.of(context).textTheme.headlineMedium,
  //         ),
  //         const Text('穿戴狀態'),
  //         Text(
  //           '${health.isWearing}',
  //           style: Theme.of(context).textTheme.headlineMedium,
  //         ),
  //         const Text('寵物姿勢'),
  //         Text(
  //           '${health.petPose}',
  //           style: Theme.of(context).textTheme.headlineMedium,
  //         ),
  //         const SizedBox(height: 16),
  //         Text(
  //           '已連接到: ${serviceState.connectedDevice!.platformName}',
  //           style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
  //         ),
  //         const SizedBox(height: 8),
  //         ElevatedButton(
  //           onPressed: () => service.disconnectFromDevice(),
  //           style: ElevatedButton.styleFrom(backgroundColor: Colors.red[400]),
  //           child: const Text('斷開藍芽裝置'),
  //         ),
  //         const SizedBox(height: 8),
  //         serviceState.services.isEmpty
  //             ? const Center(child: Text('未發現服務'))
  //             : SizedBox(
  //                 height: 400,
  //                 child: ListView.builder(
  //                   itemCount: serviceState.services.length,
  //                   itemBuilder: (context, index) =>
  //                       _buildServiceTile(serviceState.services[index]),
  //                 ),
  //               ),
  //       ],
  //     ),
  //   );
  // }

  // ═══════════════════════════════════════════════════════════════════════════
  // ✅ 修改：已連線畫面 - 斷線按鈕加入保護
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildConnectedDeviceView() {
    final serviceState = ref.watch(dataMatchServiceProvider);
    final service = ref.read(dataMatchServiceProvider.notifier);
    final health = ref.watch(healthDataProvider);

    return SingleChildScrollView(
      child: Column(
        children: [
          _buildInterpolationStats(),
          const SizedBox(height: 16),
          const Text('心率'),
          Text(
            '${health.hr}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          const Text('呼吸'),
          Text(
            '${health.br}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 20),
          const Text('陀螺儀'),
          Text(
            'X: ${health.gyroX}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          Text(
            'Y: ${health.gyroY}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          Text(
            'Z: ${health.gyroZ}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          const Text('溫度'),
          Text(
            '${health.temp}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const Text('濕度'),
          const SizedBox(height: 10),
          Text(
            '${health.temp}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const Text('步數'),
          Text(
            '${health.step}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const Text('電量'),
          Text(
            '${health.power}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const Text('穿戴狀態'),
          Text(
            '${health.isWearing}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const Text('寵物姿勢'),
          Text(
            '${health.petPose}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          Text(
            '已連接到: ${serviceState.connectedDevice!.platformName}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          // ✅ 修改：斷線按鈕加入冷卻保護
          ElevatedButton(
            onPressed: _isButtonCooldown
                ? null
                : () => _executeWithCooldown(() async {
                    await service.disconnectFromDevice();
                  }),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isButtonCooldown
                  ? Colors.grey
                  : Colors.red[400],
            ),
            child: Text(_isButtonCooldown ? '請稍候...' : '斷開藍芽裝置'),
          ),

          const SizedBox(height: 8),
          serviceState.services.isEmpty
              ? const Center(child: Text('未發現服務'))
              : SizedBox(
                  height: 400,
                  child: ListView.builder(
                    itemCount: serviceState.services.length,
                    itemBuilder: (context, index) =>
                        _buildServiceTile(serviceState.services[index]),
                  ),
                ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 未連線畫面
  // ═══════════════════════════════════════════════════════════════════════════

  // Widget _buildDisconnectedView() {
  //   return Column(
  //     mainAxisAlignment: MainAxisAlignment.center,
  //     children: [
  //       // _buildAutoReconnectSwitch(), // 新增自動重連開關
  //       ElevatedButton(
  //         onPressed: () => _toggleScan(context),
  //         child: const Text('掃描並連接藍牙裝置'),
  //       ),
  //       _buildReconnectButton(),
  //     ],
  //   );
  // }

  // ═══════════════════════════════════════════════════════════════════════════
  // ✅ 修改：掃描按鈕也要加入保護
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDisconnectedView() {
    final service = ref.read(dataMatchServiceProvider.notifier);
    final isInCooldown = service.isInCooldown;
    final isTooFrequent = service.isTooFrequent;
    final waitTime = service.getWaitTimeSeconds();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: (isInCooldown || isTooFrequent || _isButtonCooldown)
              ? null
              : () => _toggleScan(context),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                (isInCooldown || isTooFrequent || _isButtonCooldown)
                ? Colors.grey
                : null,
          ),
          child: Text(
            isInCooldown
                ? '等待 $waitTime 秒...'
                : isTooFrequent
                ? '操作過於頻繁'
                : '掃描並連接藍牙裝置',
          ),
        ),
        if (isTooFrequent)
          const Padding(
            padding: EdgeInsets.only(top: 8.0),
            child: Text(
              '⚠️ 短時間內操作過多，請等待 30 秒',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
        const SizedBox(height: 16),
        _buildReconnectButton(),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 開關插值
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildInterpolationToggle() {
    final serviceState = ref.watch(dataMatchServiceProvider);
    final service = ref.read(dataMatchServiceProvider.notifier);

    return SwitchListTile(
      title: const Text('啟用插值'),
      subtitle: Text(
        serviceState.enableInterpolation ? '開啟：16Hz → 32Hz' : '關閉：保持原始 16Hz',
      ),
      value: serviceState.enableInterpolation,
      onChanged: (value) => service.setInterpolationEnabled(value),
    );
  }

  // 在斷線後的 UI 區域，新增一個「重新連線」按鈕

  // Widget _buildReconnectButton() {
  //   final service = ref.read(dataMatchServiceProvider.notifier);
  //   final serviceState = ref.watch(dataMatchServiceProvider);
  //   final hasLastDevice = service.lastConnectedDevice != null;

  //   if (!hasLastDevice) return const SizedBox.shrink();

  //   // ✅ 如果正在自動重連中
  //   if (serviceState.isReconnecting) {
  //     return Padding(
  //       padding: const EdgeInsets.all(16.0),
  //       child: Column(
  //         children: [
  //           const CircularProgressIndicator(),
  //           const SizedBox(height: 8),
  //           Text(
  //             '自動重連中 (${serviceState.reconnectAttempts}/5)...',
  //             style: const TextStyle(color: Colors.orange),
  //           ),
  //         ],
  //       ),
  //     );
  //   }

  //   // ✅ 如果正在手動重連中
  //   if (_isReconnecting) {
  //     return const Padding(
  //       padding: EdgeInsets.all(16.0),
  //       child: Column(
  //         children: [
  //           CircularProgressIndicator(),
  //           SizedBox(height: 8),
  //           Text('正在搜尋裝置...', style: TextStyle(color: Colors.blue)),
  //         ],
  //       ),
  //     );
  //   }

  //   return Padding(
  //     padding: const EdgeInsets.all(16.0),
  //     child: ElevatedButton.icon(
  //       onPressed: () async {
  //         setState(() => _isReconnecting = true);

  //         final success = await service.connectToLastDevice();

  //         if (mounted) {
  //           setState(() => _isReconnecting = false);

  //           if (!success) {
  //             ScaffoldMessenger.of(context).showSnackBar(
  //               const SnackBar(
  //                 content: Text('裝置不在範圍內，請確認裝置已開啟並稍後再試'),
  //                 duration: Duration(seconds: 3),
  //               ),
  //             );
  //           }
  //         }
  //       },
  //       icon: const Icon(Icons.refresh),
  //       label: Text('重新連線 ${service.lastConnectedDeviceName ?? ""}'),
  //     ),
  //   );
  // }

  // ═══════════════════════════════════════════════════════════════════════════
  // ✅ 修改：重新連線按鈕 - 加入保護
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildReconnectButton() {
    final service = ref.read(dataMatchServiceProvider.notifier);
    final serviceState = ref.watch(dataMatchServiceProvider);
    final hasLastDevice = service.lastConnectedDevice != null;

    if (!hasLastDevice) return const SizedBox.shrink();

    // 如果正在自動重連中
    if (serviceState.isReconnecting) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 8),
            Text(
              '自動重連中 (${serviceState.reconnectAttempts}/5)...',
              style: const TextStyle(color: Colors.orange),
            ),
          ],
        ),
      );
    }

    // 如果正在手動重連中
    if (_isReconnecting) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 8),
            Text('正在搜尋裝置...', style: TextStyle(color: Colors.blue)),
          ],
        ),
      );
    }

    // ✅ 顯示冷卻狀態
    final isInCooldown = service.isInCooldown;
    final isTooFrequent = service.isTooFrequent;
    final waitTime = service.getWaitTimeSeconds();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          ElevatedButton.icon(
            onPressed: (isInCooldown || isTooFrequent || _isButtonCooldown)
                ? null
                : () async {
                    final canProceed = await _executeWithCooldown<bool>(
                      () async {
                        setState(() => _isReconnecting = true);
                        final success = await service.connectToLastDevice();
                        if (mounted) {
                          setState(() => _isReconnecting = false);
                          if (!success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('裝置不在範圍內，請確認裝置已開啟並稍後再試'),
                                duration: Duration(seconds: 3),
                              ),
                            );
                          }
                        }
                        return success;
                      },
                    );
                  },
            icon: const Icon(Icons.refresh),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  (isInCooldown || isTooFrequent || _isButtonCooldown)
                  ? Colors.grey
                  : null,
            ),
            label: Text(
              isInCooldown
                  ? '等待 $waitTime 秒...'
                  : isTooFrequent
                  ? '操作過於頻繁'
                  : _isButtonCooldown
                  ? '請稍候...'
                  : '重新連線 ${service.lastConnectedDeviceName ?? ""}',
            ),
          ),
          if (isTooFrequent)
            const Padding(
              padding: EdgeInsets.only(top: 8.0),
              child: Text(
                '⚠️ 短時間內操作過多，請等待 30 秒',
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 自動重連開關
  // ═══════════════════════════════════════════════════════════════════════════

  // Widget _buildAutoReconnectSwitch() {
  //   final service = ref.read(dataMatchServiceProvider.notifier);
  //   final isEnabled = service.isAutoReconnectEnabled;

  //   return SwitchListTile(
  //     title: const Text('自動重連'),
  //     subtitle: const Text('意外斷線時自動嘗試重新連線'),
  //     value: isEnabled,
  //     onChanged: (value) {
  //       service.setAutoReconnect(value);
  //       setState(() {});
  //     },
  //   );
  // }

  // ═══════════════════════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final serviceState = ref.watch(dataMatchServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('藍牙服務瀏覽器')),
      body: SafeArea(
        child: Center(
          child: serviceState.isConnected
              ? SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildInterpolationToggle(),
                      _buildConnectedDeviceView(),
                    ],
                  ),
                )
              : _buildDisconnectedView(),
        ),
      ),
    );
  }
}
