

import Foundation
import Flutter
import UIKit
import ITRIHRBR

public class HealthCalculatePlugin: NSObject, FlutterPlugin {
    private var healthCalculator: HRBRCalculate?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.example.flutter_itri_hrbr/health_calculate",
            binaryMessenger: registrar.messenger()
        )
        let instance = HealthCalculatePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            guard let args = call.arguments as? [String: Any],
                  let type = args["type"] as? Int else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Type is missing or not an Int.", details: nil))
                return
            }
            self.healthCalculator = HRBRCalculate(index: type)
            print("HealthCalculate Initialized with type \(type)")
            result("HealthCalculate Initialized with type \(type)")

        case "setType":
            guard self.healthCalculator != nil else {
                result(FlutterError(code: "NOT_INITIALIZED", message: "HealthCalculate is not initialized.", details: nil))
                return
            }
            guard let args = call.arguments as? [String: Any],
                  let type = args["type"] as? Int else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Type is missing or not an Int.", details: nil))
                return
            }
            self.healthCalculator!.setType(type: type)
            print("Type set to \(type)")
            result("Type set to \(type)")

        case "splitPackage":
            // --- 開始偵錯日誌 ---
            // print(">>> [SWIFT] Received 'splitPackage' call.")

            // 1. 檢查 healthCalculator 是否還存在
            guard let calculator = self.healthCalculator else {
                // print("!!! [SWIFT] ERROR: healthCalculator is nil! It was not initialized or was disposed.")
                result(FlutterError(code: "NOT_INITIALIZED", message: "HealthCalculate is not initialized.", details: nil))
                return
            }
            // print("--- [SWIFT] healthCalculator instance is valid.")

            // 2. 檢查傳入的參數
            guard let args = call.arguments as? [String: Any],
                  let data = args["data"] as? FlutterStandardTypedData else {
                // print("!!! [SWIFT] ERROR: Invalid arguments. 'data' is missing or not of type FlutterStandardTypedData.")
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Data is required and must be of type ByteArray.", details: nil))
                return
            }
            
            let byteArray: [UInt8] = [UInt8](data.data)

            // 🔥 新增：檢查資料長度
    if byteArray.isEmpty {
        print("!!! [SWIFT] ERROR: Received empty byte array, ignoring...")
        result(FlutterError(code: "EMPTY_DATA", message: "Received empty data array", details: nil))
        return
    }
    
    if byteArray.count < 17 {
        print("!!! [SWIFT] ERROR: Data too short (\(byteArray.count) bytes), minimum 17 bytes required")
        result(FlutterError(code: "INSUFFICIENT_DATA", message: "Data length \(byteArray.count) is less than required 17 bytes", details: nil))
        return
    }

            // 3. 印出收到的數據長度
             print("--- [SWIFT] Received data with length: \(byteArray.count) bytes.")

            // 4. 呼叫 SDK 的核心方法
//             print("--- [SWIFT] Calling ITRIHRBR.splitPackage()...")
            let status = calculator.splitPackage(data: byteArray)
            // print("<<< [SWIFT] ITRIHRBR.splitPackage() returned status: \(status).")
            // --- 結束偵錯日誌 ---
            
            // --- 註解 status 判斷是因為不斷回傳 -1 不清楚是否需要這層判斷 ---
            // if status >= 0 {
                let healthData = self.healthCalculator!.hrbrData
                let returnData: [String: Any?] = [
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
            // } else {
            //     result(FlutterError(code: "SDK_ERROR", message: "splitPackage returned error code: \(status)", details: nil))
            // }

        case "dispose":
            self.healthCalculator = nil
            result(nil)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
