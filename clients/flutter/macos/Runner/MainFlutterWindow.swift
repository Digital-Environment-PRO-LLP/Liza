import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.minSize = NSSize(width: 480, height: 400)
    self.setFrameAutosaveName("MainFlutterWindow")

    let restored = self.setFrameUsingName(self.frameAutosaveName)
    if !restored || self.frame.width < 480 || self.frame.height < 400 {
      self.setFrame(NSRect(x: 0, y: 0, width: 960, height: 700), display: true)
      self.center()
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  override func close() {
    // Hide the window instead of closing it so the app stays in the Dock.
    // Using orderOut alone is fine — the window can be restored via
    // applicationShouldHandleReopen or applicationDidBecomeActive.
    if self.isMiniaturized {
      self.deminiaturize(nil)
    }
    self.orderOut(self)
  }
}
