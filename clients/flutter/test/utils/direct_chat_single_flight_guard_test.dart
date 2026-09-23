// ledger:RL-direct-chat-single-flight
// AC:RL-direct-chat-single-flight/5
//
// Source-scan: в lib/** нет прямого `.startDirectChat(` вне воронки
// `utils/direct_chat_ensure.dart`. Любой новый вызов мимо воронки возвращает
// класс «N параллельных вызовов = N личных чатов» (инцидент 2026-09-16).
//
// Red-proof (RP-5): вернуть `client.startDirectChat(` в chat_list_header.dart —
// тест перечислит файл и упадёт.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _funnel = 'lib/utils/direct_chat_ensure.dart';
final _call = RegExp(r'\.startDirectChat\(');

void main() {
  test('AC-5: lib/** зовёт startDirectChat только через ensureDirectChat', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path == _funnel) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // Комментарии с упоминанием метода — не вызовы.
        if (line.trimLeft().startsWith('//')) continue;
        if (_call.hasMatch(line)) offenders.add('$path:${i + 1}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Прямой startDirectChat вне $_funnel — используй '
          'client.ensureDirectChat(mxid): $offenders',
    );
  });
}
