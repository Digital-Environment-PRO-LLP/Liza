// ledger:RL-channel-peek-live-feed
// AC:RL-channel-peek-live-feed/1
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ссылка на канал ведёт в ленту, а не в диалог-превью', () {
    final source = File('lib/config/routes.dart').readAsStringSync();

    // Ищем ОПРЕДЕЛЕНИЕ функции (сигнатуру с типом возврата и параметрами), а
    // не первое текстовое совпадение — иначе индекс попадает на вызов внутри
    // GoRoute (`return _handleChannelHandle(context, handle);`), который стоит
    // раньше в файле, и окно проверки смотрит не туда.
    final defPattern = RegExp(
      r'Future<String\??>\s+_handleChannelHandle\(',
    );
    final defMatch = defPattern.firstMatch(source);
    expect(
      defMatch,
      isNotNull,
      reason: 'не нашли определение _handleChannelHandle по сигнатуре',
    );
    final start = defMatch!.start;

    // Конец функции — первая строка `}` с нулевым отступом после начала
    // определения (закрывающая скобка тела функции верхнего уровня). Это
    // устойчивее, чем substring фиксированной длины: не поедет от правок
    // соседних строк или добавления/удаления комментариев.
    final closingBrace = RegExp(r'\n\}');
    final endMatch = closingBrace.firstMatch(source.substring(start));
    expect(
      endMatch,
      isNotNull,
      reason: 'не нашли конец тела _handleChannelHandle',
    );
    final body = source.substring(start, start + endMatch!.end);

    // Проверяем не голую подстроку `PublicRoomDialog` (она встречается в
    // doc-комментарии, объясняющем, что раньше показывался диалог, — на этом
    // валидный код ложно упал бы), а признак ФАКТИЧЕСКОГО использования:
    // вызов конструктора `PublicRoomDialog(` или показ диалога вообще.
    expect(
      body.contains('PublicRoomDialog(') || body.contains('showAdaptiveDialog'),
      isFalse,
      reason: 'неподписанный пользователь обязан сразу видеть ленту (AC-1)',
    );
    expect(
      body.contains('/rooms/'),
      isTrue,
      reason: 'переход идёт на экран комнаты — там сработает peek-развилка',
    );
  });
}
