import Cocoa
import FlutterMacOS

/// Чтение НЕСКОЛЬКИХ растровых изображений из системного буфера (macOS).
///
/// Пакет `pasteboard` делает `NSPasteboard.readObjects([NSImage]).first` —
/// читает ВСЕ картинки, но отдаёт лишь первую. Когда в буфере несколько растров
/// (отдельные `NSPasteboardItem` с `public.tiff`/`public.png`), пользователь мог
/// вставить их только по одной. Плагин возвращает ВСЕ как PNG, клиент кладёт их
/// одним альбомом в `SendFileDialog`.
///
/// Совпадает с `MethodChannel('liza/clipboard')` в
/// `lib/utils/clipboard_paste.dart` (метод `images`).
public class ClipboardImagesPlugin: NSObject, FlutterPlugin {
    private static let channelName = "liza/clipboard"

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger
        )
        registrar.addMethodCallDelegate(ClipboardImagesPlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "images" else {
            result(FlutterMethodNotImplemented)
            return
        }
        // Все NSImage из буфера. Каждую нормализуем в PNG через NSBitmapImageRep
        // (буфер может нести tiff/other) — клиент получает единый mimeType.
        let objects = NSPasteboard.general.readObjects(
            forClasses: [NSImage.self],
            options: nil
        ) as? [NSImage] ?? []
        let pngs: [FlutterStandardTypedData] = objects.compactMap { image in
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:])
            else { return nil }
            return FlutterStandardTypedData(bytes: png)
        }
        result(pngs)
    }
}
