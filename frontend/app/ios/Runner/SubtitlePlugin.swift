import Flutter
import AVFoundation

class SubtitlePlugin: NSObject, FlutterPlugin {
    private var channel: FlutterMethodChannel?

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.meowtv.subtitle/render", binaryMessenger: registrar.messenger())
        let instance = SubtitlePlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getEmbeddedTracks": result([])
        case "selectEmbeddedTrack":
            let args = call.arguments as? [String: Any]
            let trackIndex = args?["trackIndex"] as? Int ?? 0
            print("SubtitlePlugin: selectEmbeddedTrack \(trackIndex)")
            result(true)
        case "loadExternalSubtitle":
            let args = call.arguments as? [String: Any]
            let cues = args?["cues"] as? [[String: Any]] ?? []
            let offsetMs = args?["offsetMs"] as? Double ?? 0.0
            print("SubtitlePlugin: loadExternalSubtitle \(cues.count) cues, offset: \(offsetMs)ms")
            result(true)
        case "updateOffset":
            let args = call.arguments as? [String: Any]
            let offsetMs = args?["offsetMs"] as? Double ?? 0.0
            print("SubtitlePlugin: updateOffset \(offsetMs)ms")
            result(true)
        case "clearSubtitle": result(nil)
        default: result(FlutterMethodNotImplemented)
        }
    }
}
