## 此 SDK 是專為 HealthCare 打造的解析器。憑藉此 SDK，能夠借助藍牙協定，從寵物電子項圈設備獲取寵物的生理資料並進行相關解析 。
## 本文分為兩個部分：藍牙與SDK使用。藍牙部分僅供參考，您可以直接選擇SDK部分進行相關操作。同時，為了提升閱讀體驗，本段文字已經進行了優化處理。

## 二.	藍牙處理事項與相關
# 1.	藍牙許可權處理
●	grantPermissions 申請許可權（僅供參考）
private void grantPermissions(String[] permissions) {//許可權名稱
    long[] checkPermission = new long[permissions.length];
    for (int i = 0; i < permissions.length; i++) {
    checkPermission[i] = ContextCompat.checkSelfPermission(this, permissions[i]);
    if (checkPermission[i] != PackageManager.PERMISSION_GRANTED) {
        ActivityCompat.requestPermissions(this, permissions, 1);
        break
    } }
}
●	許可權列表（僅供參考）
int currentApiVersion = Build.VERSION.SDK_INT;
if (currentApiVersion >= Build.VERSION_CODES.S) {
    grantPermissions(new String[]{
            Manifest.permission.BLUETOOTH_SCAN, //Android 12以上需要
            Manifest.permission.BLUETOOTH_CONNECT, //Android 12以上需要
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.WRITE_EXTERNAL_STORAGE,
            Manifest.permission.READ_EXTERNAL_STORAGE});
} else if (currentApiVersion >= Build.VERSION_CODES.Q) {
    grantPermissions(new String[]{
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.WRITE_EXTERNAL_STORAGE,
            Manifest.permission.READ_EXTERNAL_STORAGE});
} else {
    grantPermissions(new String[]{
            Manifest.permission.ACCESS_COARSE_LOCATION,
            Manifest.permission.WRITE_EXTERNAL_STORAGE,
            Manifest.permission.READ_EXTERNAL_STORAGE});
}
# 2.	初始化藍牙框架資訊（在Application裏進行初始化）
private void initBle() {
    Ble.options()//開啟配置
            .setLogBleEnable(false)//設置是否輸出列印藍牙日誌
            .setThrowBleException(false)//設置是否拋出藍牙異常
            .setLogTAG("AndroidBLE")//設置全局藍牙操作日誌TAG
            .setAutoConnect(true)//設置是否自動連接
            .setMaxConnectNum(6)//最大連接個數
            .setConnectFailedRetryCount(3) //重試次數
            .setConnectTimeout(10 * 1000L)//設置連接超時時長（默認10*1000 ms）
            .setScanPeriod(12 * 1000L)//設置掃描時長（默認10*1000 ms）
            .setUuidService(UUID.fromString("0000fff0-0000-1000-8000-00805f9b34fb"))//主服務的uuid
            .setUuidReadCha(UUID.fromString("0000fff4-0000-1000-8000-00805f9b34fb"))
            .setUuidNotifyCha(UUID.fromString("0000fff4-0000-1000-8000-00805f9b34fb"))
            .setUuidWriteCha(UUID.fromString("0000fff5-0000-1000-8000-00805f9b34fb"))//可寫特徵的uuid
            .setFactory(new BleFactory() {
@Override
                public BleDevice create(String address, String name) {
return super.create(address, name);
                }
            })
            .setBleWrapperCallback(new MyBleWrapperCallback())
            .create(getApplicationContext());
}
# 3.	初始化藍牙資訊
var ble = Ble.getInstance()
var bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
# 4.	藍牙多設備連接 以及回調狀態
ble?.connects(mBleList, connectCallback()) //藍牙列表 與結果監聽
private fun connectCallback(): BleConnectCallback<BleDevice?> {
return object : BleConnectCallback<BleDevice?>() {
override fun onConnectionChanged(device: BleDevice?) {
if (device?.isConnected == true) {
println("連接成功")
            }
        }

override fun onConnectFailed(device: BleDevice?, errorCode: Int) {
super.onConnectFailed(device, errorCode)
println("連接失敗")
        }

override fun onServicesDiscovered(device: BleDevice?, gatt: BluetoothGatt?) {
super.onServicesDiscovered(device, gatt)
        }


override fun onReady(device: BleDevice?) {
super.onReady(device)
println("準備完成")
        }
    }
}
# 5.	在準備完成之後開始註冊數據接收監聽
ble?.enableNotify(device, true, bleNotifyCallback())
---
private fun bleNotifyCallback(): BleNotifyCallback<BleDevice?> {
return object : BleNotifyCallback<BleDevice?>() {
override fun onChanged(
            device: BleDevice?,
            characteristic: BluetoothGattCharacteristic?
        ) {
println("數據接收處理")
        }

override fun onNotifySuccess(device: BleDevice?) {
super.onNotifySuccess(device)
println("註冊成功回調")
if (device != null) {
                initTime(device)
            }
        }
    }
}
# 6.	藍牙數據寫入操作
// 寫入設備內容 設備嗎+byte[]
ble?.write(device, byteArray, object : BleWriteCallback<BleDevice?>() {
override fun onWriteSuccess(
        device: BleDevice?,
        characteristic: BluetoothGattCharacteristic?
    ) {
        LogUtil.i(TAG, "數據寫入成功" + characteristic.())
    }

override fun onWriteFailed(device: BleDevice?, failedCode: Int) {
super.onWriteFailed(device, failedCode)
        LogUtil.i(TAG, "數據寫入成功$failedCode")
    }
})

## 三.	SDK初始化與解析注意
# 1.	支援版本
此SDK支援 Android 5.0 版本或以上
# 2.	安裝與初始化HealthCalculate 解析器
本地初始化健康數據解析器（HealthCalculate）後，藍牙返回的設備原始數據通過解析器轉化直觀的展現心率、呼吸等健康數據。
初始化HealthCalculate解析器
libs/itriHRBR.jar
初始化後首先APP應用程式必須向解析器寫入綁定的類別

//初始化類型 type: 0: human, 1: cat, 2: rabbit, 3: dog
mHealthCalculate = HealthCalculate(type)
mHealthCalculate.setBRThreshold(200)
# 3.	設置本地時間到設備
接下來APP應用程式將當前時間 (獲取到 12 位時間戳) 通過位移計算生成byteArray 格式下發到設備上。
此目的為確保APP與設備的時間同步,為後續的數據交換奠定精確無誤的基礎。

val date = Date()
// 獲取12位時間戳
val timestamp = date.time / 10
val byteArray = getTime(timestamp)
----
public static byte[] getTime(long timestamp) {
byte byte1 = (byte) (0xFF & timestamp);
byte byte2 = (byte) (0xFFL & (timestamp >> 8));
byte byte3 = (byte) (0xFFL & (timestamp >> 16));
byte byte4 = (byte) (0xFFL & (timestamp >> 24));
byte byte5 = (byte) (0xFFL & (timestamp >> 32));
byte[] byteArray = new byte[6];
    byteArray[0] = (byte) 0xfc;
    byteArray[1] = byte1;
    byteArray[2] = byte2;
    byteArray[3] = byte3;
    byteArray[4] = byte4;
    byteArray[5] = byte5;
return byteArray;
}

# 4.	數據格式解析
APP應用程式從設備接收到ByteArray格式的數據,把數據放入 SDK內 獲取相應的內容。
以下為SDK所獲取數據內容說明。
●	數據 header 區分歷史數據（250 0xFA）還是即時數據（255 0xFF）
連線狀況下,設備(如:電子項圈或其他相關產品)會傳送即時數據 (255 0xFF)到APP,但若APP與設備中斷連線時，設備會將數據儲存在設備端當作歷史數據,而當設備再次成功連線APP後,設備即會將歷史數據 (250 0xFA)傳送到APP應用程式。 
//數據填充
mHealthCalculate.splitPackage(ByteArray)
val header = data!![0].toInt() and 0xFF

●	陀螺儀數據  xyz
mHealthCalculate.gyroValueX.toString()
mHealthCalculate.gyroValueY.toString()
mHealthCalculate.gyroValueZ.toString()

●	心率數據獲取
mHealthCalculate.hrValue

●	呼吸數據獲取
mHealthCalculate.brValue

●	室溫數據獲取
mHealthCalculate.tempValue

●	濕度數據獲取
mHealthCalculate.humValue

●	RRI數據獲取
// RRI在SDK内部封装的名称为spO2 
mHealthCalculate.spO2Value

●	步數數據獲取
mHealthCalculate.stepValue

●	電量數據獲取
mHealthCalculate.powerValue

●	時間戳數據獲取
mHealthCalculate.timeStamp

●	心率波動團表數據獲取（320 Double[]）
// 心率的原始訊號,可展示心率即時波形圖。
mHealthCalculate.hrFiltered

●	呼吸波動團表數據獲取（320 Double[]）
// 呼吸的原始訊號，可展示呼吸即時波形圖。
mHealthCalculate.brFiltered