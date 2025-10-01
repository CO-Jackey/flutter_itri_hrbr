import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

class BluetoothService {
  // 這裡可以放置藍牙服務的相關邏輯

  // Future<bool> checkPermissions() async {
  //   // 檢查並請求藍牙相關權限

  //   final bluetoothScanStatus = await Permission.bluetoothScan.isGranted
  //       ? true
  //       : false;

  //   final bluetoothConnectStatus = await Permission.bluetoothConnect.isGranted
  //       ? true
  //       : false;

  //   final locationStatus = await Permission.location.isGranted
  //       ? true
  //       : false;

  //   return bluetoothScanStatus && bluetoothConnectStatus && locationStatus
  //       ? true
  //       : false;
  // }

  Future<bool> _requestPermissions() async {
    // 在 Android 31 (S) 以上版本，需要請求藍牙掃描和連接權限
    if (Platform.isAndroid) {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
      // 檢查是否所有權限都已授予
      if (statuses[Permission.bluetoothScan] == PermissionStatus.granted &&
          statuses[Permission.bluetoothConnect] == PermissionStatus.granted) {
        return true;
      }
    } else if (Platform.isIOS) {
      // iOS 會在 Info.plist 中自動處理，但我們也可以明確請求
      // permission_handler 在 iOS 上會對應 Info.plist 的設定來請求
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetooth,
        Permission.locationWhenInUse, // 掃描也可能需要位置權限
      ].request();
      if (statuses[Permission.bluetooth] == PermissionStatus.granted) {
        return true;
      }
    }
    return false; // 如果權限被拒絕，返回 false
  }
}
