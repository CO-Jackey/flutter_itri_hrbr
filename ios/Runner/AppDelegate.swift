import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // 註冊我們自訂的插件
    HealthCalculatePlugin.register(with: self.registrar(forPlugin: "HealthCalculatePlugin")!)
    
    // 註冊其他由 Flutter 套件自動產生的插件
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}