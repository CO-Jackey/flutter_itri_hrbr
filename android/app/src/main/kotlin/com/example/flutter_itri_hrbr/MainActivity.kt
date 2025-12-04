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

    // ✅ 新增：追蹤是否正在處理中
    private val processingFlags = mutableMapOf<String, Boolean>()

    // ✅ 新增：顯示 HealthCalculate 所有方法的函數
    private fun showHealthCalculateMethods() {
        try {
            val calculator = HealthCalculate(3)
            val clazz = calculator::class.java
            
            println("╔═══════════════════════════════════════════════════════════╗")
            println("║     HealthCalculate 類別方法一覽表                         ║")
            println("╚═══════════════════════════════════════════════════════════╝")
            
            // 取得該類別自己定義的方法（不含繼承）
            val ownMethods = clazz.declaredMethods.sortedBy { it.name }
            
            println("\n📌 該類別定義的方法 (${ownMethods.size} 個):")
            println("─".repeat(60))
            
            ownMethods.forEachIndexed { index, method ->
                val params = method.parameterTypes.joinToString(", ") { it.simpleName }
                val returnType = method.returnType.simpleName
                val modifier = when {
                    java.lang.reflect.Modifier.isPublic(method.modifiers) -> "public"
                    java.lang.reflect.Modifier.isPrivate(method.modifiers) -> "private"
                    java.lang.reflect.Modifier.isProtected(method.modifiers) -> "protected"
                    else -> "package"
                }
                println("${String.format("%2d", index + 1)}. [$modifier] ${method.name}($params) → $returnType")
            }
            
            // 取得公開方法
            val publicMethods = clazz.methods
                .filter { it.declaringClass == clazz }
                .sortedBy { it.name }
            
            println("\n📌 公開方法 (${publicMethods.size} 個):")
            println("─".repeat(60))
            
            publicMethods.forEachIndexed { index, method ->
                val params = method.parameterTypes.joinToString(", ") { it.simpleName }
                val returnType = method.returnType.simpleName
                println("${String.format("%2d", index + 1)}. ${method.name}($params) → $returnType")
            }
            
            // 取得所有欄位（Fields）
            val fields = clazz.declaredFields.sortedBy { it.name }
            
            println("\n📌 欄位 (${fields.size} 個):")
            println("─".repeat(60))
            
            fields.forEachIndexed { index, field ->
                val modifier = when {
                    java.lang.reflect.Modifier.isPublic(field.modifiers) -> "public"
                    java.lang.reflect.Modifier.isPrivate(field.modifiers) -> "private"
                    java.lang.reflect.Modifier.isProtected(field.modifiers) -> "protected"
                    else -> "package"
                }
                println("${String.format("%2d", index + 1)}. [$modifier] ${field.name}: ${field.type.simpleName}")
            }
            
            println("\n" + "═".repeat(60))
            
        } catch (e: Exception) {
            println("[KT] ❌ 錯誤: ${e.message}")
            e.printStackTrace()
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        
    
        // ✅ 快速顯示所有方法
        try {
            val calc = HealthCalculate(3)
            println("\n[KT] HealthCalculate 方法列表:")
            calc::class.java.methods
                .filter { it.declaringClass == calc::class.java }
                .sortedBy { it.name }
                .forEach { m ->
                    println("[KT] - ${m.name}(${m.parameterTypes.joinToString { it.simpleName }}) -> ${m.returnType.simpleName}")
                }
            println("")
        } catch (e: Exception) {
            println("[KT] Error: ${e.message}")
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            when (call.method) {
                // "initialize" -> {
                //     // ✅ 在這裡呼叫，App 啟動時就會顯示
                //     showHealthCalculateMethods()

                //     val type: Int? = call.argument("type")
                //     if (type != null) {
                //         try {
                //             println("[KT] Initialize with type: $type")
                //             result.success(null)
                //         } catch (e: Exception) {
                //             result.error("INIT_ERROR", e.message, null)
                //         }
                //     } else {
                //         result.error("INVALID_ARGUMENT", "Type is required.", null)
                //     }
                // }

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
                
                // "splitPackage" -> {
                //     // val data: ByteArray? = call.argument("data")
                //     // val deviceId: String? = call.argument("deviceId")


                //     // ✅ 明確宣告類型並加入 null 檢查
                //     val data = call.argument<ByteArray>("data")
                //     val deviceId = call.argument<String>("deviceId")

                //     // 🔥 驗證參數
                //     if (data == null) {
                //         result.error("INVALID_ARGUMENT", "Data is required.", null)
                //         return@setMethodCallHandler
                //     }
                    
                //     if (deviceId == null) {
                //         result.error("INVALID_ARGUMENT", "DeviceId is required.", null)
                //         return@setMethodCallHandler
                //     }

                //     // ✅ 在確認 deviceId 非 null 後再取得鎖
                //     val lock = synchronized(sdkLocks) {
                //         sdkLocks.getOrPut(deviceId) { Any() }
                //     }
                    
                //     // ✅ 檢查資料長度
                //     if (data.isEmpty()) {
                //         result.error("EMPTY_DATA", "Received empty data array", null)
                //         return@setMethodCallHandler
                //     }
                    
                //     if (data.size < 17) {
                //         result.error(
                //             "INSUFFICIENT_DATA", 
                //             "Data length ${data.size} is less than required 17 bytes", 
                //             null
                //         )
                //         return@setMethodCallHandler
                //     }
                    
                //     // ✅✅✅ 關鍵修正：在主線程建立 SDK 實例
                //     val calculator = synchronized(healthCalculators) {
                //         healthCalculators.getOrPut(deviceId) {
                //             println("[KT] 🆕 為設備 $deviceId 建立新的 HealthCalculate 實例（主線程）")
                //             HealthCalculate(3) // ← 在主線程建立，有 Looper
                //         }
                //     }
                    
                //     // ✅ 然後在背景線程執行運算（不阻塞主線程）
                //     sdkScope.launch(Dispatchers.Default) {
                //         try {
                //             val startTime = System.currentTimeMillis()
                            
                //             // ✅ 關鍵：用鎖確保同一設備的資料順序處理
                //             synchronized(lock) {
                //                 calculator.splitPackage(data)
                //             }
                            
                //             // 🔥 在背景線程執行 SDK 運算
                //             // calculator.splitPackage(data)
                            

                //             val elapsedTime = System.currentTimeMillis() - startTime
                //             println("[KT SDK] 設備 $deviceId 處理耗時: ${elapsedTime}ms")
                            
                //             // 收集該設備的結果
                //             val healthData = HashMap<String, Any>()
                //             println("[KT SDK] 設備 $deviceId 數據取得成功")
                            
                            
                //             // ✅ 回傳時帶上 deviceId
                //             healthData["deviceId"] = deviceId
                            
                //             // 從該設備專屬的 calculator 取得數據
                //             healthData["BRFiltered"] = calculator.getBRFiltered().map { it.toDouble() }
                //             healthData["BRValue"] = calculator.getBRValue()
                //             healthData["FFTOut"] = calculator.getFFTOut().map { it.toDouble() }
                //             healthData["GyroValueX"] = calculator.getGyroValueX()
                //             healthData["GyroValueY"] = calculator.getGyroValueY()
                //             healthData["GyroValueZ"] = calculator.getGyroValueZ()
                //             healthData["HRFiltered"] = calculator.getHRFiltered().map { it.toDouble() }
                //             healthData["HRValue"] = calculator.getHRValue()
                //             healthData["HumValue"] = calculator.getHumValue()
                //             healthData["IsWearing"] = calculator.getIsWearing()
                //             healthData["PetPoseValue"] = calculator.getPetPoseValue()
                //             healthData["PowerValue"] = calculator.getPowerValue()
                //             healthData["RawData"] = calculator.getRawData().map { it.toInt() }
                //             healthData["StepValue"] = calculator.getStepValue()
                //             healthData["TempValue"] = calculator.getTempValue()
                //             healthData["TimeStamp"] = calculator.getTimeStamp()
                //             healthData["Type"] = calculator.getType()
                //             healthData["SplitRawData"] = calculator.splitPackage().map { it.toInt() }
                            
                //             // 🔥 回到主執行緒回傳結果
                //             withContext(Dispatchers.Main) {
                //                 result.success(healthData)
                //             }
                            
                //         } catch (e: Exception) {
                //             println("[KT SDK] 設備 $deviceId 錯誤: ${e.message}")
                //             e.printStackTrace()
                            
                //             withContext(Dispatchers.Main) {
                //                 result.error("SDK_ERROR", e.message, null)
                //             }
                //         }
                //     }
                // }
                

                "splitPackage" -> {
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

                    // ✅ 取得或建立鎖（同步操作）
                    val lock = synchronized(sdkLocks) {
                        sdkLocks.getOrPut(deviceId) { Any() }
                    }

                    // ✅ 取得或建立 SDK 實例（在主線程，同步操作）
                    val calculator = synchronized(healthCalculators) {
                        healthCalculators.getOrPut(deviceId) {
                            println("[KT] 🆕 為設備 $deviceId 建立新的 HealthCalculate 實例")
                            HealthCalculate(3)
                        }
                    }

                    // ✅ 改成完全在主線程執行（避免跨線程問題）
                    try {
                        val startTime = System.currentTimeMillis()

                        // ✅ 同步執行 splitPackage（在主線程）
                        val splitResult: Int = synchronized(lock) {
                            calculator.splitPackage(data)
                        }

                        val elapsedTime = System.currentTimeMillis() - startTime
                        println("[KT SDK] 設備 $deviceId 處理耗時: ${elapsedTime}ms, 結果碼: $splitResult")

                        // ✅ 根據回傳值判斷是否成功
                        when (splitResult) {
                            -1 -> {
                                println("[KT SDK] ✅ 設備 $deviceId 資料解析成功")
                            }
                            101 -> {
                                println("[KT SDK] ⚠️ 設備 $deviceId ERROR_FIRST_BYTE: data[0] != 0xFF (實際: 0x${String.format("%02X", data[0])})")
                            }
                            102 -> {
                                println("[KT SDK] ⚠️ 設備 $deviceId ERROR_CHECKSUM: 校驗碼不正確")
                            }
                            else -> {
                                println("[KT SDK] ⚠️ 設備 $deviceId 未知結果碼: $splitResult")
                            }
                        }

                        // 收集結果
                        val healthData = HashMap<String, Any>()

                        // healthData["splitResult"] = splitResult
                        // healthData["splitResultMessage"] = when (splitResult) {
                        //     -1 -> "RESULT_OK"
                        //     101 -> "ERROR_FIRST_BYTE"
                        //     102 -> "ERROR_CHECKSUM"
                        //     else -> "UNKNOWN_ERROR"
                        // }

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

                        result.success(healthData)

                    } catch (e: Exception) {
                        println("[KT SDK] 設備 $deviceId 錯誤: ${e.message}")
                        e.printStackTrace()
                        result.error("SDK_ERROR", e.message, null)
                    }
                }

                // "dispose" -> {
                //     val deviceId: String? = call.argument("deviceId")
                    
                //     if (deviceId != null) {
                //         // ✅ 清理特定設備的 SDK 實例
                //         synchronized(healthCalculators) {
                //             healthCalculators.remove(deviceId)
                //             println("[KT] 🗑️ 已清理設備 $deviceId 的 HealthCalculate 實例")
                //         }
                //     } else {
                //         // 清理所有實例
                //         synchronized(healthCalculators) {
                //             healthCalculators.clear()
                //             println("[KT] 🗑️ 已清理所有 HealthCalculate 實例")
                //         }
                //     }
                    
                //     result.success(null)
                // }

                // "dispose" -> {
                //     val deviceId: String? = call.argument("deviceId")
                    
                //     if (deviceId != null) {
                //         // ✅ 清理特定設備的所有相關資源
                //         synchronized(healthCalculators) {
                //             healthCalculators.remove(deviceId)
                //             println("[KT] 🗑️ 已清理設備 $deviceId 的 HealthCalculate 實例")
                //         }
                //         synchronized(sdkLocks) {
                //             sdkLocks.remove(deviceId)
                //             println("[KT] 🗑️ 已清理設備 $deviceId 的鎖")
                //         }
                //         synchronized(processingFlags) {
                //             processingFlags.remove(deviceId)
                //         }
                //     } else {
                //         // 清理所有實例
                //         synchronized(healthCalculators) {
                //             healthCalculators.clear()
                //             println("[KT] 🗑️ 已清理所有 HealthCalculate 實例")
                //         }
                //         synchronized(sdkLocks) {
                //             sdkLocks.clear()
                //             println("[KT] 🗑️ 已清理所有鎖")
                //         }
                //         synchronized(processingFlags) {
                //             processingFlags.clear()
                //         }
                //     }
                    
                //     result.success(null)
                // }
                
                // ✅ 新增：重置特定設備（不用 dispose，直接重建）
                // "reset" -> {
                //     val deviceId: String? = call.argument("deviceId")
                    
                //     if (deviceId != null) {
                //         synchronized(healthCalculators) {
                //             // 移除舊的
                //             healthCalculators.remove(deviceId)
                //             // 建立新的
                //             healthCalculators[deviceId] = HealthCalculate(3)
                //             println("[KT] 🔄 已重置設備 $deviceId 的 HealthCalculate 實例")
                //         }
                //         result.success(true)
                //     } else {
                //         result.error("INVALID_ARGUMENT", "DeviceId is required for reset.", null)
                //     }
                // }

                // ✅ 新增：檢查 SDK 實例狀態
                "getStatus" -> {
                    val deviceId: String? = call.argument("deviceId")
                    
                    val status = HashMap<String, Any>()
                    
                    synchronized(healthCalculators) {
                        if (deviceId != null) {
                            status["hasInstance"] = healthCalculators.containsKey(deviceId)
                            status["deviceId"] = deviceId
                        } else {
                            status["totalInstances"] = healthCalculators.size
                            status["deviceIds"] = healthCalculators.keys.toList()
                        }
                    }
                    
                    result.success(status)
                }
                
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    // override fun onDestroy() {
    //     // ✅ 清理所有 SDK 實例
    //     synchronized(healthCalculators) {
    //         healthCalculators.clear()
    //     }
    //     sdkScope.cancel()
    //     super.onDestroy()
    // }

    override fun onDestroy() {
        // ✅ 清理所有資源
        synchronized(healthCalculators) {
            healthCalculators.clear()
        }
        synchronized(sdkLocks) {
            sdkLocks.clear()
        }
        synchronized(processingFlags) {
            processingFlags.clear()
        }
        sdkScope.cancel()
        super.onDestroy()
    }
}