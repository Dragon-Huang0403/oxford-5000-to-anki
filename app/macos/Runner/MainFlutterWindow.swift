import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  var windowChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    windowChannel = FlutterMethodChannel(
      name: "com.deckionary/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    windowChannel!.setMethodCallHandler { [weak self] (call, result) in
      switch call.method {
      case "prepareForShow":
        // Temporarily switch to moveToActiveSpace to jump to user's current Space
        self?.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        self?.level = .floating
        // Reset after the Space transition completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
          self?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }
        result(nil)
      case "resetLevel":
        self?.level = .normal
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
    super.awakeFromNib()
  }
}
