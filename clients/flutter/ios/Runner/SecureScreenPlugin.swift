import Flutter
import UIKit

/// Защита экрана канала на iOS.
///
/// ⚠️ Предел платформы: iOS НЕ даёт приложению запретить скриншот или запись
/// экрана — аналога Android `FLAG_SECURE` нет. Реализуем то, что возможно:
/// пока защита включена, содержимое окна скрывается в переключателе приложений
/// (снапшот, который система снимает при уходе в фон). Сам скриншот подписчик
/// сделать сможет; обходить ограничение системы мы не пытаемся.
public class SecureScreenPlugin: NSObject, FlutterPlugin {
    /// Совпадает с `MethodChannel` в `lib/utils/secure_screen.dart`.
    private static let channelName = "ru.liza/secure_screen"

    /// Держит плагин живым: `addObserver`/`register` не удерживают ссылку
    /// сами по себе, а без сильной ссылки экземпляр немедленно освободился
    /// бы ARC — и подписки на `NotificationCenter` перестали бы срабатывать
    /// (наблюдатель мёртв). Поле никогда не читается — это ЕДИНСТВЕННОЕ его
    /// назначение.
    private static var instance: SecureScreenPlugin?

    /// Включена ли защита прямо сейчас (Dart-сторона держит хотя бы один экран).
    private var secure = false

    /// Накладка поверх окна на время фона — её и запоминает система в снапшоте.
    private var coverView: UIView?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        let plugin = SecureScreenPlugin()
        registrar.addMethodCallDelegate(plugin, channel: channel)
        instance = plugin

        let center = NotificationCenter.default
        center.addObserver(
            plugin,
            selector: #selector(willResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        center.addObserver(
            plugin,
            selector: #selector(didBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
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
        // Защита снята, пока приложение в фоне (например по пушу) — накладку
        // убираем сразу, иначе она «залипнет» видимой при возврате.
        if !secure {
            DispatchQueue.main.async { [weak self] in self?.removeCover() }
        }
        result(nil)
    }

    @objc private func willResignActive() {
        guard secure else { return }
        addCover()
    }

    @objc private func didBecomeActive() {
        removeCover()
    }

    private func keyWindow() -> UIWindow? {
        // `UIApplication.shared.windows` устарел с iOS 15 — на iOS 13+ окно
        // берём через сцены. Если ни одна сцена ещё не активна (короткое окно
        // на старте), возвращаем nil: `addCover()` в этом случае просто не
        // покажет накладку, следующий `willResignActive` подхватит.
        // Ветка до iOS 13 (deployment target Runner — 12.1) сцен не знает.
        if #available(iOS 13.0, *) {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
        }
        return UIApplication.shared.keyWindow
    }

    private func addCover() {
        guard coverView == nil, let window = keyWindow() else { return }
        let style: UIBlurEffect.Style
        if #available(iOS 13.0, *) {
            style = .systemMaterial
        } else {
            style = .regular
        }
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: style))
        blur.frame = window.bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(blur)
        coverView = blur
    }

    private func removeCover() {
        coverView?.removeFromSuperview()
        coverView = nil
    }
}
