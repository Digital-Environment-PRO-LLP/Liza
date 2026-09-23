import Flutter
import UIKit
import UserNotifications

/// App Group приложения, вычисленная из bundle id.
///
/// Группа всегда `group.<bundle id основного приложения>`. Для расширений
/// (NSE, Share) bundle id содержит лишний последний компонент — отбрасываем.
/// Вычисляем, а не хардкодим: bundle id меняется при смене Apple-аккаунта,
/// и рассинхрон литерала с entitlements ломает пуши МОЛЧА —
/// UserDefaults(suiteName:) вернёт пустой контейнер без ошибки.
func lizaAppGroup(for bundle: Bundle = .main) -> String {
    guard let bundleId = bundle.bundleIdentifier else { return "" }
    let isExtension = bundle.bundleURL.pathExtension == "appex"
    let appId = isExtension
        ? bundleId.split(separator: ".").dropLast().joined(separator: ".")
        : bundleId
    return "group.\(appId)"
}

/// Native APNs plugin — replaces FcmSharedIsolate.
/// Provides raw APNs device token (hex) and push handling via MethodChannel.
public class ApnsPushPlugin: NSObject, FlutterPlugin {
    private static var channel: FlutterMethodChannel?
    private static var pendingToken: String?
    private static var pendingTokenResult: FlutterResult?
    private static var pendingNotificationTap: [String: String]?
    static var activeRoomId: String?
    static var activeClientName: String?
    static var activeSingleClient = true

    /// Пуш пришёл в чат, открытый сейчас на экране (зеркало Dart
    /// `pushInActiveRoomFor`): тот же room_id у ДРУГОГО своего аккаунта не глушим;
    /// пуш без client_name (старый pusher) считаем своим только при одном аккаунте.
    static func isActiveRoom(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let room = activeRoomId,
              let pushRoom = userInfo["room_id"] as? String,
              pushRoom == room else { return false }
        if let pushClient = userInfo["client_name"] as? String, !pushClient.isEmpty {
            return pushClient == activeClientName
        }
        return activeSingleClient
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let ch = FlutterMethodChannel(
            name: "com.prodamus.laba.liza/apns",
            binaryMessenger: registrar.messenger()
        )
        let instance = ApnsPushPlugin()
        registrar.addMethodCallDelegate(instance, channel: ch)
        channel = ch

        // If token arrived before Flutter was ready
        if let token = pendingToken {
            ch.invokeMethod("onToken", arguments: token)
        }

        // If notification tap arrived before Flutter was ready (cold start)
        if let tap = pendingNotificationTap {
            ch.invokeMethod("onNotificationTap", arguments: tap)
            pendingNotificationTap = nil
        }
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "requestPermission":
            UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            ) { granted, _ in
                DispatchQueue.main.async {
                    if granted {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                    result(granted)
                }
            }
        case "getToken":
            if let token = ApnsPushPlugin.pendingToken {
                result(token)
            } else {
                UIApplication.shared.registerForRemoteNotifications()
                ApnsPushPlugin.pendingTokenResult = result
                // Timeout after 15 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                    if let pending = ApnsPushPlugin.pendingTokenResult {
                        pending(FlutterError(
                            code: "TIMEOUT",
                            message: "APNs token not received within timeout",
                            details: nil
                        ))
                        ApnsPushPlugin.pendingTokenResult = nil
                    }
                }
            }
        case "getInitialNotificationTap":
            if let tap = ApnsPushPlugin.pendingNotificationTap {
                ApnsPushPlugin.pendingNotificationTap = nil
                result(tap)
            } else {
                result(nil)
            }
        case "saveCredentials":
            let args = call.arguments as? [String: String]
            let defaults = UserDefaults(suiteName: lizaAppGroup())
            defaults?.set(args?["homeserverUrl"], forKey: "homeserverUrl")
            defaults?.set(args?["accessToken"], forKey: "accessToken")
            result(true)
        case "setActiveRoom":
            // Открытый на экране чат (Dart шлёт null при уходе с чата или в фон).
            // Живёт только в памяти процесса: в App Group значение пережило бы
            // kill и глушило бы уведомления уже закрытого чата.
            let args = call.arguments as? [String: Any]
            ApnsPushPlugin.activeRoomId = args?["roomId"] as? String
            ApnsPushPlugin.activeClientName = args?["clientName"] as? String
            ApnsPushPlugin.activeSingleClient = args?["singleClient"] as? Bool ?? true
            result(true)
        case "saveBadgeCount":
            // Клиент-авторитетное число видимых непрочитанных → App Group, откуда
            // его читает NSE при закрытом приложении (вместо сырого counts.unread).
            let args = call.arguments as? [String: Any]
            let count = args?["count"] as? Int ?? 0
            let defaults = UserDefaults(suiteName: lizaAppGroup())
            defaults?.set(count, forKey: "badge_count")
            result(true)
        case "cancelDeliveredForRoom":
            // Баннер, нарисованный NSE, плагину flutter_local_notifications не
            // принадлежит: его идентификатор — UUID от APNs, а плагин ищет по
            // своему числовому id и такие уведомления просто пропускает
            // (`userInfo[NOTIFICATION_ID] == nil`). Снимаем по threadIdentifier —
            // его NSE проставляет равным room_id на каждом баннере.
            let cancelArgs = call.arguments as? [String: Any]
            guard let roomId = cancelArgs?["roomId"] as? String, !roomId.isEmpty else {
                return result(false)
            }
            let center = UNUserNotificationCenter.current()
            center.getDeliveredNotifications { delivered in
                let ids = delivered
                    .filter { n in
                        n.request.content.threadIdentifier == roomId
                            || n.request.content.userInfo["room_id"] as? String == roomId
                    }
                    .map { $0.request.identifier }
                if !ids.isEmpty {
                    center.removeDeliveredNotifications(withIdentifiers: ids)
                }
                DispatchQueue.main.async { result(true) }
            }
        case "deliveredRoomIds":
            UNUserNotificationCenter.current().getDeliveredNotifications { delivered in
                var rooms: [String] = []
                for n in delivered {
                    let content = n.request.content
                    let room = (content.userInfo["room_id"] as? String)
                        ?? (content.threadIdentifier.isEmpty ? nil : content.threadIdentifier)
                    if let room = room, !rooms.contains(room) { rooms.append(room) }
                }
                DispatchQueue.main.async { result(rooms) }
            }
        case "getNotificationSettings":
            // Парная реализация к macOS: клиент обязан уметь отличить «ОС
            // подавила бейдж/баннер» от «мы не записали». На iOS `trySet` до
            // permission-латча выходит МОЛЧА (`_permissionFlowDone`), а
            // `_denied` при этом остаётся false — по логу это неотличимо от
            // успешной записи. Спрашиваем саму систему.
            UNUserNotificationCenter.current().getNotificationSettings { s in
                DispatchQueue.main.async {
                    result([
                        "authorization": s.authorizationStatus.rawValue,
                        "alert": s.alertSetting.rawValue,
                        "badge": s.badgeSetting.rawValue,
                        "sound": s.soundSetting.rawValue,
                    ])
                }
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }


    // MARK: - Called from AppDelegate

    public static func didRegisterForRemoteNotifications(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        pendingToken = token
        channel?.invokeMethod("onToken", arguments: token)

        if let pending = pendingTokenResult {
            pending(token)
            pendingTokenResult = nil
        }
    }

    public static func didFailToRegisterForRemoteNotifications(error: Error) {
        if let pending = pendingTokenResult {
            pending(FlutterError(
                code: "REGISTRATION_FAILED",
                message: error.localizedDescription,
                details: nil
            ))
            pendingTokenResult = nil
        }
    }

    public static func didReceiveRemoteNotification(userInfo: [AnyHashable: Any]) {
        channel?.invokeMethod("onMessage", arguments: userInfo)
    }

    /// Called from AppDelegate when user taps a remote notification (from NSE).
    /// Extracts room_id and event_id from userInfo and forwards to Flutter.
    /// If Flutter engine isn't ready yet (cold start), stores as pending.
    public static func didReceiveNotificationTap(userInfo: [AnyHashable: Any]) {
        let roomId = userInfo["room_id"] as? String ?? ""
        let eventId = userInfo["event_id"] as? String ?? ""
        // client_name — аккаунт-адресат при мультиаккаунте (Sygnal мержит
        // pusher.data.default_payload в top-level userInfo).
        let clientName = userInfo["client_name"] as? String ?? ""
        let payload: [String: String] = [
            "room_id": roomId,
            "event_id": eventId,
            "client_name": clientName,
        ]
        if let ch = channel {
            ch.invokeMethod("onNotificationTap", arguments: payload)
        } else {
            // Flutter not ready yet — store for delivery after registration
            pendingNotificationTap = payload
        }
    }
}
