import Cocoa
import FlutterMacOS

/// Защита экрана канала на macOS.
///
/// ⚠️ Предел платформы: приложение не может запретить пользователю снять
/// скриншот — аналога Android `FLAG_SECURE` в AppKit нет. Делаем возможное:
/// пока защита включена, окно исключается из захвата (`sharingType = .none`,
/// это скрывает его от записи экрана и шаринга в конференциях) и содержимое
/// закрывается накладкой при уходе приложения в фон. Сам скриншот системным
/// сочетанием клавиш остаётся доступен; обходить это мы не пытаемся.
public class SecureScreenPlugin: NSObject, FlutterPlugin {
    /// Совпадает с `MethodChannel` в `lib/utils/secure_screen.dart`.
    private static let channelName = "ru.liza/secure_screen"

    /// Держит плагин живым: без сильной ссылки экземпляр немедленно
    /// освободился бы ARC — и подписки на `NotificationCenter` перестали бы
    /// срабатывать (наблюдатель мёртв). Поле никогда не читается — это
    /// ЕДИНСТВЕННОЕ его назначение.
    private static var instance: SecureScreenPlugin?

    private weak var window: NSWindow?
    private var secure = false
    private var coverView: NSView?

    public static func register(with registrar: FlutterPluginRegistrar) {
        register(with: registrar, window: nil)
    }

    public static func register(with registrar: FlutterPluginRegistrar, window: NSWindow?) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger
        )
        let plugin = SecureScreenPlugin()
        plugin.window = window
        registrar.addMethodCallDelegate(plugin, channel: channel)
        instance = plugin

        let center = NotificationCenter.default
        center.addObserver(
            plugin,
            selector: #selector(didResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        center.addObserver(
            plugin,
            selector: #selector(didBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "setSecure" else {
            result(FlutterMethodNotImplemented)
            return
        }
        let args = call.arguments as? [String: Any]
        secure = args?["enabled"] as? Bool ?? false
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.targetWindow()?.sharingType = self.secure ? .none : .readOnly
            if !self.secure { self.removeCover() }
        }
        result(nil)
    }

    private func targetWindow() -> NSWindow? {
        window ?? NSApplication.shared.mainWindow ?? NSApplication.shared.windows.first
    }

    @objc private func didResignActive() {
        guard secure else { return }
        addCover()
    }

    @objc private func didBecomeActive() {
        removeCover()
    }

    private func addCover() {
        guard coverView == nil,
              let contentView = targetWindow()?.contentView else { return }
        let cover = NSVisualEffectView(frame: contentView.bounds)
        cover.material = .fullScreenUI
        cover.blendingMode = .withinWindow
        cover.state = .active
        cover.autoresizingMask = [.width, .height]
        contentView.addSubview(cover)
        coverView = cover
    }

    private func removeCover() {
        coverView?.removeFromSuperview()
        coverView = nil
    }
}
