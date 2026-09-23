import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';

/// Авто-захват КАНДИДАТА визуального эталона по факту зелёного e2e-кейса.
///
/// Кандидат ≠ эталон: файл пишется во ВРЕМЕННЫЙ каталог и служит материалом для
/// ручной приёмки. Эталоном Яруса B он становится ТОЛЬКО после визуальной сверки
/// человеком через `scripts/e2e/snap-feature.sh` (иначе зафиксируется кадр,
/// который никто не смотрел = ложно-зелёный навсегда).
///
/// ВНИМАНИЕ — данные ЛОКАЛЬНЫЕ. Кадр снят против сид-стека (`APP_ENV=local`,
/// `make local-seed-e2e`: юзеры testuser*, чат «e2e ping/pong»), а НЕ на проде.
/// Он годится как регрессионный/структурный кандидат, но НЕ как прод-эталон:
/// классы багов «массовое исчезновение аватарок», федерация (cross-HS), реальные
/// mxc-медиа видны только на ПРОДОВЫХ данных (см. `tests/prod-data-testing.md`).
/// Прод-точный эталон Яруса B снимается вручную с macOS-сборки, залогиненной в
/// прод-сессию (`screencapture -o -l <windowID>`), и подаётся в snap-feature.sh.
///
/// Прогон идёт через `flutter test` без `test_driver`, поэтому
/// `binding.takeScreenshot()` не годится (он требует драйвера с onScreenshot).
/// Снимаем напрямую с дерева рендера через `RepaintBoundary.toImage()` + dart:io.
///
/// Куда пишем: macOS-приложение под app-sandbox НЕ может писать в `/tmp`
/// (Operation not permitted). Поэтому кладём в sandbox-safe Documents-каталог
/// контейнера (`getApplicationDocumentsDirectory()/liza-e2e-shots/`); наружу в
/// `/tmp/liza-e2e-shots/<sha>/` их забирает `scripts/e2e/run-all.sh` после фазы.
/// Имя файла `<key>.png`, где `key = '<RL-slug>__<имя-кейса>'` — префикс-slug
/// связывает кадр с записью реестра `tests/registry/RL-<slug>.md` и аргументом
/// snap-feature.sh.
///
/// Захват никогда не валит тест: любая ошибка (нет boundary, анимация, I/O,
/// недоступный плагин) гасится и логируется — визуальный кандидат вторичен по
/// отношению к ассертам.
Future<void> snapCandidate(WidgetTester tester, String key) async {
  try {
    // Снимок только на устоявшемся кадре — иначе поймаем середину анимации.
    try {
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
    } catch (_) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    final finder = find.byType(RepaintBoundary);
    if (finder.evaluate().isEmpty) return;
    // Первый RepaintBoundary при обходе сверху-вниз — самый внешний (ближе к
    // корню, покрывает вьюпорт целиком). Для сверки глазами кадрирование не
    // обязано быть пиксельно-точным.
    final boundary = tester.firstRenderObject<RenderRepaintBoundary>(finder);

    final image = await boundary.toImage(
      pixelRatio: tester.view.devicePixelRatio,
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/liza-e2e-shots')
      ..createSync(recursive: true);
    final file = File('${dir.path}/$key.png');
    file.writeAsBytesSync(bytes.buffer.asUint8List());
    // ignore: avoid_print
    print('📸 e2e candidate: ${file.path}');
  } catch (e) {
    // ignore: avoid_print
    print('e2e snapCandidate пропущен ($key): $e');
  }
}
