class HealthData {
  final List<int> splitRawData;
  final int hr;
  final int br;
  final int gyroX;
  final int gyroY;
  final int gyroZ;
  final double temp;
  final double hum;
  final int spO2; // 目前對應您程式裡的 SPO2/RRI 變數
  final int step;
  final int power;
  final int time; // 原始 timestamp (ms/10 取回來的值)
  final List<dynamic> hrFiltered;
  final List<dynamic> brFiltered;
  final bool isWearing;
  final List<dynamic> rawData;
  final int type;
  final List<dynamic> fftOut;
  final int? petPose;

  const HealthData({
    this.splitRawData = const [],
    this.hr = 0,
    this.br = 0,
    this.gyroX = 0,
    this.gyroY = 0,
    this.gyroZ = 0,
    this.temp = 0,
    this.hum = 0,
    this.spO2 = 0,
    this.step = 0,
    this.power = 0,
    this.time = 0,
    this.hrFiltered = const [],
    this.brFiltered = const [],
    this.isWearing = false,
    this.rawData = const [],
    this.type = 0,
    this.fftOut = const [],
    this.petPose,
  });

  HealthData copyWith({
    List<int>? splitRawData,
    int? hr,
    int? br,
    int? gyroX,
    int? gyroY,
    int? gyroZ,
    double? temp,
    double? hum,
    int? spO2,
    int? step,
    int? power,
    int? time,
    List<dynamic>? hrFiltered,
    List<dynamic>? brFiltered,
    bool? isWearing,
    List<dynamic>? rawData,
    int? type,
    List<dynamic>? fftOut,
    int? petPose,
  }) {
    return HealthData(
      splitRawData: splitRawData ?? this.splitRawData,
      hr: hr ?? this.hr,
      br: br ?? this.br,
      gyroX: gyroX ?? this.gyroX,
      gyroY: gyroY ?? this.gyroY,
      gyroZ: gyroZ ?? this.gyroZ,
      temp: temp ?? this.temp,
      hum: hum ?? this.hum,
      spO2: spO2 ?? this.spO2,
      step: step ?? this.step,
      power: power ?? this.power,
      time: time ?? this.time,
      hrFiltered: hrFiltered ?? this.hrFiltered,
      brFiltered: brFiltered ?? this.brFiltered,
      isWearing: isWearing ?? this.isWearing,
      rawData: rawData ?? this.rawData,
      type: type ?? this.type,
      fftOut: fftOut ?? this.fftOut,
      petPose: petPose ?? this.petPose,
    );
  }

  Map<String, dynamic> toMap() => {
    'splitRawData': splitRawData,
    'hr': hr,
    'br': br,
    'gyroX': gyroX,
    'gyroY': gyroY,
    'gyroZ': gyroZ,
    'temp': temp,
    'hum': hum,
    'spO2': spO2,
    'step': step,
    'power': power,
    'time': time,
    'hrFiltered': hrFiltered,
    'brFiltered': brFiltered,
    'isWearing': isWearing,
    'rawData': rawData,
    'type': type,
    'fftOut': fftOut,
    'petPose': petPose,
  };
}
