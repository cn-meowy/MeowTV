import Flutter
import AVFoundation
import UIKit

/// 永远不参与命中测试的 AVPlayerLayer 子类。
///
/// 用于 AirPlay 视频交接辅助 layer：必须存在于视图层级中以满足 iOS 渲染侧
/// 条件，但不参与任何触摸事件路由——即使用户手势命中其 frame 区域，也绝不
/// 拦截事件（`hitTest` 始终返回 `nil`，UIKit 会自动跳过并向下查找）。
final class NonHitTestablePlayerLayer: AVPlayerLayer {
    override func hitTest(_ p: CGPoint) -> CALayer? { nil }
}

/// 承载 AirPlay 辅助 AVPlayerLayer 的容器视图。
///
/// 插入 UIWindow 子视图栈底（`window.insertSubview(_, at: 0)`），被根视图
/// （Flutter 画面）整体遮挡；不参与命中测试。`layoutSubviews` 在旋转/分屏
/// 后自动重算 layer 的 frame。
final class AirPlayLayerHostView: UIView {
    let playerLayer: NonHitTestablePlayerLayer
    private let aspectRatio: CGFloat

    init(playerLayer: NonHitTestablePlayerLayer, aspectRatio: CGFloat) {
        self.playerLayer = playerLayer
        self.aspectRatio = aspectRatio
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let height = max(width / aspectRatio, 1.0)
        let y = max((bounds.height - height) / 2.0, 0.0)
        playerLayer.frame = CGRect(x: 0, y: y, width: width, height: height)
    }
}

/// 原生 AirPlay 视频 Layer 桥接插件。
///
/// **目的**：iOS 的 `video_player_avfoundation` 默认使用纹理渲染，附挂的
/// `AVPlayerLayer` frame 为 0、不可见，导致 AirPlay 视频交接路径在渲染侧
/// 不满足条件——外部接收端拿到元数据但等待视频流。本插件在 AirPlay 路由
/// 激活期间，将一个 `NonHitTestablePlayerLayer`（使用同一个 `AVPlayer`）
/// 装入 `AirPlayLayerHostView` 后插入 **UIWindow 子视图 index 0**，被根
/// 视图（Flutter 画面）整体遮挡；容器 frame 仍非零、layer 仍挂在 window
/// 层级中、player 处于播放状态，满足 AirPlay 视频交接的渲染侧条件，同时
/// 不遮挡 Flutter 视频纹理与控件（容器 `isUserInteractionEnabled = false`
/// + layer `hitTest -> nil` 双保险）。
///
/// **方法**：
/// - `attachLayerWithPlayerKey` / `attachLayer`：在视图层级中查找既有
///   不可见 `AVPlayerLayer`（由 `video_player_avfoundation` 创建），取出
///   其 `AVPlayer`，再创建一个 `AVPlayerLayer` 装入容器视图挂到 window
///   index 0。
/// - `detachAllLayers`：移除并释放插件挂入的所有容器（layer 随容器一并
///   释放，KVO 同步 invalidate）。
///
/// 路由激活时挂入、断开时移除；对非 AirPlay 播放无影响。
class AirPlayVideoLayerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?

    /// 插件挂入的所有容器视图（每个承载一个 AirPlay 辅助 AVPlayerLayer）。
    /// 顺序：textureId/playerKey -> AirPlayLayerHostView。
    private var attachedHosts: [String: AirPlayLayerHostView] = [:]

    /// 每个 layer 关联的 KVO 观察者（用于 `isExternalPlaybackActive` 推送）。
    private var observations: [AVPlayerLayer: NSKeyValueObservation] = [:]

    /// 在 `kickExternalPlaybackAllPlayers` 中被踢掉外部播放的 player 集合。
    /// 路由离开 airPlay 或 detachAllLayers 时恢复 `allowsExternalPlayback = true`，
    /// 避免后续 AirPlay 无法再投。**绝不**在 kick 后立即恢复——仍激活的路由会
    /// 立即把视频重新拉回 TV。
    private static var kickedPlayers: [AVPlayer] = []

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.meowtv.airplay_video_layer",
            binaryMessenger: registrar.messenger()
        )
        let eventChannel = FlutterEventChannel(
            name: "com.meowtv.airplay_video_layer/events",
            binaryMessenger: registrar.messenger()
        )
        let instance = AirPlayVideoLayerPlugin()
        AirPlayVideoLayerPlugin.sharedInstance = instance
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
        // 注册全局路由监听：路由离开 airPlay 时恢复被踢 player 的外部播放能力。
        AirPlayVideoLayerPlugin.registerRouteRestoreObserver()
    }

    // MARK: - 一键断开（外部播放踢出）+ 恢复

    /// 全局路由监听是否已注册。
    private static var routeRestoreRegistered = false

    /// 注册一次性 `AVAudioSession.routeChangeNotification` 监听：路由不再是
    /// airPlay 时把 `kickedPlayers` 全部恢复 `allowsExternalPlayback = true`。
    /// 幂等，可被多次调用。
    static func registerRouteRestoreObserver() {
        guard !routeRestoreRegistered else { return }
        routeRestoreRegistered = true
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            let session = AVAudioSession.sharedInstance()
            let stillAirPlay = session.currentRoute.outputs.contains { $0.portType == .airPlay }
            if !stillAirPlay {
                AirPlayVideoLayerPlugin.restoreKickedPlayers(reason: "route_left_airplay")
            }
        }
    }

    /// 把被踢掉的 player 恢复 `allowsExternalPlayback = true`，并清空数组。
    /// 调用方：路由监听回调、`detachAllLayers`、`kickExternalPlaybackAllPlayers`
    /// 在调用方传入 force=true 时也会清（避免重复挂载时残留）。
    static func restoreKickedPlayers(reason: String) {
        guard !kickedPlayers.isEmpty else { return }
        let count = kickedPlayers.count
        for p in kickedPlayers {
            // 解包已被踢掉的 player（可能已被释放，需 try/catch KVO 副作用）
            if p.allowsExternalPlayback == false {
                p.allowsExternalPlayback = true
            }
        }
        kickedPlayers.removeAll()
        NSLog("[AirPlayVideoLayerPlugin] 恢复 kickedPlayers count=\(count), reason=\(reason)")
    }

    /// 把所有已知 player（含插件挂入的 `attachedHosts` 中 player + 视图层级
    /// 递归扫描得到的 AVPlayerLayer.player）的 `allowsExternalPlayback` 设为 false，
    /// 加入 `kickedPlayers`，用于一键断开。
    ///
    /// 返回是否成功踢掉至少一个 player（false 表示当前没有任何 player，调用方
    /// 应走 picker 兜底）。
    static func kickExternalPlaybackAllPlayers() -> Bool {
        var allPlayers: [AVPlayer] = []
        var seen: Set<ObjectIdentifier> = []
        if let instance = AirPlayVideoLayerPlugin.sharedInstance {
            for host in instance.attachedHosts.values {
                if let p = host.playerLayer.player, seen.insert(ObjectIdentifier(p)).inserted {
                    allPlayers.append(p)
                }
            }
        }
        if let window = AirPlayVideoLayerPlugin.keyWindow() {
            for p in AirPlayVideoLayerPlugin.collectPlayers(in: window.layer) {
                if seen.insert(ObjectIdentifier(p)).inserted {
                    allPlayers.append(p)
                }
            }
        }
        guard !allPlayers.isEmpty else {
            NSLog("[AirPlayVideoLayerPlugin] kickExternalPlaybackAllPlayers: 未找到任何 player")
            return false
        }
        var kickedCount = 0
        for p in allPlayers {
            if p.allowsExternalPlayback {
                p.allowsExternalPlayback = false
                kickedPlayers.append(p)
                kickedCount += 1
            }
        }
        NSLog("[AirPlayVideoLayerPlugin] kickExternalPlaybackAllPlayers: 总候选=\(allPlayers.count), 实际踢掉=\(kickedCount)")
        return kickedCount > 0
    }

    /// 全局共享实例引用（由 register 创建，kick 路径使用）。
    /// Swift 静态初始化顺序敏感——register 早于任何 kick 调用，运行时安全。
    private static var sharedInstance: AirPlayVideoLayerPlugin?
    static var shared: AirPlayVideoLayerPlugin? { sharedInstance }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "attachLayer":
            let args = call.arguments as? [String: Any]
            let aspectRatio = (args?["aspectRatio"] as? NSNumber)?.doubleValue ?? 16.0 / 9.0
            attachLayer(aspectRatio: aspectRatio, result: result)
        case "attachLayerWithPlayerKey":
            let args = call.arguments as? [String: Any]
            let playerKey = (args?["playerKey"] as? NSNumber)?.intValue ?? -1
            let aspectRatio = (args?["aspectRatio"] as? NSNumber)?.doubleValue ?? 16.0 / 9.0
            attachLayerWithPlayerKey(playerKey: playerKey, aspectRatio: aspectRatio, result: result)
        case "detachAllLayers":
            detachAllLayers()
            result(nil)
        case "isLayerAttached":
            result(!attachedHosts.isEmpty)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Attach Layer

    /// 从视图层级查找既有不可见 `AVPlayerLayer` 的 `AVPlayer`，挂入新可见 layer。
    private func attachLayer(aspectRatio: Double, result: @escaping FlutterResult) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                result(false)
                return
            }

            guard let hostVC = AirPlayVideoLayerPlugin.topViewController() else {
                NSLog("[AirPlayVideoLayerPlugin] ERROR: 无法获取 root view controller")
                result(false)
                return
            }

            guard let existingPlayer = AirPlayVideoLayerPlugin.findFirstPlayer(
                in: hostVC.view.layer
            ) else {
                NSLog("[AirPlayVideoLayerPlugin] ERROR: 未找到既有 AVPlayerLayer")
                result(false)
                return
            }

            let key = "auto-\(existingPlayer.hashValue)"
            self.createAndAttachLayer(
                player: existingPlayer,
                key: key,
                aspectRatio: aspectRatio
            )
            result(true)
        }
    }

    /// 根据 Dart 侧传入的 playerKey（对应 video_player_avfoundation 的
    /// `playerId` / `textureId`）从视图层级匹配最合适的 `AVPlayerLayer`。
    ///
    /// **退路**：若 playerKey 不匹配（极少见：textureId 与 playerId 不同，
    /// 或 key 解析失败），自动回退为 `attachLayer`（最近一个）。
    private func attachLayerWithPlayerKey(
        playerKey: Int,
        aspectRatio: Double,
        result: @escaping FlutterResult
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                result(false)
                return
            }

            guard let hostVC = AirPlayVideoLayerPlugin.topViewController() else {
                NSLog("[AirPlayVideoLayerPlugin] ERROR: 无法获取 root view controller")
                result(false)
                return
            }

            let players = AirPlayVideoLayerPlugin.collectPlayers(in: hostVC.view.layer)
            // 选取优先级：当前正在播放的（currentItem.status == readyToPlay 且 isPlaybackLikelyToKeepUp）
            let chosenPlayer = players.first(where: { p in
                guard let item = p.currentItem else { return false }
                return item.status == .readyToPlay
            }) ?? players.first

            guard let player = chosenPlayer else {
                NSLog("[AirPlayVideoLayerPlugin] ERROR: playerKey=\(playerKey) 未匹配到任何 AVPlayer")
                result(false)
                return
            }

            let key = "key-\(playerKey)"
            NSLog("[AirPlayVideoLayerPlugin] attachLayerWithPlayerKey: playerKey=\(playerKey), matched=ok")
            self.createAndAttachLayer(
                player: player,
                key: key,
                aspectRatio: aspectRatio
            )
            result(true)
        }
    }

    private func createAndAttachLayer(
        player: AVPlayer,
        key: String,
        aspectRatio: Double
    ) {
        guard let window = AirPlayVideoLayerPlugin.keyWindow() else {
            NSLog("[AirPlayVideoLayerPlugin] ERROR: 无法获取 key window，无法挂载 AirPlay 辅助 layer")
            return
        }

        // 若已挂同 key 的容器，先移除。
        if let existing = attachedHosts[key] {
            let existingLayer = existing.playerLayer
            existing.removeFromSuperview()
            observations[existingLayer]?.invalidate()
            observations.removeValue(forKey: existingLayer)
            attachedHosts.removeValue(forKey: key)
        }

        let layer = NonHitTestablePlayerLayer()
        layer.player = player
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = UIColor.black.cgColor

        let host = AirPlayLayerHostView(playerLayer: layer, aspectRatio: CGFloat(aspectRatio))
        host.frame = window.bounds
        // 窗口子视图栈底插入：根视图（Flutter 画面）与其后所有 presented 视图
        // 都在其之上，靠 UIView 兄弟顺序被整体遮挡——纯视图顺序语义，行为确定。
        // layer frame 由 AirPlayLayerHostView.layoutSubviews 按 window bounds
        // 与 aspectRatio 自动计算（含旋转/分屏）。
        window.insertSubview(host, at: 0)
        attachedHosts[key] = host

        let initialExternal = layer.player?.isExternalPlaybackActive ?? false
        NSLog("[AirPlayVideoLayerPlugin] 已挂 layer: key=\(key), frame=\(layer.frame), isExternal=\(initialExternal), window insertSubview at 0")

        // KVO 外部播放状态变化（监听 AVPlayer.isExternalPlaybackActive）
        if let player = layer.player {
            let obs = player.observe(\.isExternalPlaybackActive, options: [.new]) { [weak self] player, _ in
                let active = player.isExternalPlaybackActive
                NSLog("[AirPlayVideoLayerPlugin] KVO isExternalPlaybackActive=\(active)")
                DispatchQueue.main.async {
                    self?.eventSink?(active)
                }
            }
            observations[layer] = obs
        }

        // 立即推送一次当前状态
        eventSink?(initialExternal)
    }

    private func detachAllLayers() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for (key, host) in self.attachedHosts {
                let layer = host.playerLayer
                host.removeFromSuperview()
                NSLog("[AirPlayVideoLayerPlugin] 已移除 layer: key=\(key)")
                self.observations[layer]?.invalidate()
            }
            self.attachedHosts.removeAll()
            self.observations.removeAll()
            // detach 时一并恢复被踢 player 的外部播放能力（路由可能仍在 airPlay，
            // 但 Dart 侧已主动断开，需避免下次 AirPlay 无法再投）。
            AirPlayVideoLayerPlugin.restoreKickedPlayers(reason: "detach_all_layers")
        }
    }

    // MARK: - Helpers

    /// 递归查找视图层级中的所有 AVPlayerLayer 并返回其 player。
    private static func collectPlayers(in layer: CALayer) -> [AVPlayer] {
        var result: [AVPlayer] = []
        collectPlayersRecursive(in: layer, into: &result)
        return result
    }

    private static func collectPlayersRecursive(in layer: CALayer, into: inout [AVPlayer]) {
        if let playerLayer = layer as? AVPlayerLayer, let player = playerLayer.player {
            into.append(player)
        }
        for sub in layer.sublayers ?? [] {
            collectPlayersRecursive(in: sub, into: &into)
        }
    }

    /// 兼容旧 API：取第一个 AVPlayer。
    private static func findFirstPlayer(in layer: CALayer) -> AVPlayer? {
        return collectPlayers(in: layer).first
    }

    static func topViewController() -> UIViewController? {
        guard var top = AirPlayVideoLayerPlugin.keyWindow()?.rootViewController else {
            return nil
        }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        return scenes.flatMap { $0.windows }.first(where: { $0.isKeyWindow })
            ?? scenes.flatMap { $0.windows }.first
    }

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = eventSink
        // 推送当前任一已挂 layer 的状态
        if let layer = attachedHosts.values.first?.playerLayer,
           let player = layer.player {
            eventSink(player.isExternalPlaybackActive)
        } else {
            eventSink(false)
        }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}