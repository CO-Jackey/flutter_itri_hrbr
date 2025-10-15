package com.example.flutter_itri_hrbr

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import com.itri.multible.itriuwbhr32hz.HealthCalculate

import kotlinx.coroutines.*

class MainActivity: FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.example.flutter_itri_hrbr/health_calculate"
    }

    // ✅ 使用 Map 管理多個設備的 SDK 實例
    private val healthCalculators = mutableMapOf<String, HealthCalculate>()
    
    private val sdkScope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    // 為每個設備建立獨立的鎖
    private val sdkLocks = mutableMapOf<String, Any>()

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            when (call.method) {
                "initialize" -> {
                    val type: Int? = call.argument("type")
                    if (type != null) {
                        try {
                            println("[KT] Initialize with type: $type")
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("INIT_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "Type is required.", null)
                    }
                }
                
                "splitPackage" -> {
                    // val data: ByteArray? = call.argument("data")
                    // val deviceId: String? = call.argument("deviceId")


                    // ✅ 明確宣告類型並加入 null 檢查
                    val data = call.argument<ByteArray>("data")
                    val deviceId = call.argument<String>("deviceId")

                    // 🔥 驗證參數
                    if (data == null) {
                        result.error("INVALID_ARGUMENT", "Data is required.", null)
                        return@setMethodCallHandler
                    }
                    
                    if (deviceId == null) {
                        result.error("INVALID_ARGUMENT", "DeviceId is required.", null)
                        return@setMethodCallHandler
                    }

                    // ✅ 在確認 deviceId 非 null 後再取得鎖
                    val lock = synchronized(sdkLocks) {
                        sdkLocks.getOrPut(deviceId) { Any() }
                    }
                    
                    // ✅ 檢查資料長度
                    if (data.isEmpty()) {
                        result.error("EMPTY_DATA", "Received empty data array", null)
                        return@setMethodCallHandler
                    }
                    
                    if (data.size < 17) {
                        result.error(
                            "INSUFFICIENT_DATA", 
                            "Data length ${data.size} is less than required 17 bytes", 
                            null
                        )
                        return@setMethodCallHandler
                    }
                    
                    // ✅✅✅ 關鍵修正：在主線程建立 SDK 實例
                    val calculator = synchronized(healthCalculators) {
                        healthCalculators.getOrPut(deviceId) {
                            println("[KT] 🆕 為設備 $deviceId 建立新的 HealthCalculate 實例（主線程）")
                            HealthCalculate(3) // ← 在主線程建立，有 Looper
                        }
                    }
                    
                    // ✅ 然後在背景線程執行運算（不阻塞主線程）
                    sdkScope.launch(Dispatchers.Default) {
                        try {
                            val startTime = System.currentTimeMillis()
                            
                            // ✅ 關鍵：用鎖確保同一設備的資料順序處理
                            synchronized(lock) {
                                calculator.splitPackage(data)
                            }
                            
                            // 🔥 在背景線程執行 SDK 運算
                            // calculator.splitPackage(data)
                            

                            val elapsedTime = System.currentTimeMillis() - startTime
                            println("[KT SDK] 設備 $deviceId 處理耗時: ${elapsedTime}ms")
                            
                            // 收集該設備的結果
                            val healthData = HashMap<String, Any>()
                            
                            // ✅ 回傳時帶上 deviceId
                            healthData["deviceId"] = deviceId
                            
                            // 從該設備專屬的 calculator 取得數據
                            healthData["BRFiltered"] = calculator.getBRFiltered().map { it.toDouble() }
                            healthData["BRValue"] = calculator.getBRValue()
                            healthData["FFTOut"] = calculator.getFFTOut().map { it.toDouble() }
                            healthData["GyroValueX"] = calculator.getGyroValueX()
                            healthData["GyroValueY"] = calculator.getGyroValueY()
                            healthData["GyroValueZ"] = calculator.getGyroValueZ()
                            healthData["HRFiltered"] = calculator.getHRFiltered().map { it.toDouble() }
                            healthData["HRValue"] = calculator.getHRValue()
                            healthData["HumValue"] = calculator.getHumValue()
                            healthData["IsWearing"] = calculator.getIsWearing()
                            healthData["PetPoseValue"] = calculator.getPetPoseValue()
                            healthData["PowerValue"] = calculator.getPowerValue()
                            healthData["RawData"] = calculator.getRawData().map { it.toInt() }
                            healthData["StepValue"] = calculator.getStepValue()
                            healthData["TempValue"] = calculator.getTempValue()
                            healthData["TimeStamp"] = calculator.getTimeStamp()
                            healthData["Type"] = calculator.getType()
                            
                            // 🔥 回到主執行緒回傳結果
                            withContext(Dispatchers.Main) {
                                result.success(healthData)
                            }
                            
                        } catch (e: Exception) {
                            println("[KT SDK] 設備 $deviceId 錯誤: ${e.message}")
                            e.printStackTrace()
                            
                            withContext(Dispatchers.Main) {
                                result.error("SDK_ERROR", e.message, null)
                            }
                        }
                    }
                }
                
                "dispose" -> {
                    val deviceId: String? = call.argument("deviceId")
                    
                    if (deviceId != null) {
                        // ✅ 清理特定設備的 SDK 實例
                        synchronized(healthCalculators) {
                            healthCalculators.remove(deviceId)
                            println("[KT] 🗑️ 已清理設備 $deviceId 的 HealthCalculate 實例")
                        }
                    } else {
                        // 清理所有實例
                        synchronized(healthCalculators) {
                            healthCalculators.clear()
                            println("[KT] 🗑️ 已清理所有 HealthCalculate 實例")
                        }
                    }
                    
                    result.success(null)
                }
                
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    override fun onDestroy() {
        // ✅ 清理所有 SDK 實例
        synchronized(healthCalculators) {
            healthCalculators.clear()
        }
        sdkScope.cancel()
        super.onDestroy()
    }
}