// package com.example.flutter_itri_hrbr;

// import androidx.annotation.NonNull;
// import io.flutter.embedding.android.FlutterActivity;
// import io.flutter.embedding.engine.FlutterEngine;
// import io.flutter.plugin.common.MethodChannel;

// // 確保這裡的 import 路徑是正確的，對應您 itriHRBR.jar 檔案中的套件結構
// import com.itri.healthcare.HealthCalculate;

// import java.util.HashMap;
// import java.util.Map;

// public class MainActivity extends FlutterActivity {
//     // 這個通道名稱必須和 Dart 中的完全一樣
//     private static final String CHANNEL = "com.example.flutter_itri_hrbr/health_calculate";
//     private HealthCalculate healthCalculator;

//     @Override
//     public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
//         super.configureFlutterEngine(flutterEngine);
//         new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
//                 .setMethodCallHandler(
//                         (call, result) -> {
//                             switch (call.method) {
//                                 case "initialize": // 這裡處理 "initialize" 方法
//                                     Integer type = call.argument("type");
//                                     if (type != null) {
//                                         healthCalculator = new HealthCalculate(type);
//                                         result.success(null);
//                                     } else {
//                                         result.error("INVALID_ARGUMENT", "Type is required.", null);
//                                     }
//                                     break;

//                                 case "splitPackage":
//                                     if (healthCalculator == null) {
//                                         result.error("NOT_INITIALIZED", "HealthCalculate is not initialized.", null);
//                                         return;
//                                     }
//                                     byte[] data = call.argument("data");
//                                     if (data != null) {
//                                         healthCalculator.splitPackage(data);
//                                         Map<String, Integer> healthData = new HashMap<>();
//                                         healthData.put("hr", healthCalculator.getHrValue());
//                                         healthData.put("br", healthCalculator.getBrValue());
//                                         healthData.put("gyroX", healthCalculator.getGyroValueX());
//                                         healthData.put("gyroY", healthCalculator.getGyroValueY());
//                                         healthData.put("gyroZ", healthCalculator.getGyroValueZ());
//                                         result.success(healthData);
//                                     } else {
//                                         result.error("INVALID_ARGUMENT", "Data is required.", null);
//                                     }
//                                     break;

//                                 case "dispose":
//                                     healthCalculator = null;
//                                     result.success(null);
//                                     break;

//                                 default:
//                                     result.notImplemented();
//                                     break;
//                             }
//                         }
//                 );
//     }
// }