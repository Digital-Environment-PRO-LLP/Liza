import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:liza/pages/chat/events/mini_app_choice_content.dart';

// Страж РЕГРЕССИИ ledger:RL-avatar-thumbnailable-png-transcode.
//
// Инвариант: аватар бота перекодируется движком в PNG (даунскейл 512) перед
// загрузкой, чтобы Synapse его тумбнейлил (avif/heic он НЕ тумбнейлит → аватар
// падает на букву-заглушку); недекодируемый вход → null (грузим сырьё как есть).
//
// ⚠️ ПОЗИТИВНЫЙ путь (валидная картинка → PNG-байты, ширина 512) зависит от
// РЕАЛЬНОГО движка `dart:ui` (Skia-кодек), которого в headless `flutter test`
// НЕТ (`instantiateImageCodec` → «Codec failed to produce an image»). Он
// проверен сквозным путём вручную/на проде: avif-аватар → PNG → Synapse
// `/thumbnail` отдаёт 200 (раньше 400 → буква-заглушка). Здесь юнит-стражем
// закрываем детерминированную половину — фолбэк на сырьё при недекодируемом
// входе (частый реальный случай: svg-вектор, битый файл).
void main() {
  test('недекодируемый вход → null (фолбэк на сырьё) '
      '[ledger:RL-avatar-thumbnailable-png-transcode]', () async {
    expect(await toThumbnailablePng(Uint8List.fromList([1, 2, 3, 4, 5])), isNull);
    expect(await toThumbnailablePng(Uint8List(0)), isNull);
  });
}
