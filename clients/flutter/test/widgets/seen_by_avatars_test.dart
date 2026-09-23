// Страж бага #3: под прочитанными сообщениями показываем до 10 аватарок по
// тому же overlap-принципу, что и первые, а после 10 — бейдж «+N».
//
// Реальный виджет [SeenByAvatars] (lib/pages/chat/events/message.dart) рендерит
// аватарки через Avatar, который требует Matrix-контекст (isAiUser) — полный
// widget-тест потянул бы корневой Matrix-стейт. Поэтому здесь структурный
// страж по исходнику: фиксируем сам лимит и параметрическую (без магических
// чисел) вёрстку. Геометрия выводится из `_maxShown`, поэтому проверка
// константы достаточна для защиты от регресса (откат к 3 или хардкод).
//
// Заменяет удалённые seen_by_row_{exploration,preservation}_test.dart — те
// были симуляциями несуществующего виджета SeenByRow (maxAvatars=7) и были
// ложно-зелёными относительно текущего кода.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SeenByAvatars: лимит 10 + «+N»', () {
    late String source;

    setUp(() {
      final file = File('lib/pages/chat/events/message.dart');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'Тест должен запускаться из clients/flutter/',
      );
      source = file.readAsStringSync();
    });

    test('_maxShown == 10', () {
      expect(
        RegExp(r'static const int _maxShown = 10;').hasMatch(source),
        isTrue,
        reason: 'лимит видимых аватарок должен быть 10 (баг #3)',
      );
    });

    test('обрезка идёт по _maxShown, а не по магическому числу', () {
      // sublist(0, _maxShown) и extra = receipts.length - shown.length —
      // вёрстка масштабируется от константы, поэтому смена лимита не требует
      // правок геометрии.
      expect(source.contains('receipts.sublist(0, _maxShown)'), isTrue);
      expect(
        source.contains('receipts.length > _maxShown'),
        isTrue,
        reason: 'число лишних считается от _maxShown, не хардкодом',
      );
    });
  });
}
