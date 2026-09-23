// Страж регрессии (ledger:RL-read-receipt-prompt-send): квитанция прочтения на
// только что прочитанное сообщение НЕ должна теряться из-за того, что предыдущий
// запрос ещё в полёте. Иначе аватарка «прочитал» у собеседника появлялась только
// после нашего ответного сообщения, а не сразу при прочтении.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/read_marker_sender.dart';

void main() {
  group('ReadMarkerSendCoordinator', () {
    test('idle: первый запрос отправляется сразу', () {
      final c = ReadMarkerSendCoordinator();
      var sends = 0;
      c.request(() {
        sends++;
        return Completer<void>().future; // остаётся в полёте
      });
      expect(sends, 1);
      expect(c.isInFlight, isTrue);
    });

    test('в полёте: повторный запрос откладывается и уходит ПО завершении '
        '[ledger:RL-read-receipt-prompt-send]', () async {
      final c = ReadMarkerSendCoordinator();
      final first = Completer<void>();
      var sends = 0;

      c.request(() {
        sends++;
        return first.future;
      });
      expect(sends, 1);

      // Пока первый в полёте — второй (на более свежую позицию) не уходит сразу.
      var secondFired = false;
      c.request(() {
        sends++;
        secondFired = true;
        return Future<void>.value();
      });
      expect(sends, 1, reason: 'второй запрос ждёт завершения первого');
      expect(secondFired, isFalse);

      // Завершаем первый → отложенный второй уходит немедленно.
      first.complete();
      await Future<void>.delayed(Duration.zero);
      expect(secondFired, isTrue);
      expect(sends, 2);
      expect(c.isInFlight, isFalse);
    });

    test('несколько отложенных схлопываются в ОДИН — последний (самый свежий)', () async {
      final c = ReadMarkerSendCoordinator();
      final first = Completer<void>();
      final fired = <int>[];

      c.request(() {
        fired.add(0);
        return first.future;
      });
      // Три обращения подряд, пока первый в полёте.
      c.request(() {
        fired.add(1);
        return Future<void>.value();
      });
      c.request(() {
        fired.add(2);
        return Future<void>.value();
      });
      c.request(() {
        fired.add(3);
        return Future<void>.value();
      });

      expect(fired, [0], reason: 'пока в полёте — ничего нового не уходит');

      first.complete();
      await Future<void>.delayed(Duration.zero);

      // Уходит только ПОСЛЕДНИЙ накопленный (самая свежая позиция), не все три.
      expect(fired, [0, 3]);
      expect(c.isInFlight, isFalse);
    });

    test('send вернул null (гейты заблокировали) — не в полёте, следующий уходит сразу', () {
      final c = ReadMarkerSendCoordinator();
      var sends = 0;

      c.request(() {
        sends++;
        return null; // заблокировано гейтами
      });
      expect(sends, 1);
      expect(c.isInFlight, isFalse);

      // Раз ничего не в полёте — следующий запрос уходит немедленно.
      c.request(() {
        sends++;
        return Completer<void>().future;
      });
      expect(sends, 2);
      expect(c.isInFlight, isTrue);
    });

    test('цепочка: pending, пришедший во время повторной отправки, тоже уходит', () async {
      final c = ReadMarkerSendCoordinator();
      final first = Completer<void>();
      final second = Completer<void>();
      final fired = <int>[];

      c.request(() {
        fired.add(0);
        return first.future;
      });
      // Накопили pending #1 (он станет «в полёте» после завершения первого).
      c.request(() {
        fired.add(1);
        return second.future;
      });

      first.complete();
      await Future<void>.delayed(Duration.zero);
      expect(fired, [0, 1]);
      expect(c.isInFlight, isTrue, reason: 'второй теперь в полёте');

      // Пока второй в полёте — накапливаем ещё один pending.
      c.request(() {
        fired.add(2);
        return Future<void>.value();
      });
      expect(fired, [0, 1]);

      second.complete();
      await Future<void>.delayed(Duration.zero);
      expect(fired, [0, 1, 2]);
      expect(c.isInFlight, isFalse);
    });

    test('отложенный pending переживает гейт-блок при повторе (send→null) и не зависает', () async {
      final c = ReadMarkerSendCoordinator();
      final first = Completer<void>();
      final fired = <int>[];

      c.request(() {
        fired.add(0);
        return first.future;
      });
      // pending, который при срабатывании окажется заблокирован гейтами (null).
      c.request(() {
        fired.add(1);
        return null;
      });

      first.complete();
      await Future<void>.delayed(Duration.zero);

      expect(fired, [0, 1], reason: 'pending попытался отправиться');
      expect(c.isInFlight, isFalse, reason: 'send вернул null → ничего не в полёте');
    });
  });
}
