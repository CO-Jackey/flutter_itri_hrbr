//
//  HRBRCalculate.swift
//  MultiBedSensor
//
//  Created by GeorgeTsao on 2021/6/22.
//


//import Foundation
import UIKit
import CoreBluetooth

public struct HRBRData {
    
    public var TimeStamp: Int64 = 0
    public var HRValue = 80
    public var BRValue = 20
    public var lastIndex = 0  //下面陣列中 目前計算到的陣列位置
    public var PowerValue = 100
    
    public var StepValue = 0
    public var RRIValue = 0
    public var HumValue = 0
    public var TempValue = 0.0
    public var GyroValueX = 0, GyroValueY = 0, GyroValueZ = 0
    public var isWearing = true
    public var PetPose = -1
    
    public var m_HRdoubleRawdata = [UInt16]()
    public var m_HRdoubleRawOut = [Double]()
    public var m_DrawHRRawdata = [Double]()
    
    public var m_BRdoubleRawdata = [UInt16]()
    public var m_BRdoubleRawOut = [Double]()
    public var m_DrawBRRawdata = [Double]()
    public var fft_array = [Double].init(repeating: 30000, count: 128)
}
public class HRBRCalculate {
    var last_algorithm_time:Int64!
//HR BR Init
    var InitBit_HR = [CInt].init(repeating: 1, count: 1) //Set InitBit true
    var InitBit_BR = [CInt].init(repeating: 1, count: 1) //Set InitBit true
    
    let RawdataCounter = 512

    
    var fft_array = [Double].init(repeating: 30000, count: 128)
    
    var RX_datacount = 0
    var HRBRCounter = 0
    
    var c_drawValueP2P_HR = 0
    var c_drawValueP2P_BR = 0
    
    var HRValue_median = [Int].init(repeating: 80, count: 5)
    var BRValue_median = [Int].init(repeating: 20, count: 5)
    
    public var hrbrData = HRBRData()
//HR BR Init End
    
//是否配戴 Init Start
    let wearingLimit = 32 * 3
    var NotWearingCount = 0 //沒有配戴的計數器 >=wearingLimit代表沒有配戴 <=wearingLimit代表有配戴
    var lastGyroValueX = -1
    var lastGyroValueY = -1
    var lastGyroValueZ = -1
//是否配戴 Init End
    
    let cpp_wrapper = CPP_Wrapper()
    var index = -1
    public init(index: Int) {
        self.index = index
        cpp_wrapper.setIndex(Int32(index))
        cpp_wrapper.printInfo()
        HandlerInit()
    }
    public func setType(type: Int) {
        if let type = Int32(exactly: type) {
            let lastHRType = cpp_wrapper.hr_getType()
            if lastHRType != type {
                cpp_wrapper.hr_setType(type)
                //type: 0: human, 1: cat, 2: rabbit, 3: dog
                if(type == 0) {
                    HRValue_median = [Int].init(repeating: 80, count: 5)
                } else if(type == 1) {
                    HRValue_median = [Int].init(repeating: 100, count: 5)
                }
                //兔子
                else if(type == 2 ) {
                    HRValue_median = [Int].init(repeating: 160, count: 5)
                }
                else if( type == 3) {
                    HRValue_median = [Int].init(repeating: 90, count: 5)
                } else {
                    HRValue_median = [Int].init(repeating: 80, count: 5)
                }
            }
            let lastBRType = cpp_wrapper.br_getType()
            if lastBRType != type {
                cpp_wrapper.br_setType(type)
            }
            
        }
    }
    
    /***
     * 設定呼吸閥值，過濾不是呼吸的雜訊
     * @param threshold 呼吸閥值, 預設200
     */
    public func setBRThreshold(threshold: Int) {
        if let threshold = Int32(exactly: threshold) {
            cpp_wrapper.br_setThreshold(threshold)
        }
    }
    
    private func HandlerInit() {
        last_algorithm_time = getCurrentMillis()
        
        //Init HRCaculate Parameter
        hrbrData.m_HRdoubleRawdata = [UInt16](repeating: 0, count: RawdataCounter)
        hrbrData.m_HRdoubleRawOut = [Double](repeating: 0, count: RawdataCounter)
        hrbrData.m_DrawHRRawdata = [Double](repeating: 0, count: RawdataCounter)
        
        hrbrData.m_BRdoubleRawdata = [UInt16](repeating: 0, count: RawdataCounter)
        hrbrData.m_BRdoubleRawOut = [Double](repeating: 0, count: RawdataCounter)
        hrbrData.m_DrawBRRawdata = [Double](repeating: 0, count: RawdataCounter)
        
        HRValue_median = [Int].init(repeating: 80, count: 5)
        BRValue_median = [Int].init(repeating: 20, count: 5)

        InitBit_HR[0] = 1
        InitBit_BR[0] = 1
        c_drawValueP2P_HR = 0
        c_drawValueP2P_BR = 0

        RX_datacount = 0
    }

    func log(_ logMessage: String, functionName: String = #function, fileName: String = #file) {
        print("\(String(describing: HRBRCalculate.self)), \(index): \(logMessage)")
    }
    func log(functionName: String = #function, fileName: String = #file) {
        print("\(String(describing: HRBRCalculate.self))-\(functionName)")
    }

    func Algorithm(_ end_index: Int) {

        HRBRCounter = end_index - 16
        if HRBRCounter < 0 {
            HRBRCounter = hrbrData.m_HRdoubleRawdata.count + HRBRCounter
        }
        var BR_rate = [Double].init(repeating: 0, count: 1)
        var BRRawOut = [Double].init(repeating: 0, count: 1)
        var HB_rate = [Double].init(repeating: 0, count: 1)
        var HBRawOut = [Double].init(repeating: 0, count: 1)
        for _ in 0 ..< 16 {
            //Caculate Br rate
            let br_rawdata = Int32(hrbrData.m_BRdoubleRawdata[HRBRCounter])
            cpp_wrapper.br_calculate(br_rawdata, initBit: &InitBit_BR, br_rate: &BR_rate, br_rawout: &BRRawOut)
            hrbrData.m_BRdoubleRawOut[HRBRCounter] = BRRawOut[0]
            hrbrData.m_DrawBRRawdata[HRBRCounter] = Double(br_rawdata)
            
            let hr_rawdata = Int32(hrbrData.m_HRdoubleRawdata[HRBRCounter])
            
            //Caculate Hr rate
            cpp_wrapper.hr_calculate(hr_rawdata, initBit: &InitBit_HR, hb_rate: &HB_rate, hb_rawout: &HBRawOut, fftArray: &hrbrData.fft_array)
            
            hrbrData.m_HRdoubleRawOut[HRBRCounter] = HBRawOut[0]
            hrbrData.m_DrawHRRawdata[HRBRCounter] = Double(hr_rawdata)
            
            c_drawValueP2P_BR += 1
            
            if (c_drawValueP2P_BR >= 32) {
                c_drawValueP2P_BR = 0
                for j in 0 ..< 4 {
                    BRValue_median[j] = BRValue_median[j + 1]
                }
                BRValue_median[4] = Int(BR_rate[0])
                hrbrData.BRValue = averageByPercentage(values: BRValue_median, percentage: 0.6)
            }
            c_drawValueP2P_HR += 1
            if (c_drawValueP2P_HR >= 32) {
                c_drawValueP2P_HR = 0;
                for k in 0 ..< 4 {
                    HRValue_median[k] = HRValue_median[k + 1]
                }
                HRValue_median[4] = Int(HB_rate[0])
                hrbrData.HRValue = averageByPercentage(values: HRValue_median, percentage: 0.6)
            }

            HRBRCounter = HRBRCounter + 1
            if (HRBRCounter >= 512) {
                HRBRCounter = 0
            }
        }
    }

    func averageByPercentage(values: [Int], percentage: Double) -> Int {
        // Ensure the percentage is valid.
        guard percentage >= 0 && percentage <= 1 else {
            fatalError("Percentage must be between 0 and 1")
        }

        // Copy and sort the array
        let copiedValues = values.sorted()

        let totalLength = values.count
        let middleLength = Int(Double(totalLength) * percentage)

        let start = (totalLength - middleLength) / 2
        let end = start + middleLength

        var sum = 0
        // Calculate the sum for the specified percentage
        for i in start..<end {
            sum += copiedValues[i]
        }

        // Calculate and round the average
        return Int(round(Double(sum) / Double(middleLength)))
    }

    func getCurrentMillis()->Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000)
    }
    func getIntFromTwoBytes(LowByte: UInt8, HighByte: UInt8) -> Int {
        let data = Data(_: [HighByte, LowByte])
        let decimalValue = data.reduce(0) { v, byte in
            return v << 8 | Int(byte)
        }
        return decimalValue
    }
    public func splitPackage(data: [UInt8]) -> Int {
        if ((data[0] & 0xFF) == 255 || (data[0] & 0xFF) == 250) {
            var data_size = data.count
            if (data_size == 17) {
                data_size = 16
            }
            
            // --------- CheckSum -------//
            var CheckSum = 0;
            for i in 0 ..< data_size {
                CheckSum += Int(data[i])
            }
            CheckSum = (CheckSum % 16);
            
            if (CheckSum == 0) {
                
                let timestamp_1 = Int64((data[ShareInfo.BLE_TIMESTAMP_1] & 0xFF))
                let timestamp_2 = Int64((data[ShareInfo.BLE_TIMESTAMP_2] & 0xFF))
                let timestamp_3 = Int64((data[ShareInfo.BLE_TIMESTAMP_3] & 0xFF))
                let timestamp_4 = Int64((data[ShareInfo.BLE_TIMESTAMP_4] & 0xFF))
                let timestamp_5 = Int64((data[ShareInfo.BLE_TIMESTAMP_5] & 0xFF))
                
                let timestamp = timestamp_1 + timestamp_2 * 256 + timestamp_3 * 256 * 256
                + timestamp_4 * 256 * 256 * 256 + timestamp_5 * 256 * 256 * 256 * 256
                
                hrbrData.TimeStamp = timestamp * 10
                
                let i_HR:Int = getIntFromTwoBytes(LowByte: data[ShareInfo.BLE_RAW_LOW], HighByte: data[ShareInfo.BLE_RAW_HIGH])
                hrbrData.m_HRdoubleRawdata[RX_datacount] = UInt16(i_HR);
                hrbrData.m_BRdoubleRawdata[RX_datacount] = UInt16(i_HR);
                
                let i_Step:Int = getIntFromTwoBytes(LowByte: data[ShareInfo.BLE_STEP_LOW], HighByte: data[ShareInfo.BLE_STEP_HIGH])
                hrbrData.StepValue = i_Step
                
                //                    print("LIB, i_Step = \(i_Step)")
                if(data_size == 19) {
                    hrbrData.GyroValueX = Int(data[ShareInfo.BLE_GYRO_X])
                    hrbrData.GyroValueY = Int(data[ShareInfo.BLE_GYRO_Y])
                    hrbrData.GyroValueZ = Int(data[ShareInfo.BLE_GYRO_Z])
                    //                    print("LIB, Gyro = (\(hrbrData.GyroValueX), \(hrbrData.GyroValueY), \(hrbrData.GyroValueZ))")
                    
                    var hum_value = Double(Int(data[ShareInfo.BLE_HUMIDITY]))
                    hum_value = (hum_value - 44) * (71 - 55) / (74 - 44) + 55
                    if(hum_value > 100) {
                        hum_value = 100
                    }
                    if(hum_value < 0) {
                        hum_value = 0
                    }
                    hrbrData.HumValue = Int(hum_value)
                    
                    var i_TEMP = Double(getIntFromTwoBytes(LowByte: data[ShareInfo.BLE_TEMPERATURE_LOW], HighByte: data[ShareInfo.BLE_TEMPERATURE_HIGH]))
                    i_TEMP = i_TEMP / 100
                    var temp_value = (i_TEMP - 32.2) * (28.1 - 26.3) / (35 - 32.2) + 26.3
                    
                    //                    print("LIB, temp_value = \(temp_value)")
                    if(temp_value > 100) {
                        temp_value = 100
                    }
                    if(temp_value < 0) {
                        temp_value = 0
                    }
                    hrbrData.TempValue = temp_value
                } else {
                    hrbrData.PetPose = Int(data[ShareInfo.BLE_PET_POSE])
                    hrbrData.HumValue = Int(data[ShareInfo.BLE_16_HUMIDITY])
                }
                
                hrbrData.isWearing = checkIsWearing(GyroX: hrbrData.GyroValueX, GyroY: hrbrData.GyroValueY, GyroZ: hrbrData.GyroValueZ);
                
                var powerValue = Int(data[ShareInfo.BLE_BATTERY])
                if powerValue > 100 {
                    powerValue = 100
                }
                hrbrData.PowerValue = powerValue
                
                
                let RRIValue = Int(data[ShareInfo.BLE_RRI])
                //                    print("LIB, spo2Value = \(spo2Value)")
                if RRIValue >= 20 {
                    hrbrData.RRIValue = RRIValue;
                } else if RRIValue == 0 {
                    hrbrData.RRIValue = 0
                }
                
                
                RX_datacount += 1
                
                if ((RX_datacount % 16) == 0) {
                    let current_time = getCurrentMillis()
                    let diff_time = current_time - last_algorithm_time
                    log(String(format: "diff Algorithm Time: %ld", diff_time))
                    last_algorithm_time = current_time
                    let end_index = RX_datacount
                    //如果送太快可能是錯誤資料 這半秒資料不取
                    if(diff_time > 200) {
                        DispatchQueue.main.async {
                            
                            self.Algorithm(end_index)
                            self.hrbrData.lastIndex = self.HRBRCounter
                        }
                    } else {
                        RX_datacount = RX_datacount - 16
                    }
                    
                }
                if (RX_datacount >= RawdataCounter) {
                    RX_datacount = 0
                }
            } else {
                return ShareInfo.ERROR_CHECKSUM
            }
        } else {
            return ShareInfo.ERROR_FIRST_BYTE
        }
        return ShareInfo.RESULT_OK
    }
    func checkIsWearing(GyroX: Int, GyroY: Int, GyroZ: Int) -> Bool {
        var isWearing = true //是否有配戴
//        log(String(format: "Gyro: (%d, %d, %d)", GyroX, GyroY, GyroZ))
        
        if abs(lastGyroValueX - GyroX) <= 5 && abs(lastGyroValueY - GyroY) <= 5 && abs(lastGyroValueZ - GyroZ) <= 5 {
            if hrbrData.BRValue == 0 {
                isWearing = false
            }
        }
        
        lastGyroValueX = GyroX
        lastGyroValueY = GyroY
        lastGyroValueZ = GyroZ
        
        if isWearing {
            NotWearingCount = 0
        } else {
            NotWearingCount = NotWearingCount + 1
            if NotWearingCount >= wearingLimit {
                NotWearingCount = wearingLimit
            }
        }
        if NotWearingCount >= wearingLimit {
            return false
        } else {
            return true
        }
    }
}
