import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_itri_hrbr/services/muti_iso_mac_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'provider/per_device_health_provider.dart';
// import 'services/muti_mac_ble_service.dart';
import 'helper/devLog.dart';

class MutiMacPage extends ConsumerWidget {
  const MutiMacPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final btState = ref.watch(bluetoothManagerProvider);
    final devices = btState.connectedDevices.values.toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('多裝置連線管理'),
        actions: [
          IconButton(
            tooltip: '掃描裝置',
            icon: const Icon(Icons.search),
            onPressed: () => _showScanDialog(
              context,
              ref.read(bluetoothManagerProvider.notifier),
            ),
          ),
          if (devices.isNotEmpty)
            IconButton(
              tooltip: '全部斷線',
              icon: const Icon(Icons.link_off),
              onPressed: () =>
                  ref.read(bluetoothManagerProvider.notifier).disconnectAll(),
            ),
        ],
      ),
      body: SafeArea(
        child: devices.isEmpty
            ? _NoDeviceArea(
                onScan: () => _showScanDialog(
                  context,
                  ref.read(bluetoothManagerProvider.notifier),
                ),
              )
            : Column(
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        '已連線裝置數：${devices.length}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: _DeviceListArea(devices: devices)),
                ],
              ),
      ),
    );
  }

  void _showScanDialog(
    BuildContext context,
    // BluetoothManager manager,
    BluetoothISOManager manager,
  ) {
    manager.startScan();
    showDialog(
      context: context,
      builder: (_) => const _ScanDialog(),
    ).then((_) => manager.stopScan());
  }
}

/* ================= 掃描 Dialog ================= */

class _ScanDialog extends ConsumerWidget {
  const _ScanDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bluetoothManagerProvider);
    final manager = ref.read(bluetoothManagerProvider.notifier);
    return AlertDialog(
      title: const Text('掃描裝置'),
      content: SizedBox(
        width: 360,
        height: 420,
        child: state.scanResults.isEmpty
            ? Center(
                child: state.isScanning
                    ? const CircularProgressIndicator()
                    : const Text('尚未找到裝置'),
              )
            : ListView.builder(
                itemCount: state.scanResults.length,
                itemBuilder: (_, i) {
                  final r = state.scanResults[i];
                  return ListTile(
                    dense: true,
                    title: Text(
                      r.device.platformName.isEmpty
                          ? r.device.remoteId.toString()
                          : r.device.platformName,
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      '${r.device.remoteId}\nRSSI: ${r.rssi}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () async {
                      await manager.connectToDevice(r.device);
                    },
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: const Text('關閉'),
        ),
      ],
    );
  }
}

/* ================= 未連線畫面 ================= */

class _NoDeviceArea extends StatelessWidget {
  final VoidCallback onScan;
  const _NoDeviceArea({required this.onScan});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton.icon(
        icon: const Icon(Icons.search),
        label: const Text('掃描並連線'),
        onPressed: onScan,
      ),
    );
  }
}

/* ================= 裝置清單 ================= */

class _DeviceListArea extends ConsumerWidget {
  final List<BluetoothDevice> devices;
  const _DeviceListArea({required this.devices});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SizedBox(height: 8),
        ...devices.map((d) => _DeviceCard(device: d)),
      ],
    );
  }
}

/* ================= 單一裝置卡片 ================= */

class _DeviceCard extends ConsumerStatefulWidget {
  final BluetoothDevice device;
  const _DeviceCard({required this.device});

  @override
  ConsumerState<_DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends ConsumerState<_DeviceCard> {
  bool _loadingServices = false;
  bool _isDisconnecting = false;
  bool _hidden = false; // 新增：是否隱藏整個卡片

  @override
  Widget build(BuildContext context) {
    // if (_hidden) {
    //   // 測試：隱藏後不再建立任何 UI（保留占位可改成 SizedBox(height: 0)）
    //   return const SizedBox.shrink();
    // }
    final manager = ref.read(bluetoothManagerProvider.notifier);
    final services = manager.servicesCache[widget.device.remoteId];
    final healthMap = ref.watch(perDeviceHealthProvider);
    // final health = healthMap[widget.device.remoteId];

    // 使用 select 只監聽特定裝置
    final health = ref.watch(
      perDeviceHealthProvider.select((map) => map[widget.device.remoteId]),
    );

    Widget metric(String k, Object? v) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(k, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(
          '${v ?? '-'}',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 永遠顯示的健康卡片
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Card(
              elevation: 0.5,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    // metric('HR', health?.hr),
                    // metric('BR', health?.br),
                    // metric('GX', health?.gyroX),
                    // metric('GY', health?.gyroY),
                    // metric('GZ', health?.gyroZ),
                    // metric('TEMP', health?.temp),
                    // metric('HUM', health?.hum),
                    // metric('STEP', health?.step),
                    // metric('POWER', health?.power),
                    // metric('POSE', health?.petPose),
                  ],
                ),
              ),
            ),
          ),

          // ExpansionTile 加入特徵快捷列
          ExpansionTile(
            title: _DeviceHeaderWithQuickChars(
              device: widget.device,
              services: services,
              onHide: () {
                setState(() => _hidden = true);
                // 也可在這裡選擇真正斷線：
                // ref.read(bluetoothManagerProvider.notifier)
                //    .disconnectFromDevice(widget.device);
              },
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                widget.device.remoteId.toString(),
                style: const TextStyle(fontSize: 11),
              ),
            ),
            trailing: SizedBox(
              height: 36,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: _isDisconnecting
                    ? const SizedBox(
                        key: ValueKey('progress'),
                        width: 36,
                        height: 36,
                        child: Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : ElevatedButton.icon(
                        key: const ValueKey('btn'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          minimumSize: const Size(64, 36),
                        ),
                        icon: const Icon(Icons.link_off, size: 16),
                        label: const Text('斷線'),
                        onPressed: () async {
                          setState(() => _isDisconnecting = true);
                          try {
                            await ref
                                .read(bluetoothManagerProvider.notifier)
                                .disconnectFromDevice(widget.device);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${widget.device.platformName.isEmpty ? widget.device.remoteId : widget.device.platformName} 已斷線',
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('斷線失敗: $e'),
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            }
                          } finally {
                            if (mounted)
                              setState(() => _isDisconnecting = false);
                          }
                        },
                      ),
              ),
            ),
            children: [
              const SizedBox(height: 4),
              if (_loadingServices)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                )
              else if (services == null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: ElevatedButton(
                    onPressed: () async {
                      setState(() => _loadingServices = true);
                      await manager.ensureServices(widget.device);
                      if (mounted) setState(() => _loadingServices = false);
                    },
                    child: const Text('載入服務'),
                  ),
                )
              else if (services.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('無服務'),
                )
              else
                ...services.map(
                  (s) => _ServiceTile(device: widget.device, service: s),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ],
      ),
    );
  }
}

// 新增：標題＋快捷特徵列
class _DeviceHeaderWithQuickChars extends ConsumerWidget {
  final BluetoothDevice device;
  final List<BluetoothService>? services;
  final VoidCallback? onHide; // 新增：點擊特徵後要求父層隱藏
  const _DeviceHeaderWithQuickChars({
    required this.device,
    required this.services,
    this.onHide,
  });

  String _shortUuid(Guid uuid) {
    final s = uuid.toString();
    if (s.length <= 8) return s;
    return s.substring(0, 8); // 前 8 碼
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.read(bluetoothManagerProvider.notifier);

    // 尚未載入服務 → 只顯示名稱
    if (services == null || services!.isEmpty) {
      return Text(
        device.platformName.isEmpty
            ? device.remoteId.toString()
            : device.platformName,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      );
    }

    final notifyChars = services!
        .expand((s) => s.characteristics)
        .where((c) => c.properties.notify || c.properties.indicate)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          device.platformName.isEmpty
              ? device.remoteId.toString()
              : device.platformName,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        if (notifyChars.isEmpty)
          const Text(
            '（無可通知特徵）',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          )
        else
          // 垂直列：每個特徵卡片往下排列
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: notifyChars.map((c) {
              final isNoti = manager.isNotifying(device.remoteId, c.uuid);
              final data =
                  manager.getNotifyValue(device.remoteId, c.uuid) ??
                  manager.getReadValue(device.remoteId, c.uuid);
              // String miniData = '';
              // if (data != null && data.isNotEmpty) {
              //   miniData = data.take(6).join(',');
              // }
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () async {
                    await manager.toggleNotify(device, c);
                    // 觸發隱藏（效能測試用）
                    onHide?.call();
                  },
                  onLongPress: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: Text('特徵 ${c.uuid}'),
                        content: SizedBox(
                          width: 360,
                          child: SelectableText(
                            data == null
                                ? '尚無資料'
                                : '最新資料:\n$data\nUTF8:\n${utf8.decode(data, allowMalformed: true)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('關閉'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: isNoti
                          ? Colors.blue.withOpacity(0.15)
                          : Colors.grey.withOpacity(0.15),
                      border: Border.all(
                        color: isNoti ? Colors.blue : Colors.grey,
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isNoti
                              ? Icons.notifications_active
                              : Icons.notifications_none,
                          size: 16,
                          color: isNoti ? Colors.blue : Colors.grey[700],
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _shortUuid(c.uuid),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isNoti
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: isNoti ? Colors.blue[800] : Colors.black87,
                          ),
                        ),
                        // if (miniData.isNotEmpty) ...[
                        //   const SizedBox(width: 8),
                        //   Text(
                        //     miniData,
                        //     style: TextStyle(
                        //       fontSize: 11,
                        //       color: isNoti ? Colors.blue[900] : Colors.black54,
                        //     ),
                        //   ),
                        // ],
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}

/* ================= 服務 Tile ================= */

class _ServiceTile extends ConsumerWidget {
  final BluetoothDevice device;
  final BluetoothService service;
  const _ServiceTile({required this.device, required this.service});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ExpansionTile(
        title: Text(
          'Service: ${service.uuid}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        children: service.characteristics
            .map((c) => _CharacteristicTile(device: device, c: c))
            .toList(),
      ),
    );
  }
}

/* ================= 特徵 Tile ================= */

class _CharacteristicTile extends ConsumerWidget {
  final BluetoothDevice device;
  final BluetoothCharacteristic c;
  const _CharacteristicTile({required this.device, required this.c});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.read(bluetoothManagerProvider.notifier);

    final notifyV = manager.getNotifyValue(device.remoteId, c.uuid);
    final readV = manager.getReadValue(device.remoteId, c.uuid);
    final data = notifyV ?? readV;
    final isNoti = manager.isNotifying(device.remoteId, c.uuid);

    String display = '';
    if (data != null) {
      display =
          '[${data.join(', ')}]\n${utf8.decode(data, allowMalformed: true)}';
    }

    return ListTile(
      dense: true,
      title: Text(c.uuid.toString(), style: const TextStyle(fontSize: 12)),
      subtitle: Text(''), 
      // display.isEmpty
      //     ? null
      //     : Text(display, style: const TextStyle(fontSize: 11)),
      trailing: Wrap(
        spacing: 4,
        children: [
          if (c.properties.read)
            IconButton(
              icon: const Icon(Icons.download, size: 18),
              onPressed: () => manager.readCharacteristic(device, c),
            ),
          if (c.properties.write)
            IconButton(
              icon: const Icon(Icons.upload, size: 18),
              onPressed: () => manager.writeCharacteristic(device, c),
            ),
          if (c.properties.notify || c.properties.indicate)
            IconButton(
              icon: Icon(
                isNoti ? Icons.notifications_active : Icons.notifications_none,
                size: 18,
                color: isNoti ? Colors.blue : Colors.grey,
              ),
              onPressed: () => manager.toggleNotify(device, c),
            ),
        ],
      ),
    );
  }
}
