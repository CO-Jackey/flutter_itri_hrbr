package com.example.flutter_itri_hrbr

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// !!! 重要 !!!
// 請確保下面的套件名稱是您在 .jar 檔案中找到的真實路徑！
import com.itri.multible.itriuwbhr32hz.HealthCalculate

import java.util.HashMap

class MainActivity: FlutterActivity() {
    // 在 Kotlin 中，我們使用 companion object 來定義靜態常數
    companion object {
        // 這個通道名稱必須和 Dart 中的完全一樣
        private const val CHANNEL = "com.example.flutter_itri_hrbr/health_calculate"
    }

    private var healthCalculator: HealthCalculate? = null // 持有 HealthCalculate 的實例

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            // `call` 包含了從 Flutter 傳來的請求，`result` 用於回傳結果
            call, result ->
            when (call.method) {
                "initialize" -> {
                    val type: Int? = call.argument("type")
                    if (type != null) {
                        healthCalculator = HealthCalculate(type)
                        result.success(null) // 表示成功
                    } else {
                        result.error("INVALID_ARGUMENT", "Type is required.", null)
                    }
                }
                
                "splitPackage" -> {
                    if (healthCalculator == null) {
                        result.error("NOT_INITIALIZED", "HealthCalculate is not initialized.", null)
                        return@setMethodCallHandler
                    }
                    val data: ByteArray? = call.argument("data")
                    if (data != null) {
                        // 呼叫 .jar 中的方法
                        healthCalculator!!.splitPackage(data)

                        // 準備回傳給 Flutter 的數據 - 使用 Any 類型來支援多種數據類型
                        val healthData = HashMap<String, Any>()
                        healthData["BRFiltered"] = healthCalculator!!.getBRFiltered().map { it.toDouble() } // 將數據轉換為 Double List
                        healthData["BRValue"] = healthCalculator!!.getBRValue()
                        healthData["FFTOut"] = healthCalculator!!.getFFTOut().map { it.toDouble() } // 將數據轉換為 Double List
                        // healthData["GyroThreshold"] = healthCalculator!!.getGyroThreshold() // 沒有這個方法，打開 jar 後也沒有，sdk文件有誤
                        healthData["GyroValueX"] = healthCalculator!!.getGyroValueX()
                        healthData["GyroValueY"] = healthCalculator!!.getGyroValueY()
                        healthData["GyroValueZ"] = healthCalculator!!.getGyroValueZ()
                        healthData["HRFiltered"] = healthCalculator!!.getHRFiltered().map { it.toDouble() } // 將數據轉換為 Double List
                        healthData["HRValue"] = healthCalculator!!.getHRValue()
                        healthData["HumValue"] = healthCalculator!!.getHumValue()
                        healthData["IsWearing"] = healthCalculator!!.getIsWearing()
                        healthData["PetPoseValue"] = healthCalculator!!.getPetPoseValue()
                        healthData["PowerValue"] = healthCalculator!!.getPowerValue()
                        healthData["RawData"] = healthCalculator!!.getRawData().map { it.toInt() } // 將數據轉換為 Integer List
                        // healthData["RRIValue"] = healthCalculator!!.getRRIValue() // 沒有這個方法，打開 jar 後也沒有，sdk文件有誤
                        healthData["StepValue"] = healthCalculator!!.getStepValue()
                        healthData["TempValue"] = healthCalculator!!.getTempValue()
                        healthData["TimeStamp"] = healthCalculator!!.getTimeStamp()
                        healthData["Type"] = healthCalculator!!.getType()

                        result.success(healthData) // 將包含所有數據的 Map 回傳
                    } else {
                        result.error("INVALID_ARGUMENT", "Data is required.", null)
                    }
                }
                // "splitPackage" -> {
                //     if (healthCalculator == null) {
                //         result.error("NOT_INITIALIZED", "HealthCalculate is not initialized.", null)
                //         return@setMethodCallHandler
                //     }
                //     val data: ByteArray? = call.argument("data")
                //     if (data != null) {
                //         println("Data size: ${data.size}")
                //         println("Data as hex: ${data.joinToString(" ") { "%02x".format(it) }}")
                //         println("Data as bytes: ${data.contentToString()}")
                //         // 呼叫 .jar 中的方法
                //         healthCalculator!!.splitPackage(data)
                //         // 印出 data 的不同格式



                //         // 準備回傳給 Flutter 的數據 - 使用 Any 類型來支援多種數據類型
                //         val healthData = HashMap<String, Any>()
                //         healthData["hr"] = healthCalculator!!.hrValue
                //         // healthData["br"] = healthCalculator!!.brValue
                //         healthData["br"] = healthCalculator!!.getBRValue() // 呼吸率函數值
                //         //ealthData["br_fun"] = healthCalculator!!.getBRValue()
                        	
                //         // healthData["gyroX"] = healthCalculator!!.gyroValueX
                //         healthData["gyroX"] = healthCalculator!!.getGyroValueX()
                //         healthData["gyroY"] = healthCalculator!!.getGyroValueY()
                //         healthData["gyroZ"] = healthCalculator!!.getGyroValueZ()
                //         // healthData["gyroY"] = healthCalculator!!.gyroValueY
                //         // healthData["gyroZ"] = healthCalculator!!.gyroValueZ

                //         healthData["petPose"] = healthCalculator!!.getPetPoseValue()

                //         // 保留 Float 精度
                //         healthData["temp"] = healthCalculator!!.tempValue
                //         healthData["hum"] = healthCalculator!!.humValue
                //         healthData["spO2"] = healthCalculator!!.spO2Value
                //         healthData["step"] = healthCalculator!!.stepValue
                //         healthData["power"] = healthCalculator!!.powerValue
                //         healthData["time"] = healthCalculator!!.timeStamp
                //         // healthData["hrFiltered"] = healthCalculator!!.hrFiltered
                //         // healthData["brFiltered"] = healthCalculator!!.brFiltered

                //         result.success(healthData) // 將包含所有數據的 Map 回傳
                //     } else {
                //         result.error("INVALID_ARGUMENT", "Data is required.", null)
                //     }
                // }
                "dispose" -> {
                    healthCalculator = null
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}