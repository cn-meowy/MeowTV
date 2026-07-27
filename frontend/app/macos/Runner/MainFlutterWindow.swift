import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Register custom plugins for macOS
    let subtitleRegistrar = flutterViewController.registrar(forPlugin: "SubtitlePlugin")
    SubtitlePlugin.register(with: subtitleRegistrar)

    let captureRegistrar = flutterViewController.registrar(forPlugin: "CapturePlugin")
    CapturePlugin.register(with: captureRegistrar)

    super.awakeFromNib()
  }
}
