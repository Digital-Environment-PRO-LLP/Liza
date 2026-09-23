import 'dart:async';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

/// Абстракция чтения системного буфера обмена.
///
/// Нужна, чтобы логику отбора файлов при вставке (Cmd/Ctrl+V) можно было
/// тестировать без нативного буфера: в host-тесте `Pasteboard`/MethodChannel
/// недоступны. Прод-реализация — [SystemPasteboardReader]; тест подставляет
/// фейковый reader (см. RL-paste-multiple-images).
abstract class PasteboardReader {
  /// Текст из буфера (для Safari-URL-fix: URL вставляется как текст, не медиа).
  Future<String?> text();

  /// Файлы из буфера (Finder/Explorer «Copy» — уже множественно). Возвращаем
  /// готовые к чтению [XFile], а не пути: на Android буфер отдаёт `content://`-URI,
  /// который `dart:io` не откроет (`XFile('content://')` → `FileSystemException`),
  /// поэтому прод-реализация материализует их в байты В ридере. Чистая
  /// [collectPasteXFiles] остаётся платформо-независимой и тестируемой.
  Future<List<XFile>> files();

  /// Несколько растровых изображений из ОДНОГО буфера. Достижимо нативно только
  /// на macOS/iOS (`readObjects([NSImage])` / `UIPasteboard.images`); на прочих
  /// платформах — пусто (падаем на [image]).
  Future<List<Uint8List>> images();

  /// Одиночное растровое изображение (fallback: прочие платформы / один item).
  Future<Uint8List?> image();
}

/// Результат отбора при вставке из буфера.
///
/// [handledAsMedia] `false` → в буфере нет медиа (или это URL-текст) → вызывающая
/// сторона выполняет обычную текстовую вставку. `true` → [files] непусто, надо
/// открыть `SendFileDialog` с этим списком.
class PasteResult {
  final List<XFile> files;
  final bool handledAsMedia;

  const PasteResult.media(this.files) : handledAsMedia = true;
  const PasteResult.notMedia()
      : files = const [],
        handledAsMedia = false;
}

/// Чистая логика отбора файлов из буфера при вставке.
///
/// Контракт «первый непустой источник побеждает» (антидубль: одна и та же
/// Finder-копия картинки не уедет и файлом, и растром). Порядок источников:
///
///   1. текст-URL (http/https)  → НЕ медиа (вставить текстом; Safari-fix)
///   2. [PasteboardReader.files]  → все файлы          [несколько файлов]
///   3. [PasteboardReader.images] → все растры          [несколько bitmap]
///   4. [PasteboardReader.image]  → один растр          [fallback / один item]
///
/// Растрам присваиваются УНИКАЛЬНЫЕ имена (`clipboard_image_1.png…`), иначе у
/// получателя коллизия «Сохранить как» и перезапись при массовом скачивании
/// (см. RL-multi-download-collision-safe, RL-save-filename-fallback).
Future<PasteResult> collectPasteXFiles(PasteboardReader reader) async {
  // 1. URL в тексте буфера — вставить текстом, медиа НЕ трогаем (Safari на iOS
  //    кладёт превью-картинку рядом с URL; без этой проверки ссылка уехала бы
  //    картинкой). Проверка ПЕРВОЙ — инвариант, покрытый тестами URL-fix.
  final text = await reader.text();
  if (text != null && text.trim().isNotEmpty) {
    final uri = Uri.tryParse(text.trim());
    if (uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https')) {
      return const PasteResult.notMedia();
    }
  }

  // 2. Файлы из буфера (например, скопированы в Finder/Проводнике) — множественно.
  //    Ридер уже отдаёт читаемые XFile (Android — материализованные из content://).
  final files = await reader.files();
  if (files.isNotEmpty) {
    return PasteResult.media(files);
  }

  // 3. Несколько растров в одном буфере (macOS/iOS native). Пакет `pasteboard`
  //    этого не умеет (берёт .first) — читаем через нативный канал.
  final images = await reader.images();
  if (images.isNotEmpty) {
    return PasteResult.media([
      for (var i = 0; i < images.length; i++)
        _clipboardImageFile(images[i], 'clipboard_image_${i + 1}.png'),
    ]);
  }

  // 4. Одиночный растр (скриншот / «копировать изображение» / прочие платформы).
  final single = await reader.image();
  if (single != null) {
    return PasteResult.media([
      _clipboardImageFile(single, 'clipboard_image.png'),
    ]);
  }

  return const PasteResult.notMedia();
}

/// Склейка накопления: `existing` + `incoming` в одном альбоме. Порядок
/// сохраняется (сначала уже собранные, потом новые). Имена делаем уникальными —
/// два последовательных скриншота приходят как `clipboard_image.png` каждый, и
/// без ре-нумерации у получателя коллизия «Сохранить как» и перезапись при
/// массовом скачивании (RL-multi-download-collision-safe). Переименовываем
/// ТОЛЬКО коллизии (перечитываем байты лишь у них — растры буфера уже в памяти),
/// реальные файлы с уникальными именами не трогаем (не тянем их в RAM).
Future<List<XFile>> accumulate(
  List<XFile> existing,
  List<XFile> incoming,
) async {
  final result = <XFile>[...existing];
  final seen = existing.map((f) => f.name).toSet();
  for (final x in incoming) {
    if (!seen.contains(x.name)) {
      seen.add(x.name);
      result.add(x);
      continue;
    }
    final unique = _uniquifyName(x.name, seen);
    seen.add(unique);
    final bytes = await x.readAsBytes();
    result.add(
      XFile.fromData(bytes, mimeType: x.mimeType, path: unique, name: unique),
    );
  }
  return result;
}

/// Вставляет `_N` перед расширением, пока имя не станет уникальным в [seen].
String _uniquifyName(String name, Set<String> seen) {
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  var n = 2;
  var candidate = '${base}_$n$ext';
  while (seen.contains(candidate)) {
    n++;
    candidate = '${base}_$n$ext';
  }
  return candidate;
}

/// `XFile` растра из буфера с корректным именем. Ловушка cross_file: на io
/// `XFile.fromData(name:)` игнорируется — `.name` берётся из `path`. Поэтому имя
/// задаём через `path` (io) И `name` (web) — иначе `.name` пустое (исторический
/// источник пустых имён у получателя, см. RL-save-filename-fallback).
XFile _clipboardImageFile(Uint8List bytes, String name) => XFile.fromData(
      bytes,
      mimeType: 'image/png',
      path: name,
      name: name,
    );

/// Непустое имя для материализованного из `content://` файла. Android
/// `OpenableColumns.DISPLAY_NAME` может вернуть `null`/пусто → у получателя
/// пустой «Сохранить как» (RL-save-filename-fallback). Fallback —
/// `pasted_image_N` + расширение по MIME (чтобы `lookupMimeType`/detectFileType
/// на отправке узнали тип). [index] делает имена в пачке уникальными
/// (RL-multi-download-collision-safe).
String materializedClipboardName(String? rawName, String? mime, int index) {
  final trimmed = rawName?.trim() ?? '';
  if (trimmed.isNotEmpty) return trimmed;
  return 'pasted_image_${index + 1}${_extForMime(mime)}';
}

String _extForMime(String? mime) {
  switch (mime) {
    case 'image/png':
      return '.png';
    case 'image/jpeg':
      return '.jpg';
    case 'image/gif':
      return '.gif';
    case 'image/webp':
      return '.webp';
    case 'image/heic':
      return '.heic';
    default:
      return '';
  }
}

/// Прод-реализация чтения буфера поверх `pasteboard` + нативного канала
/// `liza/clipboard` (метод `images`). Таймауты живут здесь, чтобы
/// [collectPasteXFiles] оставалась чистой и тестируемой.
class SystemPasteboardReader implements PasteboardReader {
  const SystemPasteboardReader();

  static const MethodChannel _channel = MethodChannel('liza/clipboard');

  @override
  Future<String?> text() =>
      Clipboard.getData(Clipboard.kTextPlain).then((data) => data?.text);

  @override
  Future<List<XFile>> files() async {
    final raw = await Pasteboard.files().timeout(
      const Duration(seconds: 3),
      onTimeout: () => const [],
    );
    if (raw.isEmpty) return const [];
    // Android отдаёт `content://`-URI (ClipData), которые `dart:io` не откроет →
    // материализуем в байты через нативный канал. На прочих платформах путь —
    // реальный (Finder/Explorer CF_HDROP), `XFile(path)` читается напрямую.
    if (!kIsWeb &&
        Platform.isAndroid &&
        raw.any((p) => p.startsWith('content://'))) {
      return _materializeContentUris(raw);
    }
    return raw.map((path) => XFile(path)).toList();
  }

  /// Читает `content://`-URI Android-буфера в байты через нативный
  /// `resolveContentUris`. Имя берём из `OpenableColumns.DISPLAY_NAME`
  /// (нативно), с fallback на непустое [materializedClipboardName] — пустое имя
  /// у получателя даёт пустой «Сохранить как» (корень кейса, RL-save-filename-fallback).
  Future<List<XFile>> _materializeContentUris(List<String> uris) async {
    try {
      final raw = await _channel
          .invokeMethod<List<Object?>>('resolveContentUris', {'uris': uris})
          .timeout(const Duration(seconds: 10), onTimeout: () => const []);
      if (raw == null) return const [];
      final result = <XFile>[];
      for (var i = 0; i < raw.length; i++) {
        final item = raw[i];
        if (item is! Map) continue;
        final bytes = item['bytes'];
        if (bytes is! Uint8List) continue;
        final mime = item['mime'] as String?;
        final name = materializedClipboardName(item['name'] as String?, mime, i);
        result.add(XFile.fromData(bytes, mimeType: mime, path: name, name: name));
      }
      return result;
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<List<Uint8List>> images() async {
    // Несколько растров в одном буфере ОС хранит только на macOS/iOS; на прочих
    // платформах канал не зарегистрирован (MissingPluginException) — вернём
    // пусто и упадём на одиночный image().
    if (kIsWeb || !(Platform.isMacOS || Platform.isIOS)) return const [];
    try {
      final raw = await _channel
          .invokeMethod<List<Object?>>('images')
          .timeout(const Duration(seconds: 3), onTimeout: () => const []);
      if (raw == null) return const [];
      return raw.whereType<Uint8List>().toList();
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<Uint8List?> image() => Pasteboard.image.timeout(
        const Duration(seconds: 3),
        onTimeout: () => null,
      );
}
