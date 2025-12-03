// //
// //  HealthCalculatePlugin.swift
// //  Runner
// //
// //  Created by Jackey on 2025/11/17.
// //

// import Foundation
// import Flutter
// import UIKit
// import ITRIHRBR

// public class HealthCalculatePlugin: NSObject, FlutterPlugin {
//     // ═══════════════════════════════════════════════════════════════════════
//     // 🔧 多裝置管理：改用 Dictionary 存儲每個裝置的 SDK 實例
//     // ═══════════════════════════════════════════════════════════════════════
//     private var healthCalculators: [String: HRBRCalculate] = [:]
    
//     // ✅ 新增：記住預設類型（用於延遲初始化）
//     private var defaultType: Int = 3
    
//     // ═══════════════════════════════════════════════════════════════════════
//     // 📡 註冊 Method Channel
//     // ═══════════════════════════════════════════════════════════════════════
//     public static func register(with registrar: FlutterPluginRegistrar) {
//         let channel = FlutterMethodChannel(
//             name: "com.example.flutter_itri_hrbr/health_calculate",
//             binaryMessenger: registrar.messenger()
//         )
//         let instance = HealthCalculatePlugin()
//         registrar.addMethodCallDelegate(instance, channel: channel)
//     }

//     // ═══════════════════════════════════════════════════════════════════════
//     // 🎯 處理 Flutter 端的呼叫
//     // ═══════════════════════════════════════════════════════════════════════
//     public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
//         switch call.method {
            
//         // ───────────────────────────────────────────────────────────────────
//         // 🏗️ initialize：只記住類型，不建立實例（延遲初始化）
//         // ───────────────────────────────────────────────────────────────────
//         case "initialize":
//             guard let args = call.arguments as? [String: Any],
//                   let type = args["type"] as? Int else {
//                 result(FlutterError(
//                     code: "INVALID_ARGUMENT",
//                     message: "Required argument: 'type' (Int)",
//                     details: nil
//                 ))
//                 return
//             }
            
//             // ✅ 只記住類型，實際實例在 splitPackage 時才建立
//             defaultType = type
//             print("✅ [iOS] Default SDK type set to \(type)")
//             result("Default type set to \(type)")

//         // ───────────────────────────────────────────────────────────────────
//         // 🔧 setType：更新預設類型（並更新已存在的實例）
//         // ───────────────────────────────────────────────────────────────────
//         case "setType":
//             guard let args = call.arguments as? [String: Any],
//                   let type = args["type"] as? Int else {
//                 result(FlutterError(
//                     code: "INVALID_ARGUMENT",
//                     message: "Required argument: 'type' (Int)",
//                     details: nil
//                 ))
//                 return
//             }
            
//             // ✅ 更新預設類型
//             defaultType = type
            
//             // ✅ 如果有指定 deviceId，更新該裝置的類型
//             if let deviceId = args["deviceId"] as? String,
//                let calculator = healthCalculators[deviceId] {
//                 calculator.setType(type: type)
//                 print("✅ [iOS] Type updated to \(type) for device: \(deviceId)")
//                 result("Type set to \(type) for device \(deviceId)")
//             } else {
//                 // 更新所有已存在的實例
//                 for (deviceId, calculator) in healthCalculators {
//                     calculator.setType(type: type)
//                     print("✅ [iOS] Type updated to \(type) for device: \(deviceId)")
//                 }
//                 print("✅ [iOS] Default type updated to \(type) for all devices")
//                 result("Default type set to \(type)")
//             }

//         // ───────────────────────────────────────────────────────────────────
//         // 📊 splitPackage：處理藍牙資料（核心方法 + 延遲初始化）
//         // ───────────────────────────────────────────────────────────────────
//         case "splitPackage":
//             // 🔍 步驟 1：驗證參數
//             guard let args = call.arguments as? [String: Any],
//                   let data = args["data"] as? FlutterStandardTypedData,
//                   let deviceId = args["deviceId"] as? String else {
//                 result(FlutterError(
//                     code: "INVALID_ARGUMENT",
//                     message: "Required arguments: 'data' (ByteArray) and 'deviceId' (String)",
//                     details: nil
//                 ))
//                 return
//             }
            
//             // 🔥 步驟 2：延遲初始化（首次使用時才建立實例）
//             if healthCalculators[deviceId] == nil {
//                 let calculator = HRBRCalculate(index: defaultType)
//                 healthCalculators[deviceId] = calculator
//                 print("🆕 [iOS] Created SDK instance for device \(deviceId) with type \(defaultType)")
//             }
            
//             // 🔍 步驟 3：取得該裝置的 SDK 實例
//             guard let calculator = healthCalculators[deviceId] else {
//                 print("❌ [iOS] ERROR: Failed to create calculator for device \(deviceId)")
//                 result(FlutterError(
//                     code: "INIT_ERROR",
//                     message: "Failed to create SDK instance for device \(deviceId)",
//                     details: nil
//                 ))
//                 return
//             }
            
//             let byteArray: [UInt8] = [UInt8](data.data)

//             // 🔍 步驟 4：驗證資料長度
//             if byteArray.isEmpty {
//                 print("⚠️ [iOS] ERROR: Received empty byte array for device \(deviceId)")
//                 result(FlutterError(
//                     code: "EMPTY_DATA",
//                     message: "Received empty data array",
//                     details: nil
//                 ))
//                 return
//             }
            
//             if byteArray.count < 17 {
//                 print("⚠️ [iOS] ERROR: Data too short for device \(deviceId) (\(byteArray.count) bytes, minimum 17)")
//                 result(FlutterError(
//                     code: "INSUFFICIENT_DATA",
//                     message: "Data length \(byteArray.count) is less than required 17 bytes",
//                     details: nil
//                 ))
//                 return
//             }

//             // 📊 步驟 5：呼叫 SDK 處理資料
//             // let startTime = Date()  // ⏱️ 效能計時開始
//             let status = calculator.splitPackage(data: byteArray)
//             // let elapsedTime = Date().timeIntervalSince(startTime) * 1000  // 轉換為毫秒
            
//             // 可選：印出效能資訊
//             // print("⏱️ [iOS] SDK processing took: \(String(format: "%.2f", elapsedTime))ms for device: \(deviceId)")

//             // 📤 步驟 6：封裝結果並回傳
//             let healthData = calculator.hrbrData
//             let returnData: [String: Any?] = [
//                 "deviceId": deviceId,  // ✅ 回傳 deviceId 讓 Flutter 端驗證
//                 "BRValue": healthData.BRValue,
//                 "HRValue": healthData.HRValue,
//                 "HumValue": healthData.HumValue,
//                 "IsWearing": healthData.isWearing,
//                 "PetPoseValue": healthData.PetPose,
//                 "PowerValue": healthData.PowerValue,
//                 "StepValue": healthData.StepValue,
//                 "TempValue": healthData.TempValue,
//                 "TimeStamp": healthData.TimeStamp,
//                 "GyroValueX": healthData.GyroValueX,
//                 "GyroValueY": healthData.GyroValueY,
//                 "GyroValueZ": healthData.GyroValueZ,
//                 "RRIValue": healthData.RRIValue,
//                 "BRFiltered": healthData.m_DrawBRRawdata,
//                 "FFTOut": healthData.fft_array,
//                 "HRFiltered": healthData.m_DrawHRRawdata,
//                 "RawData": healthData.m_HRdoubleRawdata.map { Int($0) }
//             ]
            
//             result(returnData)

//         // ───────────────────────────────────────────────────────────────────
//         // 🗑️ dispose：清理指定裝置或全部裝置
//         // ───────────────────────────────────────────────────────────────────
//         case "dispose":
//             if let args = call.arguments as? [String: Any],
//                let deviceId = args["deviceId"] as? String {
//                 // ✅ 清理指定裝置
//                 if healthCalculators.removeValue(forKey: deviceId) != nil {
//                     print("🗑️ [iOS] Disposed SDK instance for device: \(deviceId)")
//                     result("Disposed device \(deviceId)")
//                 } else {
//                     print("⚠️ [iOS] Device \(deviceId) was not found in active calculators")
//                     result("Device \(deviceId) not found")
//                 }
//             } else {
//                 // ✅ 清理所有裝置
//                 let deviceCount = healthCalculators.count
//                 healthCalculators.removeAll()
//                 print("🗑️ [iOS] Disposed all \(deviceCount) SDK instances")
//                 result("Disposed all \(deviceCount) devices")
//             }
            
//         default:
//             result(FlutterMethodNotImplemented)
//         }
//     }
// }


//
//  HealthCalculatePlugin.swift
//  Runner
//
//  Created by Jackey on 2025/11/17.
//

import Foundation
import Flutter
import UIKit
import ITRIHRBR

public class HealthCalculatePlugin: NSObject, FlutterPlugin {
    // ═══════════════════════════════════════════════════════════════════════
    // 🔧 多裝置管理：改用 Dictionary 存儲每個裝置的 SDK 實例
    // ═══════════════════════════════════════════════════════════════════════
    private var healthCalculators: [String: HRBRCalculate] = [:]
    
    // ✅ 新增：記住預設類型（用於延遲初始化）
    private var defaultType: Int = 3
    
    // ✅ 新增：為每個設備建立獨立的處理狀態追蹤
    private var processingFlags: [String: Bool] = [:]
    
    // ✅ 新增：用於同步的鎖
    private let lock = NSLock()
    
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
        // 🏗️ initialize：只記住類型，不建立實例（延遲初始化）
        // ───────────────────────────────────────────────────────────────────
        case "initialize":
            guard let args = call.arguments as? [String: Any],
                  let type = args["type"] as? Int else {
                result(FlutterError(
                    code: "INVALID_ARGUMENT",
                    message: "Required argument: 'type' (Int)",
                    details: nil
                ))
                return
            }
            
            // ✅ 只記住類型，實際實例在 splitPackage 時才建立
            defaultType = type
            print("✅ [iOS] Default SDK type set to \(type)")
            result("Default type set to \(type)")

        // ───────────────────────────────────────────────────────────────────
        // 🔧 setType：更新預設類型（並更新已存在的實例）
        // ───────────────────────────────────────────────────────────────────
        case "setType":
            guard let args = call.arguments as? [String: Any],
                  let type = args["type"] as? Int else {
                result(FlutterError(
                    code: "INVALID_ARGUMENT",
                    message: "Required argument: 'type' (Int)",
                    details: nil
                ))
                return
            }
            
            // ✅ 更新預設類型
            defaultType = type
            
            lock.lock()
            defer { lock.unlock() }
            
            // ✅ 如果有指定 deviceId，更新該裝置的類型
            if let deviceId = args["deviceId"] as? String,
               let calculator = healthCalculators[deviceId] {
                calculator.setType(type: type)
                print("✅ [iOS] Type updated to \(type) for device: \(deviceId)")
                result("Type set to \(type) for device \(deviceId)")
            } else {
                // 更新所有已存在的實例
                for (deviceId, calculator) in healthCalculators {
                    calculator.setType(type: type)
                    print("✅ [iOS] Type updated to \(type) for device: \(deviceId)")
                }
                print("✅ [iOS] Default type updated to \(type) for all devices")
                result("Default type set to \(type)")
            }

        // ───────────────────────────────────────────────────────────────────
        // 📊 splitPackage：處理藍牙資料（核心方法 + 延遲初始化）
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
            
            let byteArray: [UInt8] = [UInt8](data.data)

            // 🔍 步驟 2：驗證資料長度
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
            
            // 🔥 步驟 3：使用鎖確保線程安全的延遲初始化
            lock.lock()
            
            if healthCalculators[deviceId] == nil {
                let calculator = HRBRCalculate(index: defaultType)
                healthCalculators[deviceId] = calculator
                print("🆕 [iOS] Created SDK instance for device \(deviceId) with type \(defaultType)")
            }
            
            guard let calculator = healthCalculators[deviceId] else {
                lock.unlock()
                print("❌ [iOS] ERROR: Failed to create calculator for device \(deviceId)")
                result(FlutterError(
                    code: "INIT_ERROR",
                    message: "Failed to create SDK instance for device \(deviceId)",
                    details: nil
                ))
                return
            }
            
            lock.unlock()

            // 📊 步驟 4：呼叫 SDK 處理資料
            let startTime = Date()
            let splitResult = calculator.splitPackage(data: byteArray)
            let elapsedTime = Date().timeIntervalSince(startTime) * 1000
            
            print("[iOS SDK] 設備 \(deviceId) 處理耗時: \(String(format: "%.2f", elapsedTime))ms, 結果碼: \(splitResult)")
            
            // ✅ 根據回傳值判斷是否成功（與 Kotlin 一致）
            switch splitResult {
            case -1:
                print("[iOS SDK] ✅ 設備 \(deviceId) 資料解析成功")
            case 101:
                print("[iOS SDK] ⚠️ 設備 \(deviceId) ERROR_FIRST_BYTE: data[0] != 0xFF (實際: 0x\(String(format: "%02X", byteArray[0])))")
            case 102:
                print("[iOS SDK] ⚠️ 設備 \(deviceId) ERROR_CHECKSUM: 校驗碼不正確")
            default:
                print("[iOS SDK] ⚠️ 設備 \(deviceId) 未知結果碼: \(splitResult)")
            }

            // 📤 步驟 5：封裝結果並回傳
            let healthData = calculator.hrbrData
            let returnData: [String: Any?] = [
                "deviceId": deviceId,
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
            lock.lock()
            defer { lock.unlock() }
            
            if let args = call.arguments as? [String: Any],
               let deviceId = args["deviceId"] as? String {
                // ✅ 清理特定設備的所有相關資源
                if healthCalculators.removeValue(forKey: deviceId) != nil {
                    print("🗑️ [iOS] 已清理設備 \(deviceId) 的 HealthCalculate 實例")
                } else {
                    print("⚠️ [iOS] Device \(deviceId) was not found in active calculators")
                }
                
                // ✅ 清理處理狀態
                processingFlags.removeValue(forKey: deviceId)
                print("🗑️ [iOS] 已清理設備 \(deviceId) 的處理狀態")
                
                result("Disposed device \(deviceId)")
            } else {
                // ✅ 清理所有裝置
                let deviceCount = healthCalculators.count
                healthCalculators.removeAll()
                processingFlags.removeAll()
                print("🗑️ [iOS] 已清理所有 \(deviceCount) 個 HealthCalculate 實例")
                result("Disposed all \(deviceCount) devices")
            }
            
        // ───────────────────────────────────────────────────────────────────
        // 🔄 reset：重置特定設備（不用 dispose，直接重建）
        // ───────────────────────────────────────────────────────────────────
        case "reset":
            guard let args = call.arguments as? [String: Any],
                  let deviceId = args["deviceId"] as? String else {
                result(FlutterError(
                    code: "INVALID_ARGUMENT",
                    message: "DeviceId is required for reset.",
                    details: nil
                ))
                return
            }
            
            lock.lock()
            defer { lock.unlock() }
            
            // 移除舊的
            healthCalculators.removeValue(forKey: deviceId)
            
            // 建立新的
            healthCalculators[deviceId] = HRBRCalculate(index: defaultType)
            
            // 清理處理狀態
            processingFlags.removeValue(forKey: deviceId)
            
            print("🔄 [iOS] 已重置設備 \(deviceId) 的 HealthCalculate 實例")
            result(true)
            
        // ───────────────────────────────────────────────────────────────────
        // 📊 getStatus：檢查 SDK 實例狀態
        // ───────────────────────────────────────────────────────────────────
        case "getStatus":
            lock.lock()
            defer { lock.unlock() }
            
            var status: [String: Any] = [:]
            
            if let args = call.arguments as? [String: Any],
               let deviceId = args["deviceId"] as? String {
                // 查詢特定設備
                status["hasInstance"] = healthCalculators[deviceId] != nil
                status["deviceId"] = deviceId
                status["isProcessing"] = processingFlags[deviceId] ?? false
            } else {
                // 查詢所有設備
                status["totalInstances"] = healthCalculators.count
                status["deviceIds"] = Array(healthCalculators.keys)
                status["processingDevices"] = processingFlags.filter { $0.value }.map { $0.key }
            }
            
            result(status)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}