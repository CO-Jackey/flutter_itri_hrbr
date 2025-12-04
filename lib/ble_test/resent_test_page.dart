import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_itri_hrbr/ble_test/ble_test.dart';
import 'package:flutter_itri_hrbr/helper/devLog.dart';

/// 補傳測試頁面
/// 獨立的測試頁面，用於測試藍牙裝置的資料補傳功能
class ReSentTestPage extends StatefulWidget {
  const ReSentTestPage({super.key});

  @override
  State<ReSentTestPage> createState() => _ReSentTestPageState();
}

class _ReSentTestPageState extends State<ReSentTestPage> {
  // 測試服務
  final ReSentTestService _testService = ReSentTestService();
  
  // 藍牙相關
  BluetoothDevice? _connectedDevice;
  List<BluetoothService> _services = [];
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _notifySubscription;
  
  // 狀態
  bool _isConnected = false;
  bool _isScanning = false;
  List<ScanResult> _scanResults = [];

  @override
  void initState() {
    super.initState();
    _testService.onStateChanged = (isRunning, remaining) {
      if (mounted) setState(() {});
    };
  }

  @override
  void dispose() {
    _testService.dispose();
    _connectionSubscription?.cancel();
    _notifySubscription?.cancel();
    _connectedDevice?.disconnect();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 藍牙操作
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _scanResults = [];
    });

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    
    FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          _scanResults = results.where((r) => r.device.platformName.isNotEmpty).toList();
        });
      }
    });

    FlutterBluePlus.isScanning.listen((scanning) {
      if (mounted) {
        setState(() => _isScanning = scanning);
      }
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      await FlutterBluePlus.stopScan();
      
      // 建立連線監聽
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          devLog('連線', '裝置已斷線');
          if (mounted) {
            setState(() {
              _isConnected = false;
              _connectedDevice = null;
              _services = [];
            });
          }
        }
      });

      await device.connect(timeout: const Duration(seconds: 15));
      
      final services = await device.discoverServices();
      
      setState(() {
        _connectedDevice = device;
        _services = services;
        _isConnected = true;
      });

      // 自動訂閱 FFF4
      await _subscribeToFFF4();
      
      devLog('連線', '✅ 已連接 ${device.platformName}');
    } catch (e) {
      devLog('連線', '連接失敗: $e');
      _connectionSubscription?.cancel();
    }
  }

  Future<void> _disconnect() async {
    _notifySubscription?.cancel();
    _notifySubscription = null;
    
    await _connectedDevice?.disconnect();
    
    setState(() {
      _isConnected = false;
      _connectedDevice = null;
      _services = [];
    });
  }

  Future<bool> _reconnect() async {
    if (_connectedDevice == null) return false;
    
    try {
      await _connectedDevice!.connect(timeout: const Duration(seconds: 15));
      
      final services = await _connectedDevice!.discoverServices();
      
      setState(() {
        _services = services;
        _isConnected = true;
      });

      await _subscribeToFFF4();
      
      return true;
    } catch (e) {
      devLog('重連', '失敗: $e');
      return false;
    }
  }

  Future<void> _subscribeToFFF4() async {
    // 找出 FFF4 特徵
    BluetoothCharacteristic? fff4;
    for (final service in _services) {
      for (final char in service.characteristics) {
        if (char.uuid.toString().toLowerCase().contains('fff4') &&
            (char.properties.notify || char.properties.indicate)) {
          fff4 = char;
          break;
        }
      }
      if (fff4 != null) break;
    }

    if (fff4 == null) {
      devLog('訂閱', '找不到 FFF4 特徵');
      return;
    }

    await fff4.setNotifyValue(true);
    
    _notifySubscription = fff4.onValueReceived.listen((value) {
      // 記錄測試資料
      _testService.recordTestData(value);
      if (mounted) setState(() {});
    });
    
    devLog('訂閱', '✅ 已訂閱 FFF4');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UI
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🧪 補傳測試'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: _isConnected ? _buildConnectedView() : _buildDisconnectedView(),
      ),
    );
  }

  Widget _buildDisconnectedView() {
    return Column(
      children: [
        // 掃描控制
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: _isScanning ? null : _startScan,
            icon: _isScanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.bluetooth_searching),
            label: Text(_isScanning ? '掃描中...' : '開始掃描'),
          ),
        ),
        
        // 掃描結果
        Expanded(
          child: _scanResults.isEmpty
              ? const Center(child: Text('尚未找到裝置'))
              : ListView.builder(
                  itemCount: _scanResults.length,
                  itemBuilder: (context, index) {
                    final result = _scanResults[index];
                    return ListTile(
                      leading: const Icon(Icons.bluetooth),
                      title: Text(result.device.platformName),
                      subtitle: Text('RSSI: ${result.rssi} dBm'),
                      trailing: ElevatedButton(
                        onPressed: () => _connectToDevice(result.device),
                        child: const Text('連接'),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildConnectedView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 連線狀態
          Card(
            color: Colors.green[50],
            child: ListTile(
              leading: const Icon(Icons.bluetooth_connected, color: Colors.green),
              title: Text(_connectedDevice?.platformName ?? '未知裝置'),
              subtitle: const Text('已連線'),
              trailing: ElevatedButton(
                onPressed: _disconnect,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('斷線'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // 測試元件
          ReSentTestWidget(
            testService: _testService,
            isConnected: _isConnected,
            onDisconnect: _disconnect,
            onReconnect: _reconnect,
          ),
        ],
      ),
    );
  }
}
