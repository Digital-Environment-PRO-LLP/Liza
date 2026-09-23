// Кастомный room-state, который читают через getState, ОБЯЗАН быть в
// importantStateEvents — иначе в partial-комнате он молча отдаёт null.
//
// Класс рецидивировал ЧЕТЫРЕ раза:
//   1. com.liza.chat.topology        — скрытый чат обсуждений всплывал в списке
//   2. com.liza.chat.hidden_members  — скрытый участник всплывал в списке
//   3. com.liza.chat.no_forwards     — защита от пересылки молча не действовала
//   4. com.liza.mcp.connections      — «нажимаю плюсик, ничего не происходит»
//
// Механика (matrix-4.1.0 client.dart:3115):
//   if (stateKey != null && (!room.partial || importantStateEvents.contains(type)))
//       room.setState(event);
// `Room.partial` истинна, пока таймлайн комнаты не открыт. На экранах, которые
// читают состояние ЧУЖОЙ комнаты (список чатов, настройки, изолят пушей),
// комната почти всегда partial — и незарегистрированный тип теряется.
//
// Первые три раза класс ловили люди, четвёртый — владелец на живом экране.
// Этот тест ловит пятый: он выводит типы ИЗ КОДА, а не из списка в себе,
// поэтому новый `com.liza.*` попадёт под проверку автоматически.
//
// ledger:RL-custom-state-important

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // AC:RL-custom-state-important/1
  test('каждый com.liza.* state, читаемый getState, объявлен важным', () {
    final libDir = Directory('lib');
    expect(
      libDir.existsSync(),
      isTrue,
      reason: 'тест обязан запускаться из clients/flutter',
    );

    // 1. Набор важных типов — из фактического литерала в client_manager.
    final manager = File('lib/utils/client_manager.dart').readAsStringSync();
    final block = RegExp(
      r'importantStateEvents:\s*<String>\{(.*?)\n      \},',
      dotAll: true,
    ).firstMatch(manager);
    expect(block, isNotNull, reason: 'не найден литерал importantStateEvents');
    final importantBlock = block!.group(1)!;

    // Константы-идентификаторы (`channelNoForwardsState`) резолвим по значению
    // объявления: в блоке они стоят именем, а в getState — значением.
    final constValues = <String, String>{};
    for (final f in libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      for (final m in RegExp(
        r"const\s+String\s+(\w+)\s*=\s*'(com\.liza\.[\w.]+)'",
      ).allMatches(f.readAsStringSync())) {
        constValues[m.group(1)!] = m.group(2)!;
      }
    }

    final important = <String>{
      ...RegExp("'(com\\.liza\\.[\\w.]+)'")
          .allMatches(importantBlock)
          .map((m) => m.group(1)!),
      for (final entry in constValues.entries)
        if (RegExp('\\b${entry.key}\\b').hasMatch(importantBlock)) entry.value,
    };

    // 2. Типы, которые КОД реально читает через getState — прямым литералом
    //    либо через константу.
    final read = <String, String>{}; // тип -> где прочитан
    final getStateRe = RegExp(r'getState\(\s*(?:'
        "'(com\\.liza\\.[\\w.]+)'"
        r'|(\w+)\s*)');
    for (final f in libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      for (final m in getStateRe.allMatches(src)) {
        final literal = m.group(1);
        final ident = m.group(2);
        final type = literal ?? constValues[ident];
        if (type == null || !type.startsWith('com.liza.')) continue;
        read.putIfAbsent(type, () => f.path);
      }
    }

    expect(
      read,
      isNotEmpty,
      reason: 'ни одного чтения com.liza.*-state не найдено — сломался парсер '
          'теста, а не код: почини регулярку, не глуши тест',
    );

    // Осознанные исключения. Промоушен типа ПОСТФАКТУМ — миграция, а не
    // бесплатная строка: значение, записанное до промоушена, уходит в
    // non-preload-бокс, а `postLoad()` важные типы ИСКЛЮЧАЕТ (подробно —
    // client_manager.dart). Значит «промотировать на всякий случай» может
    // СЛОМАТЬ то, что сейчас работает. Поэтому каждый тип — с причиной.
    const exempt = <String, String>{
      // Читается из `event.room` при просмотре видео, т.е. чат уже открыт и
      // комната не partial. Класс не применим.
      'com.liza.media_variants': 'читается только внутри открытого чата',
      // Аватарки прочитавших рисуются только в открытом таймлайне, а
      // getTimeline() делает postLoad() — неважные состояния уже в памяти.
      'com.liza.chat.hide_read_receipts':
          'читается только внутри открытого чата (getTimeline → postLoad)',
      // ⚠️ ПОДОЗРЕВАЕМЫЕ того же класса, найдены этим стражем 2026-09-10.
      // Читаются по ЧУЖОЙ комнате (список чатов / канал), где partial
      // вероятна. Не промотированы намеренно: промоушен постфактум сделает
      // нечитаемыми уже записанные значения и может сломать работающее
      // поведение. Нужна отдельная проверка с миграционным решением —
      // см. RL-custom-state-important, раздел «Подозреваемые».
      'com.liza.miniapp.config': 'подозреваемый: нужна отдельная миграция',
      'com.liza.channel.stories': 'подозреваемый: нужна отдельная миграция',
    };

    final missing = {
      for (final e in read.entries)
        if (!important.contains(e.key) && !exempt.containsKey(e.key))
          e.key: e.value,
    };

    expect(
      missing,
      isEmpty,
      reason:
          'эти кастомные state-типы читаются через getState, но НЕ объявлены в '
          'importantStateEvents (client_manager.dart). В partial-комнате '
          'getState вернёт для них null, и фича молча не сработает — это уже '
          'случалось 4 раза:\n'
          '${missing.entries.map((e) => '  ${e.key}  ← ${e.value}').join('\n')}',
    );
  });
}
