import Flutter
import AVFoundation
import UIKit
import AVKit

/// 原生 AirPlay 路由插件。
///
/// 通过 [FlutterMethodChannel] 接收 Dart 端调用：
/// - `showAirPlayPicker`: 触发系统 AirPlay 选路面板。使用一个**常驻**的离屏
///   `AVRoutePickerView`（非 `isHidden`），递归查找其内部按钮后 `sendActions`
///   触发；找不到按钮时把 picker 移到屏幕中央供用户手点（兜底）。
/// - `isExternalPlaybackActive`: 查询 AirPlay 是否激活
/// - `getActiveRouteName`: 查询当前 AirPlay 路由名称
///
/// 通过 [FlutterEventChannel] 推送 AirPlay 路由状态变化（`AVAudioSession.routeChangeNotification`）。
class AirPlayPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private var persistentPicker: AVRoutePickerView?

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.meowtv.airplay",
            binaryMessenger: registrar.messenger()
        )
        let eventChannel = FlutterEventChannel(
            name: "com.meowtv.airplay/events",
            binaryMessenger: registrar.messenger()
        )
        let instance = AirPlayPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "showAirPlayPicker":
            showAirPlayPicker { ok in
                NSLog("[AirPlayPlugin] showAirPlayPicker result=\(ok)")
                result(ok)
            }
        case "isExternalPlaybackActive":
            result(isAirPlayRouteActive())
        case "getActiveRouteName":
            result(getActiveRouteName())
        case "disconnectAirPlay":
            let kicked = AirPlayVideoLayerPlugin.kickExternalPlaybackAllPlayers()
            NSLog("[AirPlayPlugin] disconnectAirPlay kicked=\(kicked)")
            result(kicked)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - AirPlay Picker

    private func showAirPlayPicker(completion: @escaping (Bool) -> Void) {
        ensureAudioSessionActive()

        guard let hostVC = AirPlayPlugin.topViewController() else {
            NSLog("[AirPlayPlugin] ERROR: 无法获取 root view controller")
            completion(false)
            return
        }

        // 懒创建常驻离屏 AVRoutePickerView（不随触发移除、不 isHidden）
        let picker: AVRoutePickerView = {
            if let existing = persistentPicker { return existing }
            let p = AVRoutePickerView(frame: CGRect(x: -10000, y: -10000, width: 44, height: 44))
            p.prioritizesVideoDevices = true
            p.isHidden = false
            hostVC.view.addSubview(p)
            persistentPicker = p
            NSLog("[AirPlayPlugin] 创建常驻离屏 picker")
            return p
        }()
        picker.isHidden = false
        picker.frame = CGRect(x: -10000, y: -10000, width: 44, height: 44)

        picker.setNeedsLayout()
        picker.layoutIfNeeded()

        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let button = AirPlayPlugin.findButton(in: picker) else {
                NSLog("[AirPlayPlugin] ERROR: 常驻 picker 内部按钮未找到，改屏幕中央手点兜底")
                // 兜底：移到屏幕中央显示，用户可直接手点
                if let hostVC = AirPlayPlugin.topViewController() {
                    DispatchQueue.main.async {
                        picker.frame = CGRect(
                            x: hostVC.view.bounds.midX - 100,
                            y: hostVC.view.bounds.midY - 100,
                            width: 200,
                            height: 200
                        )
                    }
                }
                completion(false)
                return
            }
            NSLog("[AirPlayPlugin] 触发常驻 picker 内部按钮")
            button.sendActions(for: .touchUpInside)
            completion(true)
        }
    }

    private func ensureAudioSessionActive() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
            try session.setActive(true, options: [])
            NSLog("[AirPlayPlugin] AVAudioSession 已激活: \(session.category.rawValue)")
        } catch {
            NSLog("[AirPlayPlugin] audio session setup failed: \(error)")
        }
    }

    private static func findButton(in view: UIView) -> UIButton? {
        for subview in view.subviews {
            if let button = subview as? UIButton { return button }
            if let found = findButton(in: subview) { return found }
        }
        return nil
    }

    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let keyWindow = scenes.flatMap { $0.windows }.first(where: { $0.isKeyWindow })
            ?? scenes.flatMap { $0.windows }.first
        guard var top = keyWindow?.rootViewController else { return nil }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    // MARK: - Route Monitoring

    private func isAirPlayRouteActive() -> Bool {
        // 镜像守卫：控制中心"屏幕镜像"（UIScreen.screens.count > 1）时不视为
        // app 内投屏激活，避免镜像 TV 端跟着变黑。仅在 app 内的 AirPlay 投屏下
        // 才走 cast overlay + 一键断开链路。
        if UIScreen.screens.count > 1 {
            return false
        }
        let session = AVAudioSession.sharedInstance()
        return session.currentRoute.outputs.contains { $0.portType == .airPlay }
    }

    private func getActiveRouteName() -> String? {
        let session = AVAudioSession.sharedInstance()
        return session.currentRoute.outputs
            .first(where: { $0.portType == .airPlay })?
            .portName
    }

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = eventSink
        eventSink(isAirPlayRouteActive())

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(routeChanged),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
        eventSink = nil
        return nil
    }

    @objc private func routeChanged(_ notification: Notification) {
        let isActive = isAirPlayRouteActive()
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(isActive)
        }
    }
}