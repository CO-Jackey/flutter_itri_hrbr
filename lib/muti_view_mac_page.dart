import 'package:flutter/material.dart';
import 'package:flutter_itri_hrbr/helper/devLog.dart';
import 'package:flutter_itri_hrbr/model/muti_view_data.dart';
import 'package:flutter_itri_hrbr/provider/muti_mac_device_health_provider.dart';
import 'package:flutter_itri_hrbr/services/muti_mac_view_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// 🎯 Step 2: 簡易版寵物監控頁面（固定 2x4 網格，只訂閱 fff4）
class PetMonitorSimplePage extends ConsumerWidget {
  const PetMonitorSimplePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 👀 監聽已連線設備列表（有數據的）
    final devices = ref.watch(connectedDevicesListProvider);

    // 👀 監聽統計資訊
    final stats = ref.watch(deviceStatisticsProvider);

    // 👀 監聽藍芽管理狀態
    final btState = ref.watch(bluetoothManagerProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Column(
        children: [
          // 頂部狀態欄
          _buildTopBar(context, ref, stats, btState),

          // 主要內容區（固定高度，不滾動）
          Expanded(
            child: _buildFixedGrid(context, ref, devices, btState),
          ),
        ],
      ),
    );
  }

  /// 頂部狀態欄
  Widget _buildTopBar(
    BuildContext context,
    WidgetRef ref,
    Map<String, int> stats,
    BluetoothMultiConnectionState btState,
  ) {
    return Container(
      height: 80,
      decoration: const BoxDecoration(
        color: Color(0xFFFF6900),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Row(
          children: [
            const Text(
              '🐾 寵物監控系統',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(width: 40),

            // 🔍 掃描設備按鈕
            ElevatedButton.icon(
              onPressed: () => _showScanDialog(context, ref),
              icon: const Icon(Icons.search, size: 20),
              label: const Text('掃描設備'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFFFF9850),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),

            // 🔌 全部斷線按鈕
            if (btState.connectedDevices.isNotEmpty) ...[
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _showDisconnectAllDialog(context, ref),
                icon: const Icon(Icons.link_off, size: 20),
                label: const Text('全部斷線'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[400],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ],

            const Spacer(),

            // 統計資訊
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  _buildStatItem('🟢 在線', stats['connected'] ?? 0),
                  const SizedBox(width: 20),
                  _buildStatItem('⚠️ 注意', stats['warning'] ?? 0),
                  const SizedBox(width: 20),
                  _buildStatItem('🚨 異常', stats['error'] ?? 0),
                  const SizedBox(width: 20),
                  _buildStatItem('總計', stats['total'] ?? 0),
                ],
              ),
            ),

            const Spacer(),

            Text(
              '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
              style: const TextStyle(color: Colors.white, fontSize: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, int count) {
    return Row(
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 16)),
        const SizedBox(width: 8),
        Text(
          '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  /// 固定 2x4 網格（不滾動）
  Widget _buildFixedGrid(
    BuildContext context,
    WidgetRef ref,
    List<CardPetInfo> devices,
    BluetoothMultiConnectionState btState,
  ) {
    // 如果完全沒有連線，顯示空狀態
    if (btState.connectedDevices.isEmpty && devices.isEmpty) {
      return _buildEmptyState(context, ref);
    }

    // 固定顯示 8 個位置（2 排 x 4 列）
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // 第一排（4 個）
          Expanded(
            child: Row(
              children: [
                for (int i = 0; i < 4; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: i < 3 ? 20 : 0,
                      ),
                      child: _buildCardSlot(i, devices, btState),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // 第二排（4 個）
          Expanded(
            child: Row(
              children: [
                for (int i = 4; i < 8; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: i < 7 ? 20 : 0,
                      ),
                      child: _buildCardSlot(i, devices, btState),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 單一卡片位置
  // Widget _buildCardSlot(
  //   int index,
  //   List<CardPetInfo> devices,
  //   BluetoothMultiConnectionState btState,
  // ) {
  //   // 如果有對應的設備數據，顯示設備卡片
  //   if (index < devices.length) {
  //     return SimpleDeviceCard(device: devices[index]);
  //   }

  //   // 如果有連線但還沒數據，顯示等待狀態
  //   final connectedCount = btState.connectedDevices.length;
  //   if (index < connectedCount) {
  //     return _buildWaitingCard(index + 1);
  //   }

  //   // 否則顯示空位
  //   return _buildEmptyCard(index + 1);
  // }

  Widget _buildCardSlot(
    int index,
    List<CardPetInfo> devices,
    BluetoothMultiConnectionState btState,
  ) {
    // ⭐ 取得已連線的設備 ID 列表
    final connectedDeviceIds = btState.connectedDevices.keys.toList();

    // 條件 1：如果該位置沒有連線設備，顯示空位
    if (index >= connectedDeviceIds.length) {
      return _buildEmptyCard(index + 1);
    }

    // ⭐ 取得該位置對應的設備 ID
    final deviceIdAtThisSlot = connectedDeviceIds[index];

    // 條件 2：檢查 devices 列表中是否有該設備的數據
    CardPetInfo? deviceData;
    try {
      deviceData = devices.firstWhere(
        (d) => d.deviceId == deviceIdAtThisSlot.str,
      );
    } catch (e) {
      deviceData = null;
    }

    if (deviceData != null) {
      // 有數據 → 顯示數據卡片
      return SimpleDeviceCard(device: deviceData);
    }

    // 條件 3：有連線但還沒數據 → 顯示等待狀態
    return _buildWaitingCard(index + 1);
  }

  /// 等待數據的卡片
  Widget _buildWaitingCard(int slotNumber) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.blue[300]!, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            '$slotNumber號位',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF666666),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '正在接收數據...',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  /// 空位卡片
  Widget _buildEmptyCard(int slotNumber) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: Colors.grey[300]!,
          width: 2,
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_circle_outline, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            '${slotNumber}號位',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '空置',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  /// 完全空狀態（沒有任何連線）
  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bluetooth_searching, size: 100, color: Colors.grey[400]),
          const SizedBox(height: 20),
          Text(
            '沒有連線的設備',
            style: TextStyle(
              fontSize: 24,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '請點擊上方「掃描設備」開始連接',
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
          // const SizedBox(height: 30),
          // ElevatedButton.icon(
          //   onPressed: () => _showScanDialog(context, ref),
          //   icon: const Icon(Icons.search),
          //   label: const Text('掃描設備'),
          //   style: ElevatedButton.styleFrom(
          //     padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
          //     textStyle: const TextStyle(fontSize: 18),
          //   ),
          // ),
        ],
      ),
    );
  }

  /// 🔍 顯示掃描對話框
  void _showScanDialog(BuildContext context, WidgetRef ref) {
    final manager = ref.read(bluetoothManagerProvider.notifier);
    manager.startScan();

    showDialog(
      context: context,
      barrierDismissible: false, // 防止意外關閉
      builder: (_) => const _ScanDialog(),
    ).then((_) {
      // 確保停止掃描
      manager.stopScan();
    });
  }

  /// 🔌 顯示全部斷線確認對話框
  void _showDisconnectAllDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('確認斷線'),
        content: const Text('確定要斷開所有設備的連線嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final manager = ref.read(bluetoothManagerProvider.notifier);

              // 先斷開所有連線
              await manager.disconnectAll();

              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已斷開所有設備'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('確定斷線'),
          ),
        ],
      ),
    );
  }
}

// ==================== 🔍 掃描對話框（只訂閱 fff4） ====================

class _ScanDialog extends ConsumerStatefulWidget {
  const _ScanDialog();

  @override
  ConsumerState<_ScanDialog> createState() => _ScanDialogState();
}

class _ScanDialogState extends ConsumerState<_ScanDialog> {
  // 追蹤正在處理的設備
  final Set<String> _processingDevices = {};

  /// ✅ 獨立的訂閱函數（不依賴 Dialog context）
  Future<void> _autoSubscribeFFF4(
    BluetoothMultiManager manager,
    BluetoothDevice device,
  ) async {
    final deviceId = device.remoteId.toString();

    if (_processingDevices.contains(deviceId)) {
      devLog('[訂閱流程]', '⚠️ 設備 $deviceId 正在處理中，跳過');
      return;
    }

    _processingDevices.add(deviceId);

    try {
      devLog('[訂閱流程]', '🔍 開始處理設備: $deviceId');

      // ✅ 關鍵修正：等待服務發現完成
      devLog('[訂閱流程]', '⏳ 等待服務發現完成...');
      await Future.delayed(const Duration(milliseconds: 500));

      // 1. 載入 services
      devLog('[訂閱流程]', '📡 載入 services...');
      await manager.ensureServices(device);

      // ✅ 新增：驗證服務是否載入成功
      final services = manager.servicesCache[device.remoteId];
      if (services == null || services.isEmpty) {
        throw Exception('服務載入失敗或為空');
      }
      devLog('[訂閱流程]', '✅ Services 載入完成，共 ${services.length} 個服務');

      // 2. 找出 fff4 特徵
      devLog('[訂閱流程]', '🔍 搜尋 fff4 特徵...');
      BluetoothCharacteristic? fff4Char;

      for (final service in services) {
        devLog(
          '[訂閱流程]',
          '🔍 檢查服務: ${service.uuid}, 特徵數量: ${service.characteristics.length}',
        );

        for (final char in service.characteristics) {
          final uuidStr = char.uuid.toString().toLowerCase();
          devLog(
            '[訂閱流程]',
            '  - 特徵: $uuidStr, Notify: ${char.properties.notify}',
          );

          if (uuidStr.contains('fff4') &&
              (char.properties.notify || char.properties.indicate)) {
            fff4Char = char;
            devLog('[訂閱流程]', '✅ 找到 fff4 特徵: ${char.uuid}');
            break;
          }
        }
        if (fff4Char != null) break;
      }

      if (fff4Char == null) {
        // ✅ 列出所有特徵幫助 debug
        devLog('[訂閱流程]', '⚠️ 沒有找到 fff4 特徵，以下是所有特徵：');
        for (final service in services) {
          for (final char in service.characteristics) {
            devLog('[訂閱流程]', '  - ${char.uuid}');
          }
        }

        throw Exception('找不到 fff4 特徵');
      }

      // 3. 訂閱 fff4 特徵
      devLog('[訂閱流程]', '📡 開始訂閱 fff4...');
      await manager.toggleNotify(device, fff4Char);
      devLog('[訂閱流程]', '✅ fff4 訂閱成功！');

      // 4. ✅ 驗證訂閱狀態
      final isSubscribed = manager.isNotifying(device.remoteId, fff4Char.uuid);
      devLog('[訂閱流程]', '🔍 訂閱狀態驗證: $isSubscribed');

      if (!isSubscribed) {
        throw Exception('訂閱失敗：狀態未變更');
      }

      // 5. 顯示成功訊息
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ 已連接 ${device.platformName.isEmpty ? deviceId : device.platformName}\n'
              '訂閱特徵: ${fff4Char.uuid}\n'
              '📊 請等待 5-10 秒接收資料',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }

      devLog('[訂閱流程]', '🎉 完整流程完成！');
    } catch (e, stackTrace) {
      devLog('[訂閱流程]', '❌ 發生錯誤: $e');
      devLog('[訂閱流程]', '📋 Stack trace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 訂閱失敗\n$e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      _processingDevices.remove(deviceId);
      devLog('[訂閱流程]', '🏁 設備 $deviceId 處理完畢');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bluetoothManagerProvider);
    final manager = ref.read(bluetoothManagerProvider.notifier);

    return WillPopScope(
      onWillPop: () async => false,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.bluetooth_searching, color: Color(0xFF2196F3)),
            const SizedBox(width: 10),
            const Text('掃描藍芽設備'),
            const Spacer(),
            if (state.isScanning)
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
          child: state.scanResults.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        state.isScanning
                            ? Icons.bluetooth_searching
                            : Icons.bluetooth_disabled,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        state.isScanning ? '正在搜尋設備...' : '尚未找到設備',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: state.scanResults.length,
                  itemBuilder: (_, i) {
                    final result = state.scanResults[i];
                    final device = result.device;
                    final isConnected = state.connectedDevices.containsKey(
                      device.remoteId,
                    );
                    final isProcessing = _processingDevices.contains(
                      device.remoteId.toString(),
                    );

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
                        trailing: isProcessing
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : isConnected
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
                                  devLog(
                                    '[連接狀態]',
                                    '🚀 [UI] 點擊連接按鈕: ${device.remoteId}',
                                  );

                                  try {
                                    // 1. 連接設備
                                    devLog('[連接狀態]', '📡 [UI] 開始連接設備...');
                                    await manager.connectToDevice(device);
                                    devLog('[連接狀態]', '✅ [UI] 設備連接成功');

                                    // 2. ✅ 關鍵：先關閉 Dialog，再執行訂閱
                                    // 這樣訂閱流程就不會被 Dialog 的 context 影響
                                    // if (mounted) {
                                    //   Navigator.pop(context);
                                    // }

                                    // 3. ✅ 在背景獨立執行訂閱（不依賴 Dialog context）
                                    devLog('[連接狀態]', '📡 [UI] 開始背景訂閱流程...');
                                    await _autoSubscribeFFF4(manager, device);
                                  } catch (e) {
                                    devLog('[連接狀態]', '❌ [UI] 連接失敗: $e');
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
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
              manager.stopScan();
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
    _processingDevices.clear();
    super.dispose();
  }
}

// ==================== 簡單設備卡片 ====================

class SimpleDeviceCard extends ConsumerWidget {
  final CardPetInfo device;

  const SimpleDeviceCard({Key? key, required this.device}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = device.status;
    final statusColor = _getStatusColor(status);
    final statusText = _getStatusText(status);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: statusColor,
          width: status == DeviceStatus.error ? 4 : 3,
        ),
        boxShadow: [
          BoxShadow(
            color: status == DeviceStatus.error
                ? statusColor.withOpacity(0.3)
                : Colors.black12,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildHeader(statusColor, statusText),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                children: [
                  _buildPetInfo(),
                  const SizedBox(height: 6),
                  const Divider(height: 1, color: Color(0xFFE0E0E0)),
                  const SizedBox(height: 6),
                  _buildHealthData(),
                  const Spacer(),
                  Text(
                    '更新: ${device.updateTimeText}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF999999),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Color statusColor, String statusText) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: statusColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(10),
          topRight: Radius.circular(10),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Row(
          children: [
            Text(
              '${device.cageNumber}號籠',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            // const Spacer(),
            // Text(
            //   device.deviceId,
            //   style: const TextStyle(
            //     color: Colors.white,
            //     fontSize: 10,
            //     fontWeight: FontWeight.bold,
            //   ),
            // ),
            // Text(
            //   '${device.devicePower.toString()}%',
            //   style: const TextStyle(
            //     color: Colors.white,
            //     fontSize: 18,
            //     fontWeight: FontWeight.bold,
            //   ),
            // ),
            const Spacer(),
            Text(
              statusText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPetInfo() {
    return Row(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: _getAvatarColor(),
            shape: BoxShape.circle,
          ),
          child: Center(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                device.name ?? '未知寵物',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF333333),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                device.breed ?? '未知品種',
                style: const TextStyle(fontSize: 14, color: Color(0xFF666666)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${device.age ?? 0}歲 | ${device.weight?.toStringAsFixed(1) ?? 0.0}kg | ${device.devicePower?.toString() ?? 'N/A'}% 電量',
                style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHealthData() {
    return Column(
      children: [
        _buildHealthRow(
          '❤️ 心率',
          device.hr,
          'bpm',
          device.isHeartRateDanger,
          device.isHeartRateWarning,
        ),
        // const Spacer(),
        // const SizedBox(height: 10),
        _buildHealthRow(
          '💨 呼吸',
          device.br,
          '/分',
          device.isBreathRateDanger,
          device.isBreathRateWarning,
        ),
        // const SizedBox(height: 10),
        _buildHealthRow(
          '步數',
          device.step,
          '步',
          false,
          false,
          // device.isTemperatureDanger,
          // device.isTemperatureWarning,
        ),
      ],
    );
  }

  Widget _buildHealthRow(
    String label,
    num value,
    String unit,
    bool isDanger,
    bool isWarning,
  ) {
    Color valueColor = const Color(0xFF4CAF50);
    if (isDanger)
      valueColor = const Color(0xFFF44336);
    else if (isWarning)
      valueColor = const Color(0xFFFF9800);

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 15, color: Color(0xFF666666)),
          ),
        ),
        Text(
          value is double ? value.toStringAsFixed(1) : value.toString(),
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          unit,
          style: const TextStyle(fontSize: 13, color: Color(0xFF999999)),
        ),
      ],
    );
  }

  Color _getStatusColor(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.connected:
        return const Color(0xFF4CAF50);
      case DeviceStatus.warning:
        return const Color(0xFFFF9800);
      case DeviceStatus.error:
        return const Color(0xFFF44336);
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  String _getStatusText(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.connected:
        return '連線中';
      case DeviceStatus.warning:
        return '⚠️ 注意';
      case DeviceStatus.error:
        return '🚨 異常';
      default:
        return '離線';
    }
  }

  Color _getAvatarColor() {
    if (device.petType!.contains('貓')) {
      final colors = [
        const Color(0xFFFFB74D),
        const Color(0xFFCE93D8),
        const Color(0xFFFFCC80),
        const Color(0xFFB39DDB),
      ];
      return colors[device.cageNumber! % colors.length];
    } else {
      final colors = [
        const Color(0xFF90CAF9),
        const Color(0xFFA5D6A7),
        const Color(0xFFE0E0E0),
      ];
      return colors[device.cageNumber! % colors.length];
    }
  }
}
