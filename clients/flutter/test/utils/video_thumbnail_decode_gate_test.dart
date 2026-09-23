import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/resize_video.dart';

/// Синтезирует РЕАЛЬНО валидный PNG нативным кодеком (надёжнее, чем хардкод
/// байт с ручным CRC).
Future<Uint8List> makeValidPng() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 2, 2),
    ui.Paint()..color = const ui.Color(0xFF00FF00),
  );
  final image = await recorder.endRecording().toImage(2, 2);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// ledger:RL-video-thumbnail-decode-gate
///
/// Баг (2026-07-30): при отправке 3 видео галереей 2-е и 3-е показывались
/// «битой картинкой» (broken_image) в ленте отправителя. Корень — постер
/// видео (`VideoCompress.getByteThumbnail`, дефолт `position:-1` = отрицательный
/// CMTime; под нагрузкой соседнего `compressVideo` кадр 2/3 извлекается битым)
/// уходил в `info.thumbnail_url` БЕЗ проверки, что он вообще декодируется. У
/// получателя/отправителя `Image.memory` падал «Invalid image data».
///
/// `videoThumbnailBytesDecode` — гейт, который `getVideoThumbnail` применяет
/// перед заливкой: непустой-но-битый JPEG отбраковывается (шлём без постера →
/// BlurHash лучше мёртвой иконки). Тест защищает решения гейта на реальном
/// декоде нативного кодека.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('videoThumbnailBytesDecode — гейт постера видео перед заливкой', () {
    test('null → отбраковка', () async {
      expect(await videoThumbnailBytesDecode(null), isFalse);
    });

    test('пустые байты → отбраковка', () async {
      expect(await videoThumbnailBytesDecode(Uint8List(0)), isFalse);
    });

    test('усечённый-но-JPEG-сигнатурный blob → отбраковка (корень бага)',
        () async {
      // FF D8 FF (валидная сигнатура JPEG) + мусор: проскакивает magic-чек
      // self-heal, но не декодируется. Именно это уходило в постер видео 2/3.
      final truncated = Uint8List.fromList(
        <int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x00, 0xFF],
      );
      expect(await videoThumbnailBytesDecode(truncated), isFalse);
    });

    test('мусор без сигнатуры → отбраковка', () async {
      final garbage = Uint8List.fromList(List<int>.filled(64, 0x42));
      expect(await videoThumbnailBytesDecode(garbage), isFalse);
    });

    test('валидная картинка → пропускаем', () async {
      expect(await videoThumbnailBytesDecode(await makeValidPng()), isTrue);
    });
  });
}
