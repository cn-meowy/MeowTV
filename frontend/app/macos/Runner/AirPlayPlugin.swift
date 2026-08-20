import FlutterMacOS
import AVKit
import AppKit
import CoreAudio
import CoreFoundation

/// 原生 AirPlay 路由插件（macOS）。
///
/// 通过 [FlutterMethodChannel] 接收 Dart 端调用：
/// - `showAirPlayPicker`: 触发系统 AirPlay 选路面板。使用一个**常驻**的
///   `AVRoutePickerView`（非 `isHidden`），触发前临时把它移到窗口可见区域内
///   （锚定在用户点击入口附近），递归查找其内部 `NSButton` 后 `performClick`
///   触发；macOS 26 (Tahoe) 上按钮不可见时系统不再弹出 popover，故必须可见。
///   popover 关闭后再把 picker 移回离屏；3s 内未出现 popover 时保持可见供手点（10s 兜底自动回收）。
/// - `isExternalPlaybackActive`: 基于 CoreAudio 输出设备 transport 类型判断
///   AirPlay 是否激活
/// - `getActiveRouteName`: 返回 AirPlay 输出设备名
///
/// 通过 [FlutterEventChannel] 推送 AirPlay 路由状态变化：监听系统默认输出设备
/// （`kAudioHardwarePropertyDefaultOutputDevice`）与设备列表
/// （`kAudioHardwarePropertyDevices`）变化，重评估后 push 布尔状态。
class AirPlayPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private var persistentPicker: AVRoutePickerView?
    private var deviceListenerRegistered = false
    /// popover 关闭轮询定时器（主队列）。再次触发 showAirPlayPicker 时先取消。
    private var popoverPollTimer: Timer?

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.meowtv.airplay",
            binaryMessenger: registrar.messenger
        )
        let eventChannel = FlutterEventChannel(
            name: "com.meowtv.airplay/events",
            binaryMessenger: registrar.messenger
        )
        let instance = AirPlayPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "showAirPlayPicker":
            // 可选参数 {x, y}：Flutter 逻辑坐标（原点左上）。缺省 nil → 默认右上角。
            var anchorX: Double? = nil
            var anchorY: Double? = nil
            if let args = call.arguments as? [String: Any] {
                if let x = args["x"] as? Double { anchorX = x }
                if let y = args["y"] as? Double { anchorY = y }
            }
            DispatchQueue.main.async { [weak self] in
                let ok = self?.triggerPicker(anchorX: anchorX, anchorY: anchorY) ?? false
                NSLog("[AirPlayPlugin] showAirPlayPicker result=\(ok)")
                result(ok)
            }
        case "isExternalPlaybackActive":
            result(isAirPlayRouteActive())
        case "getActiveRouteName":
            result(getActiveRouteName())
        case "disconnectAirPlay":
            let switched = self.disconnectAirPlayBySwitchingDefaultOutput()
            NSLog("[AirPlayPlugin] disconnectAirPlay switched=\(switched)")
            result(switched)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - AirPlay Picker

    /// 触发系统 AirPlay 选路面板。
    ///
    /// - Parameters:
    ///   - anchorX/anchorY: Flutter 逻辑坐标（原点左上），锚定在用户点击入口附近。
    ///     缺省 nil 时取窗口内容视图右上角。
    ///
    /// macOS 26 (Tahoe) 上 `AVRoutePickerButton` 不在窗口可见区域内时，
    /// `performClick` 静默失败（不弹 popover）。故触发前把常驻 picker 临时移到
    /// 可见区内，`performClick` 后双信号轮询 popover（类名启发式 + 窗口集合 diff）：
    /// 出现后等其关闭再移回离屏；3s 内未出现则保持可见供用户手点，10s 兜底自动回收。
    /// 总时长 30s 硬上限，避免轮询定时器常驻。
    private func triggerPicker(anchorX: Double?, anchorY: Double?) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        guard let hostView = NSApp.keyWindow?.contentViewController?.view else {
            NSLog("[AirPlayPlugin] ERROR: 无法获取 keyWindow contentViewController.view")
            return false
        }

        // 再次触发时先取消旧的 popover 轮询定时器
        popoverPollTimer?.invalidate()
        popoverPollTimer = nil

        // 懒创建常驻 AVRoutePickerView（不随触发移除、不 isHidden）
        let picker: AVRoutePickerView
        if let existing = persistentPicker {
            picker = existing
        } else {
            let p = AVRoutePickerView(frame: NSRect(x: -10000, y: -10000, width: 44, height: 44))
            p.isHidden = false
            hostView.addSubview(p)
            persistentPicker = p
            picker = p
            NSLog("[AirPlayPlugin] 创建常驻 picker")
        }
        if picker.superview !== hostView {
            hostView.addSubview(picker)
        }
        picker.isHidden = false

        // 计算 picker 目标 frame（AppKit 坐标，原点左下），确保完整落在
        // hostView.bounds 可见区内（8pt 边距，44×44 尺寸）。
        // Flutter 逻辑 px == AppKit points（macOS 无 DPR 换算）；
        // Flutter y 原点左上 → AppKit y = bounds.height - flutterY。
        let bounds = hostView.bounds
        let size: CGFloat = 44
        let margin: CGFloat = 8
        let targetX: CGFloat
        if let ax = anchorX {
            // 锚点为入口中心，picker 居中于锚点 x
            targetX = min(max(ax - size / 2, margin), bounds.width - size - margin)
        } else {
            targetX = bounds.width - size - margin
        }
        let targetY: CGFloat
        if let ay = anchorY {
            let appKitY = bounds.height - ay
            targetY = min(max(appKitY - size / 2, margin), bounds.height - size - margin)
        } else {
            targetY = bounds.height - size - margin
        }
        picker.frame = NSRect(x: targetX, y: targetY, width: size, height: size)

        picker.layoutSubtreeIfNeeded()

        guard let button = AirPlayPlugin.findButton(in: picker) else {
            NSLog("[AirPlayPlugin] ERROR: 常驻 picker 内部按钮未找到，保持可见供手点兜底")
            // 找不到按钮时保持当前可见位置（替代旧"移屏幕中央"语义），让用户手点
            return false
        }
        NSLog("[AirPlayPlugin] 触发常驻 picker 内部按钮 anchor=(\(targetX),\(targetY))")
        button.performClick(nil)

        // 启动 popover 轮询：0.25s 间隔，总时长 30s 硬上限。
        // performClick 前快照 NSApp.windows 的 ObjectIdentifier 集合，之后任意
        // 不在快照中的窗口视为 popover（双信号：类名启发式 + 窗口集合 diff，
        // 跨 macOS 版本健壮）。3s 内未出现 → 兜底保持可见至 10s 后自动回收；
        // 出现后等其关闭立即移回离屏停表。
        let baselineWindowIDs = Set(NSApp.windows.map { ObjectIdentifier($0) })
        let startTime = Date()
        var didAppear = false
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            let elapsed = Date().timeIntervalSince(startTime)
            let popoverVisible = self.isPopoverWindowPresented()
                || self.isNewWindowPresented(baseline: baselineWindowIDs)

            // 30s 硬上限（兑现注释承诺，防 Timer 永生）
            if elapsed >= 30.0 {
                NSLog("[AirPlayPlugin] popover 轮询达 30s 上限，移回离屏 (elapsed=\(elapsed)s)")
                self.hidePickerOffscreen()
                t.invalidate()
                self.popoverPollTimer = nil
                return
            }

            if popoverVisible {
                if !didAppear {
                    didAppear = true
                    // 诊断：首次检出时记录新窗口类名，便于将来排查类名变化
                    if let newWin = NSApp.windows.first(where: { !baselineWindowIDs.contains(ObjectIdentifier($0)) }) {
                        NSLog("[AirPlayPlugin] popover 已出现 (elapsed=\(elapsed)s, class=\(String(describing: type(of: newWin))))")
                    } else {
                        NSLog("[AirPlayPlugin] popover 已出现 (elapsed=\(elapsed)s)")
                    }
                }
                return
            }

            if didAppear {
                // popover 已关闭 → 移回离屏，停表
                NSLog("[AirPlayPlugin] popover 已关闭，移回离屏 (elapsed=\(elapsed)s)")
                self.hidePickerOffscreen()
                t.invalidate()
                self.popoverPollTimer = nil
                return
            }

            // 尚未出现：3s 内继续轮询等待；超时后兜底保持可见至 10s 自动回收
            if elapsed >= 10.0 {
                NSLog("[AirPlayPlugin] popover 兜底超时，自动移回离屏 (elapsed=\(elapsed)s)")
                self.hidePickerOffscreen()
                t.invalidate()
                self.popoverPollTimer = nil
                return
            }
        }
        // 主队列调度，保证与 UI 线程一致
        RunLoop.main.add(timer, forMode: .common)
        popoverPollTimer = timer

        return true
    }

    /// 把常驻 picker 移回离屏坐标。
    private func hidePickerOffscreen() {
        guard let picker = persistentPicker else { return }
        picker.frame = NSRect(x: -10000, y: -10000, width: 44, height: 44)
    }

    /// 检测系统 AirPlay 选路 popover 是否已弹出。
    ///
    /// 遍历 `NSApp.windows`，存在类名含 `"Popover"` 的窗口（实际类
    /// `_NSPopoverWindow`）即视为弹出。
    private func isPopoverWindowPresented() -> Bool {
        for w in NSApp.windows {
            let typeName = String(describing: type(of: w))
            if typeName.contains("Popover") { return true }
        }
        return false
    }

    /// 窗口集合 diff 检测：是否存在 performClick 后新增的窗口（与类名无关）。
    /// 跨 macOS 版本健壮；`NSApp.windows` 含子窗口/面板，所以 popover 也会被捕获。
    private func isNewWindowPresented(baseline: Set<ObjectIdentifier>) -> Bool {
        for w in NSApp.windows where !baseline.contains(ObjectIdentifier(w)) {
            return true
        }
        return false
    }

    private static func findButton(in view: NSView) -> NSButton? {
        for subview in view.subviews {
            if let button = subview as? NSButton { return button }
            if let found = findButton(in: subview) { return found }
        }
        return nil
    }

    // MARK: - CoreAudio Route Status

    /// 系统对象 ID（`kAudioObjectSystemObject` 在 Swift 中为 Int32，需转 AudioObjectID）。
    private var systemObject: AudioObjectID { AudioObjectID(kAudioObjectSystemObject) }

    private func currentAirPlayDeviceID() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            systemObject, &address, 0, nil, &size, &deviceID
        )
        if status != noErr || deviceID == kAudioObjectUnknown { return 0 }
        return deviceID
    }

    private func transportType(deviceID: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        if status != noErr { return nil }
        return value
    }

    private func deviceName(deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfNamePtr: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &cfNamePtr)
        guard status == noErr, let cfName = cfNamePtr?.takeRetainedValue() else { return nil }
        return cfName as String
    }

    /// 是否 AirPlay 激活。默认输出设备若是 AirPlay transport 即视为激活。
    private func isAirPlayRouteActive() -> Bool {
        // 镜像守卫：外接显示器存在（NSScreen.screens.count > 1）时不视为
        // app 内投屏激活。已知取舍：常年外接显示器的 Mac 用户投音频时不会出
        // 黑屏 overlay（文档化说明即可）。
        if NSScreen.screens.count > 1 {
            return false
        }
        let deviceID = currentAirPlayDeviceID()
        guard deviceID != 0 else { return false }
        if let transport = transportType(deviceID: deviceID),
           transport == kAudioDeviceTransportTypeAirPlay {
            return true
        }
        // 退化：默认输出不切换时，存在任意 AirPlay transport 输出设备也视为激活
        return hasAnyAirPlayOutputDevice()
    }

    private func hasAnyAirPlayOutputDevice() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(0)
        guard AudioObjectGetPropertyDataSize(
            systemObject, &address, 0, nil, &dataSize) == noErr,
            dataSize > 0 else { return false }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return false }
        let devices = UnsafeMutablePointer<AudioDeviceID>.allocate(capacity: count)
        defer { devices.deallocate() }
        let status = AudioObjectGetPropertyData(
            systemObject, &address, 0, nil, &dataSize, devices)
        guard status == noErr else { return false }
        for i in 0..<count {
            let deviceID = devices.advanced(by: i).pointee
            if let transport = transportType(deviceID: deviceID),
               transport == kAudioDeviceTransportTypeAirPlay {
                return true
            }
        }
        return false
    }

    private func getActiveRouteName() -> String? {
        let deviceID = currentAirPlayDeviceID()
        guard deviceID != 0 else { return nil }
        guard let transport = transportType(deviceID: deviceID),
              transport == kAudioDeviceTransportTypeAirPlay else { return nil }
        return deviceName(deviceID: deviceID)
    }

    // MARK: - 一键断开（切回非 AirPlay 默认输出）

    /// 枚举所有输出设备，选最合适的非 AirPlay transport，把系统默认输出切过去。
    /// 优先级：内置（`kAudioDeviceTransportTypeBuiltIn`）> HDMI/DisplayPort/USB
    /// > 其他非 AirPlay > 任意非 AirPlay。返回是否实际执行了切换。
    private func disconnectAirPlayBySwitchingDefaultOutput() -> Bool {
        // 仅在当前默认输出是 AirPlay 时尝试切换
        let currentID = currentAirPlayDeviceID()
        guard currentID != 0,
              let currentTransport = transportType(deviceID: currentID),
              currentTransport == kAudioDeviceTransportTypeAirPlay else {
            NSLog("[AirPlayPlugin] disconnectAirPlay: 当前默认输出非 AirPlay，无需切换")
            return false
        }

        // 取全部输出设备
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(0)
        guard AudioObjectGetPropertyDataSize(
            systemObject, &address, 0, nil, &dataSize) == noErr,
            dataSize > 0 else { return false }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return false }
        let devices = UnsafeMutablePointer<AudioDeviceID>.allocate(capacity: count)
        defer { devices.deallocate() }
        guard AudioObjectGetPropertyData(
            systemObject, &address, 0, nil, &dataSize, devices) == noErr else { return false }

        var candidates: [AudioDeviceID] = []
        for i in 0..<count {
            let id = devices.advanced(by: i).pointee
            if id == currentID { continue }
            // 仅输出设备
            var streamAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize = UInt32(0)
            let hasStream = AudioObjectGetPropertyDataSize(id, &streamAddr, 0, nil, &streamSize) == noErr && streamSize > 0
            if !hasStream { continue }
            if let t = transportType(deviceID: id), t != kAudioDeviceTransportTypeAirPlay {
                candidates.append(id)
            }
        }
        guard !candidates.isEmpty else {
            NSLog("[AirPlayPlugin] disconnectAirPlay: 未找到非 AirPlay 输出设备")
            return false
        }

        // 选 best：内置优先
        let preferred: [UInt32] = [
            kAudioDeviceTransportTypeBuiltIn,
            kAudioDeviceTransportTypeHDMI,
            kAudioDeviceTransportTypeDisplayPort,
            kAudioDeviceTransportTypeUSB,
            kAudioDeviceTransportTypeBluetooth,
        ]
        var chosen: AudioDeviceID = candidates.first!
        for pref in preferred {
            if let hit = candidates.first(where: { transportType(deviceID: $0) == pref }) {
                chosen = hit
                break
            }
        }

        var newDeviceID = chosen
        var setAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let setSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectSetPropertyData(
            systemObject, &setAddr, 0, nil, setSize, &newDeviceID
        )
        let name = deviceName(deviceID: chosen) ?? "?"
        NSLog("[AirPlayPlugin] disconnectAirPlay: 切换默认输出 status=\(status), target=\(name) (id=\(chosen))")
        // CoreAudio 监听器会异步推送新的 false 状态，Dart 端自动清 overlay。
        return status == noErr
    }

    // MARK: - CoreAudio Listeners

    private static let audioObjectListener: AudioObjectPropertyListenerProc = {
        inObjectID, inNumberAddresses, inAddresses, inClientData in
        guard let clientData = inClientData else { return kAudioHardwareNoError }
        let plugin = Unmanaged<AirPlayPlugin>.fromOpaque(clientData).takeUnretainedValue()
        let active = plugin.isAirPlayRouteActive()
        NSLog("[AirPlayPlugin] CoreAudio 设备属性变化 active=\(active)")
        DispatchQueue.main.async {
            plugin.eventSink?(active)
        }
        return kAudioHardwareNoError
    }

    private func registerAudioListeners() {
        guard !deviceListenerRegistered else { return }
        deviceListenerRegistered = true
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        var defaultOutputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListener(
            systemObject, &defaultOutputAddress,
            AirPlayPlugin.audioObjectListener, selfPtr)

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListener(
            systemObject, &devicesAddress,
            AirPlayPlugin.audioObjectListener, selfPtr)
    }

    private func unregisterAudioListeners() {
        guard deviceListenerRegistered else { return }
        deviceListenerRegistered = false
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        var defaultOutputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListener(
            systemObject, &defaultOutputAddress,
            AirPlayPlugin.audioObjectListener, selfPtr)

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListener(
            systemObject, &devicesAddress,
            AirPlayPlugin.audioObjectListener, selfPtr)
    }

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = eventSink
        eventSink(isAirPlayRouteActive())
        registerAudioListeners()
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        unregisterAudioListeners()
        eventSink = nil
        return nil
    }
}