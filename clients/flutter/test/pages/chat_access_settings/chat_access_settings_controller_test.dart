import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Регресс: резолв ника канала уже чинили в chat_details.dart (домен
// пользователя -> serverNameForRoom), но второе место с тем же паттерном
// осталось на userID?.domain (см. CLAUDE.md, инцидент этой сессии). Полный
// widget-тест требует поднятого Matrix-клиента с комнатой на чужом
// хоумсервере; здесь достаточно структурно поймать возврат к
// `room.client.userID?.domain` в местах резолва ника — именно эта строка
// молча уводит запрос на сервер пользователя вместо сервера канала.
//
// Строка 470 (`addAlias`) — легитимное исключение: там нужен домен
// ПОЛЬЗОВАТЕЛЯ (алиас создаётся на его сервере), её трогать не нужно.

const _path =
    'lib/pages/chat_access_settings/chat_access_settings_controller.dart';

String _read() {
  final file = File(_path);
  expect(
    file.existsSync(),
    isTrue,
    reason: 'Тест должен запускаться из clients/flutter/ (нет $_path)',
  );
  return file.readAsStringSync();
}

void main() {
  test('резолв ника канала идёт через serverNameForRoom, не userID.domain', () {
    final source = _read();

    // Импорт публичной функции обязателен — без него подстановка невозможна.
    expect(
      source,
      contains('serverNameForRoom'),
      reason:
          'Контроллер должен использовать serverNameForRoom(room.id) из '
          'chat_details.dart для резолва ника канала',
    );

    // Разбиваем файл по методам и проверяем каждый метод резолва ника
    // отдельно — grep по всему файлу пропустил бы регресс, если легитимная
    // addAlias() (строка ~470, домен пользователя нужен по смыслу) стоит
    // рядом с испорченным методом резолва ника.
    final loadMethod = _extractMethod(source, '_loadChannelHandle');
    final saveMethod = _extractMethod(source, 'saveChannelHandle');
    final addAliasMethod = _extractMethod(source, 'addAlias');

    for (final entry in {
      '_loadChannelHandle': loadMethod,
      'saveChannelHandle': saveMethod,
    }.entries) {
      expect(
        entry.value,
        isNot(contains('userID?.domain')),
        reason:
            '${entry.key} резолвит ник КАНАЛА — домен пользователя '
            '(room.client.userID?.domain) для этого не годится, нужен '
            'serverNameForRoom(room.id)',
      );
      expect(
        entry.value,
        contains('serverNameForRoom(room.id)'),
        reason: '${entry.key} обязан брать домен через serverNameForRoom',
      );
    }

    // addAlias создаёт alias НА СВОЁМ сервере — там userID?.domain корректен
    // по смыслу, страж не должен его ломать (иначе это ложный "фикс").
    expect(
      addAliasMethod,
      contains('userID?.domain'),
      reason:
          'addAlias создаёт алиас на сервере пользователя — легитимное '
          'использование userID?.domain, не трогать',
    );
  });
}

/// Вырезает тело метода/функции по имени — от объявления до строки с
/// закрывающей скобкой на нулевом уровне отступа внутри класса (эвристика
/// достаточна для плоских async-методов этого файла, не претендует на
/// парсинг Dart).
String _extractMethod(String source, String name) {
  final startPattern = RegExp('\\b$name\\s*\\(');
  final match = startPattern.firstMatch(source);
  expect(match, isNotNull, reason: 'Метод $name не найден в исходнике');
  final start = match!.start;
  var depth = 0;
  var bodyStarted = false;
  for (var i = start; i < source.length; i++) {
    final char = source[i];
    if (char == '{') {
      depth++;
      bodyStarted = true;
    } else if (char == '}') {
      depth--;
      if (bodyStarted && depth == 0) {
        return source.substring(start, i + 1);
      }
    }
  }
  fail('Не удалось найти конец метода $name');
}
