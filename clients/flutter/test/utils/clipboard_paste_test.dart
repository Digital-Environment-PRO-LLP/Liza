// Страж мультивставки изображений из буфера.
//
// Тестирует РЕАЛЬНУЮ логику отбора `collectPasteXFiles` (не реплику — снимает
// MOCK_ONLY, ср. инцидент 3704) через фейковый PasteboardReader. Нативный буфер
// в host-тесте недоступен, поэтому отбор вынесен в чистую функцию.
//
// ledger:RL-paste-multiple-images

library;

import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/clipboard_paste.dart';

/// Фейковый буфер: возвращает заранее заданные text/files/images/image.
class FakeReader implements PasteboardReader {
  final String? _text;
  final List<XFile> _files;
  final List<Uint8List> _images;
  final Uint8List? _image;

  const FakeReader({
    String? text,
    List<XFile> files = const [],
    List<Uint8List> images = const [],
    Uint8List? image,
  })  : _text = text,
        _files = files,
        _images = images,
        _image = image;

  @override
  Future<String?> text() async => _text;
  @override
  Future<List<XFile>> files() async => _files;
  @override
  Future<List<Uint8List>> images() async => _images;
  @override
  Future<Uint8List?> image() async => _image;
}

Uint8List _png(int seed) => Uint8List.fromList([137, 80, 78, 71, seed]);

void main() {
  group('collectPasteXFiles — мультивставка из буфера', () {
    // AC:RL-paste-multiple-images/1 — N файлов из буфера → РОВНО N XFile, порядок.
    for (final n in [1, 2, 3]) {
      test('AC-1: $n файлов → $n XFile, порядок сохранён', () async {
        final paths = [for (var i = 0; i < n; i++) '/tmp/pic_$i.png'];
        final r = await collectPasteXFiles(
          FakeReader(files: paths.map(XFile.new).toList()),
        );
        expect(r.handledAsMedia, isTrue);
        expect(r.files.length, n);
        expect(r.files.map((f) => f.path).toList(), paths);
      });
    }

    // AC:RL-paste-multiple-images/2 — N растров → N XFile, image/png, УНИКАЛЬНЫЕ имена.
    for (final n in [2, 3]) {
      test('AC-2: $n растров → $n XFile, image/png, уникальные имена', () async {
        final imgs = [for (var i = 0; i < n; i++) _png(i)];
        final r = await collectPasteXFiles(FakeReader(images: imgs));
        expect(r.handledAsMedia, isTrue);
        expect(r.files.length, n);
        expect(r.files.every((f) => f.mimeType == 'image/png'), isTrue);
        final names = r.files.map((f) => f.name).toList();
        expect(names.toSet().length, n, reason: 'имена должны быть уникальны');
        expect(names, [for (var i = 1; i <= n; i++) 'clipboard_image_$i.png']);
      });
    }

    // AC:RL-paste-multiple-images/3 — один скриншот → РОВНО 1 XFile (не регресс).
    test('AC-3: один растр (image, images пуст) → ровно 1 XFile', () async {
      final r = await collectPasteXFiles(FakeReader(image: _png(9)));
      expect(r.handledAsMedia, isTrue);
      expect(r.files.length, 1);
      expect(r.files.single.mimeType, 'image/png');
    });

    // AC:RL-paste-multiple-images/4 — URL-текст → НЕ медиа (Safari-fix), URL первым.
    group('AC-4: URL в буфере → текстовая вставка, медиа не триггерится', () {
      for (final url in ['https://matrix.org', 'http://example.com/a?b=1']) {
        test('$url + preview-картинка → notMedia', () async {
          final r = await collectPasteXFiles(
            FakeReader(text: url, image: _png(1), images: [_png(2)]),
          );
          expect(r.handledAsMedia, isFalse, reason: 'URL должен идти текстом');
          expect(r.files, isEmpty);
        });
      }
      test('НЕ-URL текст + картинка → медиа (контроль)', () async {
        final r = await collectPasteXFiles(
          FakeReader(text: 'просто подпись', image: _png(1)),
        );
        expect(r.handledAsMedia, isTrue);
        expect(r.files.length, 1);
      });
    });

    // AC:RL-paste-multiple-images/5 — первый непустой источник побеждает (антидубль).
    test('AC-5: files И image одновременно → только files (без дубля)', () async {
      final r = await collectPasteXFiles(
        FakeReader(
          files: [XFile('/tmp/a.png')],
          image: _png(1),
          images: [_png(2)],
        ),
      );
      expect(r.files.length, 1, reason: 'files выигрывает, image/images не читаются');
      expect(r.files.single.path, '/tmp/a.png');
    });

    test('AC-5: images И image одновременно → только images', () async {
      final r = await collectPasteXFiles(
        FakeReader(images: [_png(1), _png(2)], image: _png(9)),
      );
      expect(r.files.length, 2, reason: 'images выигрывает над одиночным image');
    });

    test('пустой буфер → notMedia (текстовая вставка)', () async {
      final r = await collectPasteXFiles(const FakeReader());
      expect(r.handledAsMedia, isFalse);
      expect(r.files, isEmpty);
    });

    // AC:RL-paste-multiple-images/9 — Windows/desktop: реальные пути читаются как есть,
    // порядок сохранён (CF_HDROP отдаёт настоящие пути, XFile(path) работает).
    for (final n in [1, 2, 3]) {
      test('AC-9: $n реальных путей (desktop CF_HDROP) → $n XFile, порядок', () async {
        final paths = [for (var i = 0; i < n; i++) 'C:/Users/npusk/pic_$i.png'];
        final r = await collectPasteXFiles(
          FakeReader(files: paths.map(XFile.new).toList()),
        );
        expect(r.files.map((f) => f.path).toList(), paths);
      });
    }
  });

  // AC:RL-paste-multiple-images/7 — имя материализованного из content:// файла.
  // Android OpenableColumns.DISPLAY_NAME бывает null/пусто → имя обязано быть
  // непустым и уникальным в пачке (иначе пустой «Сохранить как» у получателя —
  // корень кейса, RL-save-filename-fallback / RL-multi-download-collision-safe).
  group('AC-7: materializedClipboardName — непустое уникальное имя', () {
    test('реальное имя из DISPLAY_NAME сохраняется', () {
      expect(materializedClipboardName('Снимок 2026.png', 'image/png', 0),
          'Снимок 2026.png');
    });

    test('null имя → fallback pasted_image_N + расширение по MIME', () {
      expect(materializedClipboardName(null, 'image/png', 0), 'pasted_image_1.png');
      expect(materializedClipboardName('', 'image/jpeg', 1), 'pasted_image_2.jpg');
      expect(materializedClipboardName('   ', 'image/webp', 2), 'pasted_image_3.webp');
    });

    test('null MIME → fallback без расширения, но имя непустое', () {
      final name = materializedClipboardName(null, null, 0);
      expect(name, isNotEmpty);
      expect(name, 'pasted_image_1');
    });

    test('пачка из null-имён → имена уникальны по индексу', () {
      final names = [
        for (var i = 0; i < 3; i++)
          materializedClipboardName(null, 'image/png', i),
      ];
      expect(names.toSet().length, 3, reason: 'имена в пачке должны быть уникальны');
    });
  });
}
