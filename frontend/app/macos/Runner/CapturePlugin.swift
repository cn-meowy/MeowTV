import Cocoa
import FlutterMacOS
import AVFoundation

/// macOS 端截图/录制原生插件
/// 实现 MethodChannel `com.meowtv.capture` 的 captureFrame / startRecording / stopRecording
class CapturePlugin: NSObject, FlutterPlugin {
    private var channel: FlutterMethodChannel?
    private var isRecording = false
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var outputURL: URL?
    private var recordingWidth: Int = 1920
    private var recordingHeight: Int = 1080
    private var recordingFps: Int = 30
    private var frameCount: Int64 = 0
    private var captureTimer: Timer?
    private var flutterViewController: FlutterViewController?

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.meowtv.capture", binaryMessenger: registrar.messenger)
        let instance = CapturePlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "captureFrame":
            captureFrame(result: result)
        case "startRecording":
            startRecording(call: call, result: result)
        case "stopRecording":
            stopRecording(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - 截图

    /// 截取当前 FlutterView 内容，返回 JPEG Data (Uint8List)
    private func captureFrame(result: @escaping FlutterResult) {
        guard let fvc = getFlutterViewController() else {
            result(FlutterError(code: "NO_VIEW", message: "Cannot find FlutterViewController", details: nil))
            return
        }

        let view = fvc.view
        guard let bitmapRep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            result(FlutterError(code: "CAPTURE_FAILED", message: "Failed to create bitmap representation", details: nil))
            return
        }

        view.cacheDisplay(in: view.bounds, to: bitmapRep)

        guard let tiffData = bitmapRep.tiffRepresentation,
              let tiffImage = NSImage(data: tiffData),
              let cgImage = tiffImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            result(FlutterError(code: "CAPTURE_FAILED", message: "Failed to convert to CGImage", details: nil))
            return
        }

        let newRep = NSBitmapImageRep(cgImage: cgImage)

        // JPEG 压缩 (quality=100 → compressionFactor=1.0)
        guard let jpegData = newRep.representation(using: NSBitmapImageRep.FileType.jpeg, properties: [NSBitmapImageRep.PropertyKey.compressionFactor: 1.0]) else {
            result(FlutterError(code: "CAPTURE_FAILED", message: "Failed to encode JPEG", details: nil))
            return
        }

        result(FlutterStandardTypedData(bytes: jpegData))
    }

    // MARK: - 录制

    /// 开始录制：使用 AVAssetWriter + 定时截图帧序列
    private func startRecording(call: FlutterMethodCall, result: @escaping FlutterResult) {
        if isRecording {
            result(FlutterError(code: "ALREADY_RECORDING", message: "Recording is already in progress", details: nil))
            return
        }

        guard let fvc = getFlutterViewController() else {
            result(FlutterError(code: "NO_VIEW", message: "Cannot find FlutterViewController", details: nil))
            return
        }

        flutterViewController = fvc

        let args = call.arguments as? [String: Any]
        recordingFps = args?["fps"] as? Int ?? 30
        recordingWidth = args?["width"] as? Int ?? 1920
        recordingHeight = args?["height"] as? Int ?? 1080

        // 创建临时输出文件
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "meowtv_record_\(Int(Date().timeIntervalSince1970)).mp4"
        outputURL = tempDir.appendingPathComponent(fileName)

        guard let url = outputURL else {
            result(FlutterError(code: "CREATE_FAILED", message: "Failed to create output URL", details: nil))
            return
        }

        // 删除已存在的文件
        try? FileManager.default.removeItem(at: url)

        do {
            assetWriter = try AVAssetWriter(outputURL: url, fileType: .mp4)

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: recordingWidth,
                AVVideoHeightKey: recordingHeight,
            ]

            assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            assetWriterInput!.expectsMediaDataInRealTime = true

            let sourcePixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: recordingWidth,
                kCVPixelBufferHeightKey as String: recordingHeight,
            ]

            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: assetWriterInput!,
                sourcePixelBufferAttributes: sourcePixelBufferAttributes
            )

            assetWriter!.add(assetWriterInput!)
            assetWriter!.startWriting()
            assetWriter!.startSession(atSourceTime: .zero)

            frameCount = 0
            isRecording = true

            // 启动定时截图（降低帧率以减少性能开销，实际使用 15fps）
            let effectiveFps = min(recordingFps, 15)
            let interval = 1.0 / Double(effectiveFps)
            captureTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.captureFrameForRecording()
            }

            result(true)
        } catch {
            result(FlutterError(code: "CREATE_FAILED", message: "Failed to create AVAssetWriter: \(error.localizedDescription)", details: nil))
        }
    }

    /// 定时捕获帧并写入 AVAssetWriter
    private func captureFrameForRecording() {
        guard isRecording,
              let writerInput = assetWriterInput,
              let adaptor = pixelBufferAdaptor,
              let fvc = flutterViewController,
              writerInput.isReadyForMoreMediaData else {
            return
        }

        let view = fvc.view
        guard let bitmapRep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmapRep)

        guard let cgImage = bitmapRep.cgImage else { return }

        let presentationTime = CMTime(value: frameCount, timescale: Int32(recordingFps))
        frameCount += 1

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, recordingWidth, recordingHeight,
                                          kCVPixelFormatType_32ARGB, nil, &pixelBuffer)
        guard status == kCVReturnSuccess, let pb = pixelBuffer else { return }

        CVPixelBufferLockBaseAddress(pb, [])
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pb),
                                       width: recordingWidth,
                                       height: recordingHeight,
                                       bitsPerComponent: 8,
                                       bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                       space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else {
            CVPixelBufferUnlockBaseAddress(pb, [])
            return
        }

        // 填充黑色背景
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: recordingWidth, height: recordingHeight))

        // 缩放绘制视图内容（保持宽高比居中）
        let imgWidth = CGFloat(cgImage.width)
        let imgHeight = CGFloat(cgImage.height)
        let scale = min(CGFloat(recordingWidth) / imgWidth, CGFloat(recordingHeight) / imgHeight)
        let drawWidth = imgWidth * scale
        let drawHeight = imgHeight * scale
        let drawX = (CGFloat(recordingWidth) - drawWidth) / 2
        let drawY = (CGFloat(recordingHeight) - drawHeight) / 2
        context.draw(cgImage, in: CGRect(x: drawX, y: drawY, width: drawWidth, height: drawHeight))

        CVPixelBufferUnlockBaseAddress(pb, [])

        adaptor.append(pb, withPresentationTime: presentationTime)
    }

    /// 停止录制，返回文件路径
    private func stopRecording(result: @escaping FlutterResult) {
        guard isRecording else {
            result(FlutterError(code: "NOT_RECORDING", message: "No recording in progress", details: nil))
            return
        }

        captureTimer?.invalidate()
        captureTimer = nil
        isRecording = false

        guard let writer = assetWriter else {
            result(nil)
            return
        }

        assetWriterInput?.markAsFinished()

        writer.finishWriting { [weak self] in
            guard let self = self else {
                result(nil)
                return
            }

            if writer.status == .completed, let url = self.outputURL {
                result(url.path)
            } else {
                let errorMsg = writer.error?.localizedDescription ?? "Unknown error"
                print("[CapturePlugin] AVAssetWriter finishWriting failed: \(errorMsg)")
                result(nil)
            }

            // 清理
            self.assetWriter = nil
            self.assetWriterInput = nil
            self.pixelBufferAdaptor = nil
            self.outputURL = nil
            self.flutterViewController = nil
        }
    }

    // MARK: - 辅助方法

    /// 获取当前 FlutterViewController
    /// 通过遍历应用窗口查找包含 FlutterViewController 的主窗口
    private func getFlutterViewController() -> FlutterViewController? {
        for window in NSApp.windows {
            if let fvc = window.contentViewController as? FlutterViewController {
                return fvc
            }
        }
        return nil
    }
}