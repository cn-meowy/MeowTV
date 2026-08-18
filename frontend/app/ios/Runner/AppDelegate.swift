import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 必须在 app 启动早期配置 AVAudioSession 为 .playback 并激活，
    // 否则 `AVRoutePickerView` 收到点击事件后系统选路面板会被静默吞掉
    // （这是 iOS 的强制要求：未激活的 audio session 无法触发 AirPlay 路由）。
    // 注：Flutter 的 video_player 插件不会自动配置此项，需手动设置。
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
      try session.setActive(true, options: [])
    } catch {
      NSLog("[AppDelegate] AVAudioSession 启动配置失败: \(error)")
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    let registry = engineBridge.pluginRegistry
    GeneratedPluginRegistrant.register(with: registry)
    if let registrar = registry.registrar(forPlugin: "SubtitlePlugin") {
      SubtitlePlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "CapturePlugin") {
      CapturePlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "AirPlayPlugin") {
      AirPlayPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "AirPlayVideoLayerPlugin") {
      AirPlayVideoLayerPlugin.register(with: registrar)
    }
  }
}
