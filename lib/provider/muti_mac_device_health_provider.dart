import 'package:flutter_itri_hrbr/helper/devLog.dart';
import 'package:flutter_itri_hrbr/model/muti_view_data.dart';
import 'package:flutter_itri_hrbr/provider/multi_device_health_provider.dart';
import 'package:flutter_itri_hrbr/services/muti_mac_view_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 🔑 核心 Provider：CardPetInfo Map（適配 Family Provider）
// ═══════════════════════════════════════════════════════════════════════════

/// 🔑 核心 Provider：CardPetInfo Map
///
/// 📋 改動說明：
/// - 舊版：直接 watch perDeviceHealthProvider（Map 模式）
/// - 新版：先取得已連線裝置列表，再逐一 watch family provider
///
/// 📌 資料流：
/// 1. 從 bluetoothManagerProvider 取得已連線裝置列表
/// 2. 對每個裝置 watch multiDeviceHealthProvider(deviceId)
/// 3. 將 HealthData 轉換成 CardPetInfo
final cardPetInfoMapProvider = Provider<Map<String, CardPetInfo>>((ref) {
  final bluetoothState = ref.watch(bluetoothManagerProvider);
  final connectedDevices = bluetoothState.connectedDevices;

  final result = <String, CardPetInfo>{};

  for (final entry in connectedDevices.entries) {
    final deviceId = entry.key;
    final deviceIdStr = deviceId.str;

    // ✅ 關鍵修正：增加錯誤處理
    try {
      final healthData = ref.watch(multiDeviceHealthProvider(deviceId));

      result[deviceIdStr] = CardPetInfo(
        deviceId: deviceIdStr,
        devicePower: healthData.power, // 新增設備電量
        cageNumber: _getCageNumberFromMac(deviceIdStr),
        name: _getDefaultName(deviceIdStr),
        petType: _getDefaultPetType(deviceIdStr),
        breed: _getDefaultBreed(deviceIdStr),
        age: _getDefaultAge(deviceIdStr),
        weight: _getDefaultWeight(deviceIdStr),
        imageUrl: null,
        hr: healthData.hr,
        br: healthData.br,
        temp: healthData.temp,
        step: healthData.step,
        isWearing: healthData.isWearing,
        updatedTime: DateTime.now(),
      );

      // ✅ 新增：Debug 輸出
      devLog(
        'CardPetInfo',
        '✅ 裝置 $deviceIdStr 資料更新: HR=${healthData.hr}, BR=${healthData.br}, Temp=${healthData.temp}',
      );
    } catch (e, stackTrace) {
      // ✅ 錯誤處理：如果該裝置的 provider 還沒初始化
      devLog('CardPetInfo', '⚠️ 裝置 $deviceIdStr 資料尚未就緒: $e');
      devLog('CardPetInfo', 'Stack: $stackTrace');
    }
  }

  return result;
});

// ═══════════════════════════════════════════════════════════════════════════
// 🎯 已連線設備列表（按籠位編號排序）
// ═══════════════════════════════════════════════════════════════════════════

/// 🎯 已連線設備列表（按籠位編號排序）
/// UI 專用：返回 List 方便 GridView 使用
///
/// 📋 功能：
/// - 將 Map 轉換成 List
/// - 可選：按籠位編號排序
final connectedDevicesListProvider = Provider<List<CardPetInfo>>((ref) {
  final cardPetInfoMap = ref.watch(cardPetInfoMapProvider);

  // 轉換成 List 並按籠位編號排序
  final list = cardPetInfoMap.values.toList()
    ..sort((a, b) => a.cageNumber!.compareTo(b.cageNumber!));

  return list;
});

// ═══════════════════════════════════════════════════════════════════════════
// 📊 統計資訊 Provider
// ═══════════════════════════════════════════════════════════════════════════

/// 📊 統計資訊 Provider
///
/// 📋 功能：
/// - 統計已連線/警告/錯誤裝置數量
/// - 用於儀表板顯示
final deviceStatisticsProvider = Provider<Map<String, int>>((ref) {
  final cardPetInfoMap = ref.watch(cardPetInfoMapProvider);

  int connected = 0;
  int warning = 0;
  int error = 0;

  for (final info in cardPetInfoMap.values) {
    switch (info.status) {
      case DeviceStatus.connected:
        connected++;
        break;
      case DeviceStatus.warning:
        warning++;
        break;
      case DeviceStatus.error:
        error++;
        break;
      default:
        break;
    }
  }

  return {
    'connected': connected,
    'warning': warning,
    'error': error,
    'total': cardPetInfoMap.length,
  };
});

// ═══════════════════════════════════════════════════════════════════════════
// 🔍 單一設備 Provider (by deviceId)
// ═══════════════════════════════════════════════════════════════════════════

/// 🔍 單一設備 Provider (by deviceId)
///
/// 📋 使用方式：
/// ```dart
/// final petInfo = ref.watch(singleCardPetInfoProvider('deviceId'));
/// ```
///
/// ⚠️ 注意：這個 provider 會依賴 cardPetInfoMapProvider
/// 建議改用下面的 `singleCardPetInfoDirectProvider` 提升效能
final singleCardPetInfoProvider = Provider.family<CardPetInfo?, String>((
  ref,
  deviceId,
) {
  final allDevices = ref.watch(cardPetInfoMapProvider);
  return allDevices[deviceId];
});

// ═══════════════════════════════════════════════════════════════════════════
// 🚀 效能優化版：直接從 Family Provider 取得單一裝置資料
// ═══════════════════════════════════════════════════════════════════════════

/// 🚀 單一設備 Provider（效能優化版）
///
/// 📋 優勢：
/// - 直接從 multiDeviceHealthProvider 取得資料
/// - 不依賴 cardPetInfoMapProvider（避免多餘的 rebuild）
/// - 只有該裝置更新時才會重新計算
///
/// 📝 使用方式：
/// ```dart
/// final petInfo = ref.watch(singleCardPetInfoDirectProvider('deviceId'));
/// ```
final singleCardPetInfoDirectProvider = Provider.family<CardPetInfo?, String>((
  ref,
  deviceIdStr,
) {
  // ✅ 步驟 1：檢查裝置是否已連線
  final bluetoothState = ref.watch(bluetoothManagerProvider);
  final deviceId = bluetoothState.connectedDevices.keys.firstWhere(
    (id) => id.str == deviceIdStr,
    orElse: () => null as dynamic,
  );

  if (deviceId == null) {
    return null; // 裝置未連線
  }

  // ✅ 步驟 2：watch 該裝置的健康資料
  final healthData = ref.watch(multiDeviceHealthProvider(deviceId));

  // ✅ 步驟 3：轉換成 CardPetInfo
  return CardPetInfo(
    deviceId: deviceIdStr,
    cageNumber: _getCageNumberFromMac(deviceIdStr),
    name: _getDefaultName(deviceIdStr),
    petType: _getDefaultPetType(deviceIdStr),
    breed: _getDefaultBreed(deviceIdStr),
    age: _getDefaultAge(deviceIdStr),
    weight: _getDefaultWeight(deviceIdStr),
    imageUrl: null,
    hr: healthData.hr,
    br: healthData.br,
    temp: healthData.temp,
    step: healthData.step,
    isWearing: healthData.isWearing,
    updatedTime: DateTime.now(),
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// 🛠️ 臨時輔助函數（未來改用資料庫）
// ═══════════════════════════════════════════════════════════════════════════

/// 從 MAC 地址推算籠位編號
/// 臨時方案：用 MAC 最後一個 byte 取模
int _getCageNumberFromMac(String deviceId) {
  try {
    final lastByte = deviceId.split(':').last;
    final num = int.parse(lastByte, radix: 16);
    return (num % 20) + 1; // 支援最多 20 個籠位
  } catch (e) {
    return deviceId.hashCode % 20 + 1;
  }
}

/// 生成預設名稱
String _getDefaultName(String deviceId) {
  final cage = _getCageNumberFromMac(deviceId);
  final names = [
    '咪咪',
    '旺財',
    '小花',
    'Max',
    '橘子',
    '球球',
    '小白',
    '黑妞',
    '小虎',
    '豆豆',
    '妞妞',
    'Lucky',
    '妮妮',
    '小黑',
    '毛毛',
    '波比',
    'Coco',
    '小美',
    '阿財',
    '布丁',
  ];
  return names[(cage - 1) % names.length];
}

/// 生成預設寵物類型
String _getDefaultPetType(String deviceId) {
  final cage = _getCageNumberFromMac(deviceId);
  return cage % 2 == 0 ? '狗' : '貓';
}

/// 生成預設品種
String _getDefaultBreed(String deviceId) {
  final petType = _getDefaultPetType(deviceId);
  final cage = _getCageNumberFromMac(deviceId);

  if (petType == '貓') {
    final breeds = ['波斯貓', '英短', '橘貓', '美短', '暹羅貓', '布偶貓', '緬因貓', '俄羅斯藍貓'];
    return breeds[(cage - 1) % breeds.length];
  } else {
    final breeds = ['柴犬', '黃金獵犬', '貴賓犬', '哈士奇', '柯基', '邊牧', '薩摩耶', '拉布拉多'];
    return breeds[(cage - 1) % breeds.length];
  }
}

/// 生成預設年齡
int _getDefaultAge(String deviceId) {
  final cage = _getCageNumberFromMac(deviceId);
  return (cage % 8) + 1; // 1-8 歲
}

/// 生成預設體重
double _getDefaultWeight(String deviceId) {
  final petType = _getDefaultPetType(deviceId);
  final cage = _getCageNumberFromMac(deviceId);

  if (petType == '貓') {
    return 3.0 + (cage % 5).toDouble(); // 3-8 kg
  } else {
    return 8.0 + (cage % 8).toDouble() * 3; // 8-32 kg
  }
}
