import Foundation
import Flutter
import UIKit
import ITRIHRBR

public class HealthCalculatePlugin: NSObject, FlutterPlugin {
    // ═══════════════════════════════════════════════════════════════════════
    // 🔧 多裝置管理：改用 Dictionary 存儲每個裝置的 SDK 實例
    // ═══════════════════════════════════════════════════════════════════════
    private var healthCalculators: [String: HRBRCalculate] = [:]
    
    // ═══════════════════════════════════════════════════════════════════════
    // 📡 註冊 Method Channel
    // ═══════════════════════════════════════════════════════════════════════
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.example.flutter_itri_hrbr/health_calculate",
            binaryMessenger: registrar.messenger()
        )
        let instance = HealthCalculatePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 🎯 處理 Flutter 端的呼叫
    // ═══════════════════════════════════════════════════════════════════════
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
            
        // ───────────────────────────────────────────────────────────────────
        // 🏗️ initialize：初始化指定裝置的 SDK 實例
        // ───────────────────────────────────────────────────────────────────
        case "initialize":
            guard let args = call.arguments as? [String: Any],
                  let type = args["type"] as? Int,
                  let deviceId = args["deviceId"] as? String else {
                result(FlutterError(
                    code: "INVALID_ARGUMENT",
                    message: "Required arguments: 'type' (Int) and 'deviceId' (String)",
                    details: nil
                ))
                return
            }
            
            // ✅ 為該裝置建立新的 SDK 實例
            let calculator = HRBRCalculate(index: type)
            healthCalculators[deviceId] = calculator
            
            print("✅ [iOS] HealthCalculate initialized for device: \(deviceId) with type: \(type)")
            result("HealthCalculate initialized for device \(deviceId) with type \(type)")

        // ───────────────────────────────────────────────────────────────────
        // 🔧 setType：設定指定裝置的類型
        // ───────────────────────────────────────────────────────────────────
        case "setType":
            guard let args = call.arguments as? [String: Any],
                  let deviceId = args["deviceId"] as? String,
                  let type = args["type"] as? Int else {
                result(FlutterError(
                    code: "INVALID_ARGUMENT",
                    message: "Required arguments: 'deviceId' (String) and 'type' (Int)",
                    details: nil
                ))
                return
            }
            
            guard let calculator = healthCalculators[deviceId] else {
                result(FlutterError(
                    code: "NOT_INITIALIZED",
                    message: "HealthCalculate for device \(deviceId) is not initialized",
                    details: nil
                ))
                return
            }
            
            calculator.setType(type: type)
            print("✅ [iOS] Type set to \(type) for device: \(deviceId)")
            result("Type set to \(type) for device \(deviceId)")

        // ───────────────────────────────────────────────────────────────────
        // 📊 splitPackage：處理藍牙資料（核心方法）
        // ───────────────────────────────────────────────────────────────────
        case "splitPackage":
            // 🔍 步驟 1：驗證參數
            guard let args = call.arguments as? [String: Any],
                  let data = args["data"] as? FlutterStandardTypedData,
                  let deviceId = args["deviceId"] as? String else {
                result(FlutterError(
                    code: "INVALID_ARGUMENT",
                    message: "Required arguments: 'data' (ByteArray) and 'deviceId' (String)",
                    details: nil
                ))
                return
            }
            
            // 🔍 步驟 2：檢查該裝置的 SDK 實例是否存在
            guard let calculator = healthCalculators[deviceId] else {
                print("⚠️ [iOS] ERROR: HealthCalculate for device \(deviceId) is not initialized")
                result(FlutterError(
                    code: "NOT_INITIALIZED",
                    message: "HealthCalculate for device \(deviceId) is not initialized",
                    details: nil
                ))
                return
            }
            
            let byteArray: [UInt8] = [UInt8](data.data)

            // 🔍 步驟 3：驗證資料長度
            if byteArray.isEmpty {
                print("⚠️ [iOS] ERROR: Received empty byte array for device \(deviceId)")
                result(FlutterError(
                    code: "EMPTY_DATA",
                    message: "Received empty data array",
                    details: nil
                ))
                return
            }
            
            if byteArray.count < 17 {
                print("⚠️ [iOS] ERROR: Data too short for device \(deviceId) (\(byteArray.count) bytes, minimum 17)")
                result(FlutterError(
                    code: "INSUFFICIENT_DATA",
                    message: "Data length \(byteArray.count) is less than required 17 bytes",
                    details: nil
                ))
                return
            }

            // 📊 步驟 4：呼叫 SDK 處理資料
            // print("📡 [iOS] Processing \(byteArray.count) bytes for device: \(deviceId)")
            
            let startTime = Date()  // ⏱️ 效能計時開始
            let status = calculator.splitPackage(data: byteArray)
            let elapsedTime = Date().timeIntervalSince(startTime) * 1000  // 轉換為毫秒
            
            // print("⏱️ [iOS] SDK processing took: \(String(format: "%.2f", elapsedTime))ms for device: \(deviceId)")

            // 📤 步驟 5：封裝結果並回傳
            let healthData = calculator.hrbrData
            let returnData: [String: Any?] = [
                "deviceId": deviceId,  // ✅ 新增：回傳 deviceId
                "BRValue": healthData.BRValue,
                "HRValue": healthData.HRValue,
                "HumValue": healthData.HumValue,
                "IsWearing": healthData.isWearing,
                "PetPoseValue": healthData.PetPose,
                "PowerValue": healthData.PowerValue,
                "StepValue": healthData.StepValue,
                "TempValue": healthData.TempValue,
                "TimeStamp": healthData.TimeStamp,
                "GyroValueX": healthData.GyroValueX,
                "GyroValueY": healthData.GyroValueY,
                "GyroValueZ": healthData.GyroValueZ,
                "RRIValue": healthData.RRIValue,
                "BRFiltered": healthData.m_DrawBRRawdata,
                "FFTOut": healthData.fft_array,
                "HRFiltered": healthData.m_DrawHRRawdata,
                "RawData": healthData.m_HRdoubleRawdata.map { Int($0) }
            ]
            
            result(returnData)

        // ───────────────────────────────────────────────────────────────────
        // 🗑️ dispose：清理指定裝置或全部裝置
        // ───────────────────────────────────────────────────────────────────
        case "dispose":
            if let args = call.arguments as? [String: Any],
               let deviceId = args["deviceId"] as? String {
                // ✅ 清理指定裝置
                if healthCalculators.removeValue(forKey: deviceId) != nil {
                    print("🗑️ [iOS] Disposed HealthCalculate for device: \(deviceId)")
                    result("Disposed device \(deviceId)")
                } else {
                    print("⚠️ [iOS] Device \(deviceId) was not found in active calculators")
                    result("Device \(deviceId) not found")
                }
            } else {
                // ✅ 清理所有裝置
                let deviceCount = healthCalculators.count
                healthCalculators.removeAll()
                print("🗑️ [iOS] Disposed all \(deviceCount) HealthCalculate instances")
                result("Disposed all \(deviceCount) devices")
            }
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}