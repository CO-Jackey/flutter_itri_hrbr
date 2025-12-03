import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_itri_hrbr/provider/health_provider.dart';
import 'package:flutter_itri_hrbr/services/simple_single_connection_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SimpleConnectionViewPage extends ConsumerStatefulWidget {
  const SimpleConnectionViewPage({super.key});

  @override
  ConsumerState<SimpleConnectionViewPage> createState() =>
      _SimpleConnectionViewPageState();
}

class _SimpleConnectionViewPageState
    extends ConsumerState<SimpleConnectionViewPage> {
  @override
  void initState() {
    super.initState();
    ref.read(simpleConnectionServiceProvider.notifier).requestPermissions();
  }

  @override
  void dispose() {
    ref.read(simpleConnectionServiceProvider.notifier).cleanup();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 掃描 Dialog（參考 muti_view_mac_page 的設計）
  // ═══════════════════════════════════════════════════════════════════════════

  void _toggleScan(BuildContext context) async {
    final service = ref.read(simpleConnectionServiceProvider.notifier);

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

    // 開始掃描並顯示 Dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ScanDialog(),
    ).then((_) {
      service.stopScan();
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 特徵 Tile
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCharacteristicTile(BluetoothCharacteristic c) {
    final serviceState = ref.watch(simpleConnectionServiceProvider);
    final service = ref.read(simpleConnectionServiceProvider.notifier);

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
  // 已連線畫面
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildConnectedDeviceView() {
    final serviceState = ref.watch(simpleConnectionServiceProvider);
    final service = ref.read(simpleConnectionServiceProvider.notifier);
    final health = ref.watch(healthDataProvider);

    return SingleChildScrollView(
      child: Column(
        children: [
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
          const SizedBox(height: 10),
          const Text('濕度'),
          Text(
            '${health.hum}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          const Text('步數'),
          Text(
            '${health.step}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          const Text('電量'),
          Text(
            '${health.power}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          const Text('穿戴狀態'),
          Text(
            '${health.isWearing}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
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
          ElevatedButton(
            onPressed: () => service.disconnectFromDevice(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[400],
            ),
            child: const Text('斷開藍芽裝置'),
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

  Widget _buildDisconnectedView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: () => _toggleScan(context),
          child: const Text('掃描並連接藍牙裝置'),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final serviceState = ref.watch(simpleConnectionServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('簡易藍牙連線')),
      body: SafeArea(
        child: Center(
          child: serviceState.isConnected
              ? _buildConnectedDeviceView()
              : _buildDisconnectedView(),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 掃描 Dialog（參考 muti_view_mac_page）
// ═══════════════════════════════════════════════════════════════════════════

class _ScanDialog extends ConsumerStatefulWidget {
  const _ScanDialog();

  @override
  ConsumerState<_ScanDialog> createState() => _ScanDialogState();
}

class _ScanDialogState extends ConsumerState<_ScanDialog> {
  List<ScanResult> _scanResults = [];
  bool _isScanning = true;
  
  // ✅ 修正：保存 StreamSubscription 以便正確取消
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;
  StreamSubscription<bool>? _isScanningSubscription;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  void _startScan() {
    // 開始掃描
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

    // ✅ 訂閱掃描結果（保存 subscription）
    _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          _scanResults = results
              .where((r) => r.device.platformName.isNotEmpty)
              .toList();
        });
      }
    });

    // ✅ 監聽掃描狀態（保存 subscription）
    _isScanningSubscription = FlutterBluePlus.isScanning.listen((isScanning) {
      if (mounted) {
        setState(() {
          _isScanning = isScanning;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.read(simpleConnectionServiceProvider.notifier);
    final serviceState = ref.watch(simpleConnectionServiceProvider);

    return WillPopScope(
      onWillPop: () async => false,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.bluetooth_searching, color: Color(0xFF2196F3)),
            const SizedBox(width: 10),
            const Text('掃描藍芽設備'),
            const Spacer(),
            if (_isScanning)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        content: SizedBox(
          width: 500,
          height: 400,
          child: _scanResults.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isScanning
                            ? Icons.bluetooth_searching
                            : Icons.bluetooth_disabled,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isScanning ? '正在搜尋設備...' : '尚未找到設備',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _scanResults.length,
                  itemBuilder: (_, i) {
                    final result = _scanResults[i];
                    final device = result.device;
                    final isConnected =
                        serviceState.connectedDevice?.remoteId == device.remoteId;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: Icon(
                          Icons.bluetooth,
                          color: isConnected
                              ? Colors.green
                              : const Color(0xFF2196F3),
                        ),
                        title: Text(
                          device.platformName.isEmpty
                              ? device.remoteId.toString()
                              : device.platformName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          '${device.remoteId}\nRSSI: ${result.rssi} dBm',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: isConnected
                            ? Chip(
                                label: const Text('已連線'),
                                backgroundColor: Colors.green[100],
                                labelStyle: TextStyle(
                                  color: Colors.green[800],
                                  fontSize: 12,
                                ),
                              )
                            : ElevatedButton(
                                onPressed: () async {
                                  try {
                                    // 停止掃描
                                    await FlutterBluePlus.stopScan();

                                    // 連接設備
                                    final success = await service.connectToDevice(device);

                                    if (success && mounted) {
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('✅ 已連接 ${device.platformName}'),
                                          backgroundColor: Colors.green,
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    } else if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('❌ 連接失敗 ${device.platformName}'),
                                          backgroundColor: Colors.red,
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('連接失敗: $e'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  }
                                },
                                child: const Text('連接'),
                              ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              FlutterBluePlus.stopScan();
              Navigator.pop(context);
            },
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // ✅ 修正：取消所有 StreamSubscription
    _scanResultsSubscription?.cancel();
    _isScanningSubscription?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }
}
