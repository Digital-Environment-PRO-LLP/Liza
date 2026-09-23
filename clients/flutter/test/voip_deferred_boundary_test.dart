@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ledger:RL-voip-deferred-chunk
//
// Звонилка вынесена в отдельный deferred-чанк (2026-08-27): `flutter_webrtc`
// плюс экран `pages/dialer` — это ~214 КБ сырых / ~42 КБ brotli, которые
// раньше ехали в main.dart.js каждому пользователю, включая тех, кто ни разу
// не звонил.
//
// Граница держится на ОДНОМ правиле: `voip_plugin.dart` упоминается ровно в
// одном месте — deferred-импортом в `voip_loader.dart`. Достаточно одного
// обычного `import 'package:liza/utils/voip_plugin.dart'` где-нибудь ещё,
// чтобы dart2js вернул весь webrtc-стек в основной чанк. Компилятор на это
// НЕ ругается — сборка останется зелёной, а выигрыш молча исчезнет. Отсюда
// страж на уровне исходников.
void main() {
  final libDir = Directory('lib');

  List<File> dartFiles() => libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test(
    'AC:RL-voip-deferred-chunk/1 — voip_plugin импортируется ТОЛЬКО '
    'deferred-импортом в voip_loader.dart',
    () {
      final offenders = <String>[];

      for (final file in dartFiles()) {
        if (file.path.endsWith('utils/voip/voip_loader.dart')) continue;

        for (final line in file.readAsLinesSync()) {
          final trimmed = line.trim();
          if (!trimmed.startsWith('import ')) continue;
          if (!trimmed.contains('voip_plugin.dart')) continue;
          offenders.add('${file.path}: $trimmed');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'voip_plugin.dart импортирован вне voip_loader.dart:\n'
            '${offenders.join('\n')}\n\n'
            'Любой такой импорт втягивает flutter_webrtc и pages/dialer '
            'обратно в main.dart.js. Нужен доступ к звонилке — расширь '
            'интерфейс VoipHandle (utils/voip/voip_handle.dart), а не '
            'импортируй реализацию.',
      );
    },
  );

  test(
    'AC:RL-voip-deferred-chunk/2 — loader держит deferred-импорт, '
    'а matrix.dart работает через интерфейс',
    () {
      final loader = File('lib/utils/voip/voip_loader.dart');
      expect(loader.existsSync(), isTrue, reason: 'загрузчик пропал');
      expect(
        loader.readAsStringSync(),
        contains("deferred as voip_impl"),
        reason: 'в loader пропал deferred-импорт — чанк схлопнется в основной',
      );

      // matrix.dart — корневой виджет; конкретный тип VoipPlugin в его поле
      // вернул бы webrtc в главный чанк (deferred-типы нельзя в сигнатурах).
      final matrix = File('lib/widgets/matrix.dart').readAsStringSync();
      expect(
        matrix,
        contains('VoipHandle? voipPlugin'),
        reason: 'поле voipPlugin в matrix.dart должно быть типа VoipHandle',
      );
      // Ищем ТИП в коде, а не подстроку: `createVoipPlugin()` — легальное
      // имя метода, а `VoipPlugin` в докстроке объясняет саму границу.
      // Ловим объявления/конструкторы: `VoipPlugin foo`, `VoipPlugin? foo`,
      // `= VoipPlugin(`, `as VoipPlugin`.
      final typeUsage = RegExp(
        r'(^|[^A-Za-z_/*])VoipPlugin\s*[?<]?\s*(\w+\s*[;=,)]|\()',
        multiLine: true,
      );
      final hits = typeUsage
          .allMatches(matrix)
          .map((m) => m.group(0)!.trim())
          .where((h) => !h.startsWith('create'))
          .toList();
      expect(
        hits,
        isEmpty,
        reason: 'matrix.dart использует ТИП VoipPlugin ($hits) — webrtc '
            'вернётся в основной чанк. Поле и переменные держи на VoipHandle.',
      );
    },
  );

  test(
    'AC:RL-voip-deferred-chunk/3 — чанк не грузится без флага '
    'experimentalVoip (иначе deferred бессмысленен)',
    () {
      final matrix = File('lib/widgets/matrix.dart').readAsStringSync();

      // Гейт обязан быть ОТРИЦАНИЕМ: `if (!experimentalVoip) { ...; return; }`.
      // До 2026-08-27 условие было инвертировано (плагин создавался именно
      // БЕЗ флага), поэтому чанк тянулся на старте у всех и вынос не давал
      // ничего — измерено в браузере: main.dart.js_320.part.js грузился
      // сразу после старта.
      expect(
        matrix,
        contains('if (!AppSettings.experimentalVoip.value) {'),
        reason: 'гейт звонилки должен быть «нет флага -> нет плагина». '
            'Если условие снова станет прямым, webrtc-чанк начнёт '
            'качаться при каждом запуске, и весь вынос обнулится.',
      );
    },
  );
}
