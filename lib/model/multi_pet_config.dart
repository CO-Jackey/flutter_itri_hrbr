// PetConfig (靜態資訊)          HealthData (動態數據)
// ├─ 籠位編號                    ├─ 心率 (HR)
// ├─ 寵物名稱                    ├─ 呼吸率 (BR)
// ├─ 品種                        ├─ 體溫 (Temp)
// ├─ 年齡                        ├─ 是否佩戴
// └─ 體重                        └─ 其他 17+ 個欄位
//       ↓                             ↓
//    petConfigProvider    +    perDeviceHealthProvider
//                 ↓                    ↓
//               合併 (自動監聽兩者變化)
//                         ↓
//               cardPetInfoMapProvider
//                         ↓
//                   UI 顯示
// ```

// ---

// ## 📊 資料流程圖
// ```
// 你的藍芽流程：
// toggleNotify 監聽
//     ↓
// 藍芽數據到達
//     ↓
// 過濾驗證
//     ↓
// SDK 處理 (calc.splitPackage)
//     ↓
// 組裝 HealthData (完整的)
//     ↓
// 存入 perDeviceHealthProvider  ← 這裡已經有完整數據了！
//     ↓
// cardPetInfoMapProvider 自動監聽變化
//     ↓
// 合併 PetConfig + HealthData
//     ↓
// 生成 CardPetInfo
//     ↓
// UI 自動更新

/// 寵物基本資訊配置
/// 這些資訊應該從資料庫、API 或設定檔載入
class PetConfig {
  final int? cageNumber; // 籠位編號 (1-8)
  final String? name; // 寵物名稱
  final String? petType; // 寵物類型 (狗/貓)
  final String? breed; // 品種
  final int? age; // 年齡
  final double? weight; // 體重
  final String? imageUrl; // 照片 URL

  PetConfig({
    this.cageNumber,
    this.name,
    this.petType,
    this.breed,
    this.age,
    this.weight,
    this.imageUrl,
  });

  String? get petEmoji {
    if (petType != null && petType!.isNotEmpty) {
      if (petType!.contains('貓') || petType!.toLowerCase().contains('cat')) {
        return '🐱';
      } else if (petType!.contains('狗') ||
          petType!.toLowerCase().contains('dog')) {
        return '🐕';
      }
    } else {
      return null;
    }
    return '🐾';
  }

  Map<String, dynamic> toJson() {
    return {
      'cageNumber': cageNumber,
      'name': name,
      'petType': petType,
      'breed': breed,
      'age': age,
      'weight': weight,
      'imageUrl': imageUrl,
    };
  }

  factory PetConfig.fromJson(Map<String, dynamic> json) {
    return PetConfig(
      cageNumber: json['cageNumber'],
      name: json['name'],
      petType: json['petType'],
      breed: json['breed'],
      age: json['age'],
      weight: (json['weight'] as num).toDouble(),
      imageUrl: json['imageUrl'],
    );
  }
}
