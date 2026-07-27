import Flutter
import UIKit
import AVFoundation
import ReplayKit

public class CapturePlugin: NSObject, FlutterPlugin {
    private var registrar: FlutterPluginRegistrar?
    private var assetWriter: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var isRecording = false
    private var tempFilePath: String?
    private var frameCount: Int64 = 0
    private var startTime: CMTime = .zero
    private var recordingFps: Int = 30
    private var recordingWidth: Int = 1920
    private var recordingHeight: Int = 1080
    private var channel: FlutterMethodChannel?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.meowtv.capture", binaryMessenger: registrar.messenger())
        let instance = CapturePlugin()
        instance.registrar = registrar
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
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

    // MARK: - 截帧

    private func captureFrame(result: @escaping FlutterResult) {
        DispatchQueue.main.async { [weak self] in
            guard self != nil else {
                result(FlutterError(code: "CAPTURE_FAILED", message: "Plugin deallocated", details: nil))
                return
            }

            guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }),
                  let rootViewController = window.rootViewController,
                  let view = rootViewController.view else {
                result(FlutterError(code: "NO_WINDOW", message: "Cannot find key window", details: nil))
                return
            }

            UIGraphicsBeginImageContextWithOptions(view.bounds.size, false, UIScreen.main.scale)
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
            let image = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            guard let capturedImage = image,
                  let jpegData = capturedImage.jpegData(compressionQuality: 1.0) else {
                result(FlutterError(code: "CAPTURE_FAILED", message: "Failed to capture frame", details: nil))
                return
            }

            result(FlutterStandardTypedData(bytes: jpegData))
        }
    }

    // MARK: - 录制

    private func startRecording(call: FlutterMethodCall, result: @escaping FlutterResult) {
        if isRecording {
            result(FlutterError(code: "ALREADY_RECORDING", message: "Recording is already in progress", details: nil))
            return
        }

        recordingFps = (call.arguments as? [String: Any])?["fps"] as? Int ?? 30
        recordingWidth = (call.arguments as? [String: Any])?["width"] as? Int ?? 1920
        recordingHeight = (call.arguments as? [String: Any])?["height"] as? Int ?? 1080

        let screenRecorder = RPScreenRecorder.shared()

        guard screenRecorder.isAvailable else {
            result(FlutterError(code: "RECORDING_UNAVAILABLE", message: "Screen recording is not available on this device", details: nil))
            return
        }

        // 设置临时文件
        let tempDir = NSTemporaryDirectory()
        let filePath = (tempDir as NSString).appendingPathComponent("meowtv_record_\(Int(Date().timeIntervalSince1970)).mp4")
        tempFilePath = filePath
        let fileURL = URL(fileURLWithPath: filePath)

        do {
            assetWriter = try AVAssetWriter(outputURL: fileURL, fileType: .mp4)

            let screenWidth = Int(UIScreen.main.bounds.width * UIScreen.main.scale)
            let screenHeight = Int(UIScreen.main.bounds.height * UIScreen.main.scale)
            let recordWidth = min(screenWidth, recordingWidth)
            let recordHeight = min(screenHeight, recordingHeight)

            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: recordWidth,
                AVVideoHeightKey: recordHeight,
            ]

            writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            writerInput?.expectsMediaDataInRealTime = true

            let sourcePixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: recordWidth,
                kCVPixelBufferHeightKey as String: recordHeight,
            ]

            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: writerInput!,
                sourcePixelBufferAttributes: sourcePixelBufferAttributes
            )

            if let writerInput = writerInput {
                assetWriter?.add(writerInput)
            }

            assetWriter?.startWriting()
            startTime = CMTimeMake(value: 0, timescale: 1)
            assetWriter?.startSession(atSourceTime: startTime)

            isRecording = true
            frameCount = 0

            // 使用 ReplayKit 的 startCapture 回调获取帧数据
            screenRecorder.startCapture(handler: { [weak self] sampleBuffer, type, error in
                guard let self = self, self.isRecording else { return }

                if type == .video, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

                    guard let writerInput = self.writerInput,
                          writerInput.isReadyForMoreMediaData else { return }

                    // 创建 CVPixelBuffer 副本，因为 CMSampleBuffer 的 buffer 可能不被 adaptor 接受
                    var pixelBufferCopy: CVPixelBuffer?
                    let copyAttributes: [String: Any] = [
                        kCVPixelBufferCGImageCompatibilityKey as String: true,
                        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                    ]
                    CVPixelBufferCreate(kCFAllocatorDefault,
                                        CVPixelBufferGetWidth(pixelBuffer),
                                        CVPixelBufferGetHeight(pixelBuffer),
                                        CVPixelBufferGetPixelFormatType(pixelBuffer),
                                        copyAttributes as CFDictionary,
                                        &pixelBufferCopy)

                    if let copy = pixelBufferCopy {
                        CVPixelBufferLockBaseAddress(copy, [])
                        CVPixelBufferLockBaseAddress(pixelBuffer, [])

                        if let srcData = CVPixelBufferGetBaseAddress(pixelBuffer),
                           let dstData = CVPixelBufferGetBaseAddress(copy) {
                            let srcBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
                            let dstBytesPerRow = CVPixelBufferGetBytesPerRow(copy)
                            let height = CVPixelBufferGetHeight(pixelBuffer)
                            for row in 0..<height {
                                memcpy(dstData.advanced(by: row * dstBytesPerRow),
                                       srcData.advanced(by: row * srcBytesPerRow),
                                       min(srcBytesPerRow, dstBytesPerRow))
                            }
                        }

                        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
                        CVPixelBufferUnlockBaseAddress(copy, [])

                        self.pixelBufferAdaptor?.append(copy, withPresentationTime: presentationTime)
                    }
                }
            }, completionHandler: { [weak self] error in
                guard let self = self else { return }
                if let error = error {
                    self.channel?.invokeMethod("onRecordingError", arguments: error.localizedDescription)
                }
                self.isRecording = false
            })

            result(nil)
        } catch {
            result(FlutterError(code: "RECORD_START_FAILED", message: "Failed to start recording: \(error.localizedDescription)", details: nil))
        }
    }

    private func stopRecording(result: @escaping FlutterResult) {
        if !isRecording {
            result(FlutterError(code: "NOT_RECORDING", message: "No recording in progress", details: nil))
            return
        }

        let screenRecorder = RPScreenRecorder.shared()
        screenRecorder.stopCapture { [weak self] error in
            guard let self = self else {
                result(FlutterError(code: "RECORD_STOP_FAILED", message: "Plugin deallocated", details: nil))
                return
            }

            self.isRecording = false
            self.writerInput?.markAsFinished()

            let path = self.tempFilePath
            self.tempFilePath = nil

            self.assetWriter?.finishWriting { [weak self] in
                guard self != nil else {
                    result(FlutterError(code: "RECORD_STOP_FAILED", message: "Plugin deallocated", details: nil))
                    return
                }

                if let path = path, FileManager.default.fileExists(atPath: path) {
                    result(path)
                } else {
                    result(FlutterError(code: "RECORD_STOP_FAILED", message: "Recording file not found", details: nil))
                }
            }
        }
    }
}
