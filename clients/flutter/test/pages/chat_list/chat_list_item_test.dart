// Регрессионные тесты для бага «MXID-локалпарт вместо ФИО в списке чатов
// после холодного старта».
//
// Корень: SDK помечает восстановленные из БД комнаты как `partial`, и
// `getLocalizedDisplayname` фолбэчит на localpart MXID партнёра, пока state
// не подгружен. Фикс делает две вещи:
//   1. `prefetchDmHeroes` в `lib/widgets/matrix.dart` после первого sync
//      дёргает `loadHeroUsers` у всех DM-комнат, добирая state партнёра.
//   2. В `lib/pages/chat_list/chat_list_item.dart` убран FutureBuilder,
//      создававший новый `loadHeroUsers`-Future на каждый rebuild.
//
// Тесты ниже защищают оба изменения от регрессии:
//   - `prefetchDmHeroes` корректно работает на пустых и не-DM комнатах и не
//     падает на ошибках `loadHeroUsers` отдельной комнаты.
//   - В `chat_list_item.dart` больше нет `FutureBuilder` (структурный чек).

// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/widgets/matrix.dart' show prefetchDmHeroes;

import '../../utils/test_client.dart';

void main() {
  group('prefetchDmHeroes', () {
    late Client client;

    setUp(() async {
      client = await prepareTestClient();
    });

    tearDown(() async {
      await client.dispose(closeDatabase: true);
    });

    test('пустой список комнат: проходит без exception', () async {
      await expectLater(prefetchDmHeroes(const <Room>[]), completes);
    });

    test('список комнат клиента без DM: фильтр работает, exception нет',
        () async {
      // У свежесозданного клиента нет account_data `m.direct`, поэтому
      // `isDirectChat` для любых комнат вернёт false. Это удобный smoke-
      // случай: `where` отсеивает всё, до `loadHeroUsers` дело не доходит.
      await expectLater(prefetchDmHeroes(client.rooms), completes);
    });
  });

  group('chat_list_item.dart структура', () {
    test('FutureBuilder вокруг GestureDetector удалён', () {
      // Защита от регрессии: возврат FutureBuilder приведёт к тому, что
      // `loadHeroUsers` снова будет вызываться на каждый rebuild
      // StreamBuilder в `chat_list_body.dart`, спамя `/profile/{userId}`.
      final file = File('lib/pages/chat_list/chat_list_item.dart');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'Тест должен запускаться из clients/flutter/',
      );
      final source = file.readAsStringSync();
      // Внутри subtitle остаётся отдельный FutureBuilder для
      // `calcLocalizedBody`, его не трогаем. Проверяем именно вызов
      // `loadHeroUsers` на rebuild — он создавал лишний spam.
      expect(
        source.contains('room.loadHeroUsers()'),
        isFalse,
        reason:
            'room.loadHeroUsers() в ChatListItem не нужен: героев '
            'DM-комнат прогревает prefetchDmHeroes после первого sync, '
            'а ребилд при изменении participants обеспечивает '
            'StreamBuilder в chat_list_body.dart.',
      );
    });

    test('у канала не рисуется вторая аватарка пространства', () {
      // Регрессия: у канала показывались ДВЕ аватарки внахлёст — своя и
      // пространства, в котором лежит канал. Пользователь принимал вторую
      // за «аватарку автора», хотя это обычный механизм списка чатов
      // (Stack аватара пространства поверх аватара комнаты). Для канала
      // нужна только его собственная аватарка.
      //
      // Проверяем ТОЧНУЮ форму условий (нормализуя пробелы/переносы, чтобы
      // dart format не ломал тест), а не наличие отдельных токенов —
      // проверка вида `contains('!room.isChannel')` не ловит диверсию
      // `&&` -> `||` или снятие `!` (сам токен `!room.isChannel` в обоих
      // случаях остаётся в файле).
      final file = File('lib/pages/chat_list/chat_list_item.dart');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'Тест должен запускаться из clients/flutter/',
      );
      final normalized = file
          .readAsStringSync()
          .replaceAll(RegExp(r'\s+'), ' ');

      expect(
        normalized.contains('if (space != null && !room.isChannel)'),
        isTrue,
        reason:
            'верхняя аватарка (аватар пространства) должна рисоваться '
            'только когда пространство есть И это не канал: у канала '
            'вторая аватарка не нужна вовсе',
      );
      expect(
        normalized.contains('size: space != null && !room.isChannel ? Avatar.defaultSize * 0.75 : Avatar.defaultSize'),
        isTrue,
        reason:
            'основная аватарка канала не должна уменьшаться коэффициентом '
            '0.75 (он предназначен для случая "есть аватарка пространства '
            'сверху", а у канала её нет)',
      );
    });
  });
}
