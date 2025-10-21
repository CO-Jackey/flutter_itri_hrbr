enum DeviceStatus {
  connected, // 連線中
  warning, // 注意
  error, // 異常
  disconnected, // 離線
  empty, // 未使用
}

/// UI 專用的寵物資訊卡片資料模型
class CardPetInfo {
  final String deviceId; // 設備 ID
  final int? devicePower; // 設備電量
  final int? cageNumber; // 籠位編號
  final String? name; // 寵物名稱
  final String? petType; // 狗或貓
  final String? breed; // 寵物品種
  final int? age; // 年齡
  final double? weight; // 體重
  final String? imageUrl; // 寵物圖片

  // 來自 HealthData 的即時數據
  final int hr; // 心率
  final int br; // 呼吸率
  final double temp; // 溫度
  final bool isWearing; // 是否佩戴裝置
  final DateTime updatedTime; // 更新時間

  CardPetInfo({
    required this.deviceId,
    this.devicePower,
    this.cageNumber,
    this.name,
    this.petType,
    this.breed,
    this.age,
    this.weight,
    required this.hr,
    required this.br,
    required this.temp,
    required this.isWearing,
    required this.updatedTime,
    this.imageUrl,
  });

  // ==================== 健康狀態判斷 ====================

  bool get isHeartRateNormal => hr >= 60 && hr <= 120;
  bool get isHeartRateWarning =>
      (hr >= 120 && hr <= 140) || (hr >= 40 && hr < 60);
  bool get isHeartRateDanger => hr > 140 || hr < 40;
  // bool get isHeartRateDanger => false; // 先不判斷心率異常
  // bool get isHeartRateWarning => false;
  // bool get isHeartRateNormal => true;

  // ==================== 健康狀態判斷 ====================
  bool get isBreathRateNormal => br >= 20 && br <= 30;
  bool get isBreathRateWarning =>
      (br >= 15 && br < 20) || (br > 30 && br <= 35);
  bool get isBreathRateDanger => br < 15 || br > 50;
  // bool get isBreathRateDanger => false; // 先不判斷呼吸異常
  // bool get isBreathRateWarning => false;
  // bool get isBreathRateNormal => true;

  // ==================== 健康狀態判斷 ====================
  // bool get isTemperatureNormal => temp >= 37.5 && temp <= 39.2;
  // bool get isTemperatureWarning =>
  //     (temp >= 36.5 && temp < 37.5) || (temp > 39.2 && temp <= 40.0);
  // bool get isTemperatureDanger => temp < 36.5 || temp > 40.0;
  // bool get isTemperatureDanger => false; // 先不判斷體溫異常
  // bool get isTemperatureWarning => false;
  // bool get isTemperatureNormal => true;

  /// 自動計算設備狀態
  DeviceStatus get status {
    // 如果未佩戴，視為警告
    if (!isWearing) {
      return DeviceStatus.warning;
    }

    // 任一指標危險 → 異常
    if (isHeartRateDanger || isBreathRateDanger) {
      return DeviceStatus.error;
    }

    // 任一指標警告 → 注意
    if (isHeartRateWarning || isBreathRateWarning) {
      return DeviceStatus.warning;
    }

    // 全部正常 → 連線中
    return DeviceStatus.connected;
  }

  // String get petEmoji {
  //   if (petType.contains('貓') || petType.toLowerCase().contains('cat')) {
  //     return '🐱';
  //   } else if (petType.contains('狗') || petType.toLowerCase().contains('dog')) {
  //     return '🐕';
  //   }
  //   return '🐾';
  // }

  String get updateTimeText {
    final diff = DateTime.now().difference(updatedTime);
    if (diff.inSeconds < 5) return '剛才';
    if (diff.inSeconds < 60) return '${diff.inSeconds}秒前';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分鐘前';
    if (diff.inHours < 24) return '${diff.inHours}小時前';
    return '${diff.inDays}天前';
  }

  CardPetInfo copyWith({
    String? deviceId,
    int? devicePower,
    int? cageNumber,
    String? name,
    String? petType,
    String? breed,
    int? age,
    double? weight,
    int? hr,
    int? br,
    double? temp,
    bool? isWearing,
    DateTime? updatedTime,
    String? imageUrl,
  }) {
    return CardPetInfo(
      deviceId: deviceId ?? this.deviceId,
      devicePower: devicePower ?? this.devicePower,
      cageNumber: cageNumber ?? this.cageNumber,
      name: name ?? this.name,
      petType: petType ?? this.petType,
      breed: breed ?? this.breed,
      age: age ?? this.age,
      weight: weight ?? this.weight,
      hr: hr ?? this.hr,
      br: br ?? this.br,
      temp: temp ?? this.temp,
      isWearing: isWearing ?? this.isWearing,
      updatedTime: updatedTime ?? this.updatedTime,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  @override
  String toString() {
    return 'CardPetInfo(cage: $cageNumber, name: $name, status: $status, HR: $hr, BR: $br, Temp: ${temp.toStringAsFixed(1)})';
  }
}
