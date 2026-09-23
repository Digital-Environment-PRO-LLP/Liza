import Flutter
import UIKit

/// Чтение НЕСКОЛЬКИХ растровых изображений из системного буфера.
///
/// Пакет `pasteboard` отдаёт только `UIPasteboard.general.image` (одно). Когда в
/// буфере несколько картинок (`UIPasteboard.general.images` — множественное),
/// пользователь мог вставить их только по одной. Плагин возвращает ВСЕ как PNG,
/// клиент кладёт их одним альбомом в `SendFileDialog`.
///
/// Совпадает с `MethodChannel('liza/clipboard')` в
/// `lib/utils/clipboard_paste.dart` (метод `images`). На платформах без плагина
/// Dart ловит `MissingPluginException` и падает на одиночный `Pasteboard.image`.
public class ClipboardImagesPlugin: NSObject, FlutterPlugin {
    private static let channelName = "liza/clipboard"

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(ClipboardImagesPlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "images" else {
            result(FlutterMethodNotImplemented)
            return
        }
        // `UIPasteboard.general.images` — все растры буфера. Нормализуем в PNG,
        // чтобы клиент не гадал формат (mimeType image/png).
        let images = UIPasteboard.general.images ?? []
        let pngs: [FlutterStandardTypedData] = images.compactMap { image in
            guard let data = image.pngData() else { return nil }
            return FlutterStandardTypedData(bytes: data)
        }
        result(pngs)
    }
}
