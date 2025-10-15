import 'package:flutter/material.dart';
import 'package:flutter_itri_hrbr/model/broadcast_data.dart';
import 'package:flutter_itri_hrbr/provider/broadcasr_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BroadcastTestPage extends ConsumerWidget {
  const BroadcastTestPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(broadcastServiceProvider);
    final service = ref.read(broadcastServiceProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('廣播模式測試 - 階段1')),
      body: Column(
        children: [
          // 控制按鈕
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                ElevatedButton.icon(
                  onPressed: state.isScanning
                      ? null
                      : () => service.startScan(),
                  icon: const Icon(Icons.radar),
                  label: const Text('開始掃描'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: state.isScanning ? () => service.stopScan() : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('停止'),
                ),
              ],
            ),
          ),
          // 裝置列表
          Expanded(
            child: state.devices.isEmpty
                ? const Center(child: Text('尚無裝置'))
                : ListView(
                    children: state.devices.values.map((device) {
                      return _DeviceCard(device: device);
                    }).toList(),
                  ),

            // ListView(
            //     children: state.devices.values.map((device) {
            //       return ListTile(
            //         title: Text(device.name),
            //         subtitle: Text(
            //           'ID: ${device.deviceId}\n'
            //           'RSSI: ${device.rssi}\n'
            //           'Data: ${device.manufacturerData}',
            //         ),
            //         isThreeLine: true,
            //       );
            //     }).toList(),
            //   ),
          ),
        ],
      ),
    );
  }
}

/// 階段 2：單個裝置卡片（監聽健康數據）
class _DeviceCard extends ConsumerWidget {
  final BroadcastDevice device;
  const _DeviceCard({required this.device});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 階段 2.1/2.3：監聽該裝置的健康數據
    final healthState = ref.watch(broadcastHealthFamily(device.deviceId));

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(
        title: Text(
          device.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('${device.deviceId} | RSSI: ${device.rssi}'),
        children: [
          // 階段 2.1：顯示封包統計
          ListTile(
            dense: true,
            title: const Text('封包統計'),
            trailing: Text(
              '收到 ${healthState.packetCount} 筆',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          if (healthState.lastUpdateTime != null)
            ListTile(
              dense: true,
              title: const Text('最後更新'),
              trailing: Text(
                '${healthState.lastUpdateTime!.hour}:${healthState.lastUpdateTime!.minute}:${healthState.lastUpdateTime!.second}',
              ),
            ),
          const Divider(),
          // 顯示 device 完整資訊（List 形式）
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '裝置詳細資訊',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _InfoRow('名稱', device.name),
                _InfoRow('裝置 ID', device.deviceId),
                _InfoRow('RSSI', '${device.rssi} dBm'),
                _InfoRow('最後更新', healthState.lastUpdateTime != null
                    ? '${healthState.lastUpdateTime!.hour.toString().padLeft(2, '0')}:'
                      '${healthState.lastUpdateTime!.minute.toString().padLeft(2, '0')}:'
                      '${healthState.lastUpdateTime!.second.toString().padLeft(2, '0')}'
                    : 'N/A'),
                _InfoRow('封包數', '${healthState.packetCount}'),
                if (device.manufacturerData != null)
                  _InfoRow('Manufacturer Data', device.manufacturerData!.take(8).join(', ') + '...'),
              ],
            ),
          ),
          const Divider(),
          // 階段 2.3：顯示 SDK 解析結果
          if (healthState.latestRawPacket != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  // todo: 顯示更多解析結果
                  Text(
                    'Raw: ${healthState.latestRawPacket}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          // 原始數據（可選）
          // if (healthState.latestRawPacket != null)
          //   ExpansionTile(
          //     title: const Text('原始封包', style: TextStyle(fontSize: 12)),
          //     children: [
          //       Padding(
          //         padding: const EdgeInsets.all(8),
          //         child: SelectableText(
          //           healthState.latestRawPacket.toString(),
          //           style: const TextStyle(
          //             fontSize: 10,
          //             fontFamily: 'monospace',
          //           ),
          //         ),
          //       ),
          //     ],
          //   ),
        ],
      ),
    );
  }
}

/// 信息行小部件
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
