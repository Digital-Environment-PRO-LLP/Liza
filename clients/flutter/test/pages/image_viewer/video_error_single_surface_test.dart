import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Провал воспроизведения видео в просмотрщике показывает РОВНО ОДНУ поверхность
// сообщения — центральный error-overlay. Второй поверхности (SnackBar) быть не
// должно ни на одном пути провала.
//
// Регресс, который сторожим (владелец, 2026-09-04, скрин Саши): на экране разом
// висели оверлей «Не удалось воспроизвести видео» + плашка «Ой, что-то пошло не
// так…», обе с кнопкой «Повторить». Родился в 1dbabb74 (2026-05-26): одна строка
// рендера `_buildPoster` → `_buildErrorOverlay` превратила немую заглушку в
// полноценную поверхность, а парный вызов SnackBar рядом никто не снял.
//
// Почему source-scan, а не widget-тест: поверхности рождаются в async-колбэках
// libmpv (`_handlePlaybackError`, `_maybeSwapOnFatalLog`, `on IOException`), для
// которых на host нет детерминированного триггера — реальный рендер сторожит
// device-flow `integration_test/liza/video_no_download_flow_test.dart`
// (AC:RL-video-viewer-save-and-overlay/6 AC:RL-video-viewer-save-and-overlay/7). Здесь ловим САМ ИСТОЧНИК дубля:
// появление второго писателя поверхности в коде. Тот же приём, что у
// `AC:RL-monitoring-fleet-heartbeat/2`.
//
// ledger:RL-video-viewer-save-and-overlay

const _playerPath = 'lib/pages/image_viewer/video_player.dart';

String _read(String path) {
  final file = File(path);
  expect(
    file.existsSync(),
    isTrue,
    reason: 'Тест должен запускаться из clients/flutter/ (нет $path)',
  );
  return file.readAsStringSync();
}

/// Схлопывает пробелы/переносы: `dart format` рвёт вызовы по-разному в
/// зависимости от отступа, а нам важен смысл, не раскладка.
String _normalize(String source) => source.replaceAll(RegExp(r'\s+'), ' ');

/// Вырезает участок исходника от [start] до [end] (не включая). Индексы, а не
/// регулярка на всё тело: тело метода растёт при правках, и regex с лимитом
/// длины молча перестаёт матчить — тест «зеленел бы» по той же причине, по
/// которой проехал сам регресс.
String _section(String source, String start, String end) {
  final from = source.indexOf(start);
  expect(from, isNot(-1), reason: 'не найден маркер «$start» — тест устарел');
  final to = source.indexOf(end, from + start.length);
  expect(to, isNot(-1), reason: 'не найден конец «$end» после «$start»');
  return source.substring(from, to);
}

void main() {
  group('одна поверхность ошибки видео', () {
    test(
      'AC:RL-video-viewer-save-and-overlay/6 — ни один путь провала не показывает '
      'SnackBar (вторая поверхность запрещена)',
      () {
        final source = _normalize(_read(_playerPath));

        expect(
          source.contains('_showVideoErrorDialog'),
          isFalse,
          reason: 'SnackBar-поверхность ошибки воспроизведения удалена: '
              'единственное сообщение — центральный error-overlay',
        );
        // Именно ВЫЗОВЫ, а не определение: `_scaffoldMessenger.clearSnackBars()`
        // в dispose/_enterErrorState остаётся — он очередь ЧИСТИТ, а не создаёт.
        expect(
          RegExp(r'_showSnackBar\s*\(').allMatches(source).length,
          0,
          reason: 'в просмотрщике видео SnackBar не показывается ни на одном '
              'пути: все провалы ведут в error-overlay',
        );
      },
    );

    test(
      'AC:RL-video-viewer-save-and-overlay/7 — сетевая ошибка скачивания ведёт в '
      'overlay, а не в SnackBar поверх вечного спиннера',
      () {
        final source = _read(_playerPath);

        // До фикса ветка `on IOException` показывала SnackBar на 4с и НЕ ставила
        // `_showErrorFallback` → под плашкой оставался `_buildDownloadOverlay`,
        // то есть бесконечный крутящийся индикатор без кнопки. Навсегда.
        final ioBranch = _section(source, 'on IOException catch', '} catch (');
        expect(
          ioBranch,
          contains('_enterErrorState'),
          reason: 'IOException обязан переводить экран в error-overlay, иначе '
              'класс провала остаётся немым под вечным спиннером',
        );
        // Именно вызов показа, а не слово: в ветке остался комментарий, который
        // объясняет, почему прежний SnackBar убран.
        expect(
          ioBranch,
          isNot(contains('_showSnackBar(')),
          reason: 'на IO-пути показ SnackBar заменён общим error-overlay',
        );
      },
    );

    test(
      'AC:RL-video-viewer-save-and-overlay/8 — у error-overlay есть тёмный scrim '
      '(текст читаем на светлом кадре)',
      () {
        final source = _read(_playerPath);

        // Оверлей рисуется ПОВЕРХ постера (BoxFit.cover): без подложки белый
        // текст нечитаем на светлом кадре. Пока снизу висел Material-SnackBar с
        // контрастным фоном, это маскировалось; став единственной поверхностью,
        // оверлей обязан нести scrim сам — как соседний _buildDownloadOverlay.
        final overlay = _normalize(
          _section(source, 'Widget _buildErrorOverlay(', 'Повторная попытка'),
        );
        expect(
          overlay,
          contains('Colors.black54'),
          reason: 'AC-3 записи RL требует тёмный scrim под текстом overlay',
        );
        // Якорь для скоупа ассертов device-flow (иначе finder'ы меряют весь экран).
        expect(
          overlay,
          contains("Key('video-error-overlay')"),
          reason: 'корень overlay нуждается в стабильном Key',
        );
      },
    );

    test(
      'AC:RL-video-viewer-save-and-overlay/10 — провал свапа на локальный файл '
      'терминален с ЛЮБОЙ точки входа (в т.ч. из watchdog)',
      () {
        final source = _read(_playerPath);

        // Дыра, которую сторожим: watchdog звал `_swapToLocal()` fire-and-forget
        // (`// ignore: discarded_futures`), а сам метод был `try/finally` БЕЗ
        // catch. Бросок из скачивания улетал в zone-хендлер, где сетевой класс
        // ещё и отфильтрован (`Monitoring._isNetworkError`) → `_showErrorFallback`
        // не ставился НИКОГДА: мёртвый кадр без «Повторить» и ноль телеметрии.
        // Второй вход в метод появился уже ПОСЛЕ фикса LABA-2557 и контракт
        // вызывающих не соблюл — поэтому терминал обязан жить внутри метода.
        final swap = _normalize(
          _section(source, 'Future<void> _swapToLocal(', '`Player.stream.error` — это'),
        );
        expect(
          swap,
          contains('catch'),
          reason: 'у _swapToLocal обязан быть собственный catch: вызывающие '
              'уже один раз забыли обернуть',
        );
        expect(
          swap,
          contains('_enterErrorState'),
          reason: 'провал свапа обязан заканчиваться error-overlay, а не немым '
              'мёртвым кадром',
        );
        expect(
          swap,
          contains("_reportVideoFailure('swap-failed'"),
          reason: 'телеметрия swap-failed обязана жить ВНУТРИ метода: иначе '
              'watchdog-путь (тот самый, где был баг) остаётся слепым',
        );
        // Никаких fire-and-forget вызовов без обработки: если метод снова
        // станет бросающим, `discarded_futures` вернёт исходную немоту.
        expect(
          _normalize(source),
          isNot(contains('ignore: discarded_futures _swapToLocal')),
          reason: 'вызов свапа не должен глушиться игнором анализатора',
        );
      },
    );

    test(
      'AC:RL-video-viewer-save-and-overlay/12 — индикатор буферизации снимается '
      'вместе со свапом (не переживает успешное восстановление)',
      () {
        final source = _read(_playerPath);

        // Единственный писатель `_pausedForCache` — адаптивный монитор, а он
        // после свапа замолкает навсегда (ранний return по `_useLocalFile`).
        // Сброс есть только в `_retryPlayback`, куда с играющего видео уже не
        // попасть → спиннер висел поверх нормально играющего файла до конца
        // просмотра. Комбинация не редкая: свап по stalled-reconnect
        // срабатывает ровно при `paused-for-cache=yes`.
        final swap = _normalize(
          _section(source, 'Future<void> _swapToLocal(', '`Player.stream.error` — это'),
        );
        expect(
          swap,
          contains('_pausedForCache = false'),
          reason: 'кто свапнул — тот и снимает индикатор буферизации',
        );
      },
    );

    test(
      'AC:RL-video-viewer-save-and-overlay/13 — у индикатора буферизации РОВНО '
      'один писатель: контролы карусели своего спиннера не рисуют',
      () {
        final controls = _normalize(
          _read('lib/pages/image_viewer/carousel_video_controls.dart'),
        );

        // Тот же класс, что и две ошибки в LABA-2557, только про загрузку: на
        // одном затыке рисовались ДВА индикатора — свой в плеере (по mpv
        // `paused-for-cache`) и свой в контролах (по `player.stream.buffering`).
        expect(
          controls,
          isNot(contains('CircularProgressIndicator')),
          reason: 'индикатор буферизации живёт в EventVideoPlayer (его пинует '
              'AC-4); второй в контролах = две поверхности на один факт',
        );
        // Кнопку play/pause больше ничто не гейтит по буферизации: раньше на
        // затыке она исчезала целиком и поставить паузу было нечем.
        expect(
          controls,
          isNot(contains('bool _buffering')),
          reason: 'состояние буферизации в контролах не хранится',
        );
        expect(
          controls,
          isNot(contains('stream.buffering')),
          reason: 'контролы не подписаны на буферизацию: кнопку play/pause '
              'больше ничто по ней не гейтит (на затыке её нельзя было нажать)',
        );
      },
    );
  });
}
