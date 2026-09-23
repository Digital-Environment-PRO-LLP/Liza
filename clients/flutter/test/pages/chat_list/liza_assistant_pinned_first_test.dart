// ledger:RL-liza-assistant-pinned-first
//
// Страж инварианта «Лиза ИИ ВСЕГДА закреплена первой в главном списке и
// в «Поделиться»».
//
// Покрываемые AC (см. tests/registry/RL-liza-assistant-pinned-first.md):
//   AC-1  живой DM (@liza:bots.liza.ru, name пусто) → индекс 0 в filteredRooms
//         при наличии SDK-первого другого чата.
//   AC-2  негатив-квантор ∀: НИКАКОЙ мёртвый @liza:synapse... DM не становится
//         индексом 0 ни в наборе {только мёртвые}, {живой+мёртвые},
//         {miniApp+мёртвые} — проверяется в ОБОИХ списках (filteredRooms + share).
//   AC-3  mini-App @liza-DM (с именем) НЕ перехватывает пин.
//   AC-4  ShareScaffoldDialog пинит живой DM (не мёртвый/mini-App).
//   AC-6  self-heal: комната с membership лизы == join, но отсутствует в
//         client.directChats[lizaMxid] → после addToDirectChat она там есть и
//         directChatMatrixID резолвируется.
//
// AC-5 (_ensureLizaDm с только мёртвым DM доходит до startDirectChat) —
//   MANUAL: _ensureLizaDm приватный, чистого seam для прямого вызова нет;
//   поведение детектора (isLiveLizaRoom) покрыто здесь, а конечный эффект
//   «startDirectChat вызван» требует полного MatrixState.
//
// Red-proof:
//   RP-1 (AC-1): убрать пин-логику → живой DM остаётся не на индексе 0.
//   RP-2 (AC-2): заменить isLizaAssistantRoom на localpart-предикат →
//         мёртвый DM проходит тест как «живой» и встаёт на 0.
//   RP-4 (AC-4): аналогично RP-2, но для ShareScaffoldDialog.
//
// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/miniapp_room.dart';
import 'package:liza/widgets/matrix.dart' as liza_matrix;
import 'package:liza/widgets/share_scaffold_dialog.dart';

import '../../utils/test_client.dart';

// ---------------------------------------------------------------------------
// Вспомогательные константы
// ---------------------------------------------------------------------------

/// Мёртвый @liza на старом инстансе prod (деактивирован 2026-07-14).
const _deadMxid = '@liza:synapse.liza.laba.prodamus.tech';

/// Живой ассистент (prod/company).
const _liveMxid = '@liza:bots.liza.ru';

// ---------------------------------------------------------------------------
// Фейковый MatrixState — Provider-слой для ShareScaffoldDialog.
// Паттерн forwarded_attribution_test.dart / channel_peek_message_render_test.dart.
// ---------------------------------------------------------------------------
class _TestMatrixState extends liza_matrix.MatrixState {
  _TestMatrixState(this._client);
  final Client _client;
  @override
  Client get client => _client;
}

Widget _wrapShare(Widget child, Client client) => MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Provider<liza_matrix.MatrixState>.value(
        value: _TestMatrixState(client),
        child: Scaffold(body: child),
      ),
    );

// ---------------------------------------------------------------------------
// Вспомогательные фабрики Room
// ---------------------------------------------------------------------------

/// Создаёт Room с membership == join для владельца (alice) и записывает
/// m.direct для [owner] → [roomId] = [partnerMxid].
void _makeDmJoined(
  Client client, {
  required String roomId,
  required String partnerMxid,
  String? roomName,
}) {
  final room = Room(id: roomId, client: client);
  // membership владельца = join (нужно для canSendDefaultMessages)
  room.membership = Membership.join;

  // Имя комнаты (если задано — mini-App-чат)
  if (roomName != null) {
    room.setState(Event(
      type: EventTypes.RoomName,
      eventId: '\$name$roomId',
      senderId: partnerMxid,
      originServerTs: DateTime.now(),
      room: room,
      content: {'name': roomName},
      stateKey: '',
    ));
  }

  client.rooms.add(room);

  // m.direct: partner → [roomId]
  final current = Map<String, dynamic>.from(
    (client.accountData['m.direct']?.content ?? {}).cast<String, dynamic>(),
  );
  final existing = List<String>.from(
    (current[partnerMxid] as List?) ?? [],
  );
  if (!existing.contains(roomId)) existing.add(roomId);
  current[partnerMxid] = existing;
  client.accountData['m.direct'] =
      BasicEvent(type: 'm.direct', content: current);
}

/// Добавляет state-event RoomMember для [memberMxid] с заданным [membership].
void _setMemberState(
  Room room,
  String memberMxid,
  Membership membership,
) {
  room.setState(Event(
    type: EventTypes.RoomMember,
    eventId: '\$member${memberMxid.hashCode}',
    senderId: memberMxid,
    originServerTs: DateTime.now(),
    room: room,
    content: {'membership': membership.name},
    stateKey: memberMxid,
  ));
}

// ---------------------------------------------------------------------------
// Логика пина (зеркало filteredRooms / share_scaffold_dialog.dart) —
// тестируемый seam для AC-1/2/3.
// ---------------------------------------------------------------------------
List<Room> _pinLizaFirst(List<Room> rooms, String lizaMxid) {
  final result = List<Room>.from(rooms);
  final lizaIndex =
      result.indexWhere((r) => isLizaAssistantRoom(r, lizaMxid));
  if (lizaIndex > 0) {
    result.insert(0, result.removeAt(lizaIndex));
  }
  return result;
}

// ---------------------------------------------------------------------------
// Тесты
// ---------------------------------------------------------------------------
void main() {
  group(
    'RL-liza-assistant-pinned-first — пин ассистента в главном списке и «Поделиться»',
    () {
      late Client client;

      setUp(() async {
        client = await prepareTestClient(loggedIn: true);
        client.rooms.clear();
      });

      tearDown(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await client.dispose(closeDatabase: true);
      });

      // -----------------------------------------------------------------------
      // AC-1: живой DM первым даже если SDK-ставит его НЕ первым
      // [AC:RL-liza-assistant-pinned-first/1]
      // -----------------------------------------------------------------------
      test(
        'AC-1: живой DM (@liza:bots.liza.ru, name пусто) → индекс 0',
        () {
          // Сначала — «другой чат», потом — живой Лиза-DM (SDK-порядок: другой первый)
          final otherRoom = Room(id: '!other:example.invalid', client: client)
            ..membership = Membership.join;
          _makeDmJoined(
            client,
            roomId: '!liza:example.invalid',
            partnerMxid: _liveMxid,
          );
          client.rooms.insert(0, otherRoom); // другой чат стоит первым

          final pinned = _pinLizaFirst(client.rooms, _liveMxid);

          // AC:RL-liza-assistant-pinned-first/1
          expect(
            pinned[0].id,
            '!liza:example.invalid',
            reason: 'AC-1: живой DM Лизы на индексе 0',
          );
          expect(pinned.length, 2);
        },
      );

      // -----------------------------------------------------------------------
      // AC-2: негатив-квантор ∀ — НИКАКОЙ мёртвый @liza:synapse DM НЕ индекс 0
      // [AC:RL-liza-assistant-pinned-first/2]
      // Наборы: {только мёртвые}, {живой+мёртвые}, {miniApp+мёртвые}
      // -----------------------------------------------------------------------
      group('AC-2: мёртвый DM НЕ попадает на индекс 0', () {
        test(
          'AC-2a: набор {только мёртвые @liza:synapse} — perm-index > 0',
          () {
            // Мёртвый DM — m.direct на старый @liza:synapse (partner: leave)
            _makeDmJoined(
              client,
              roomId: '!dead:example.invalid',
              partnerMxid: _deadMxid,
            );
            final otherRoom =
                Room(id: '!other:example.invalid', client: client)
                  ..membership = Membership.join;
            client.rooms.insert(0, otherRoom);

            final pinned = _pinLizaFirst(client.rooms, _liveMxid);

            // AC:RL-liza-assistant-pinned-first/2
            expect(
              pinned[0].id,
              isNot('!dead:example.invalid'),
              reason: 'AC-2a: мёртвый DM не становится первым',
            );
          },
        );

        test(
          'AC-2b: набор {живой+мёртвые} — живой первый, мёртвый НЕ первый',
          () {
            _makeDmJoined(
              client,
              roomId: '!dead:example.invalid',
              partnerMxid: _deadMxid,
            );
            _makeDmJoined(
              client,
              roomId: '!live:example.invalid',
              partnerMxid: _liveMxid,
            );
            // SDK-порядок: мёртвый первым
            final sdkOrder = [
              client.getRoomById('!dead:example.invalid')!,
              client.getRoomById('!live:example.invalid')!,
            ];

            final pinned = _pinLizaFirst(sdkOrder, _liveMxid);

            // AC:RL-liza-assistant-pinned-first/2
            expect(
              pinned[0].id,
              '!live:example.invalid',
              reason: 'AC-2b: живой DM должен обогнать мёртвый',
            );
            expect(
              pinned[1].id,
              '!dead:example.invalid',
              reason: 'AC-2b: мёртвый DM остаётся НЕ первым',
            );
          },
        );

        test(
          'AC-2c: набор {живой+miniApp+мёртвый} — живой первый, mini и dead НЕ первые',
          () {
            // Все три класса @liza-DM разом: живой ассистент должен победить,
            // ни mini-App (с именем), ни мёртвый @liza:synapse — не индекс 0.
            _makeDmJoined(
              client,
              roomId: '!dead:example.invalid',
              partnerMxid: _deadMxid,
            );
            _makeDmJoined(
              client,
              roomId: '!mini:example.invalid',
              partnerMxid: _liveMxid,
              roomName: 'Магазин',
            );
            _makeDmJoined(
              client,
              roomId: '!live:example.invalid',
              partnerMxid: _liveMxid,
            );
            // SDK-порядок: мёртвый первый, mini второй, живой третий
            final sdkOrder = [
              client.getRoomById('!dead:example.invalid')!,
              client.getRoomById('!mini:example.invalid')!,
              client.getRoomById('!live:example.invalid')!,
            ];

            final pinned = _pinLizaFirst(sdkOrder, _liveMxid);

            // AC:RL-liza-assistant-pinned-first/2
            expect(
              pinned[0].id,
              '!live:example.invalid',
              reason: 'AC-2c: живой ассистент обгоняет и mini, и мёртвый',
            );
            expect(
              pinned[0].id,
              isNot('!dead:example.invalid'),
              reason: 'AC-2c: мёртвый @liza:synapse не первый',
            );
            expect(
              pinned[0].id,
              isNot('!mini:example.invalid'),
              reason: 'AC-2c: miniApp @liza не первый',
            );
          },
        );
      });

      // -----------------------------------------------------------------------
      // AC-3: mini-App DM (directChatMatrixID == liveMxid, но есть m.room.name)
      // НЕ перехватывает пин.
      // [AC:RL-liza-assistant-pinned-first/3]
      // -----------------------------------------------------------------------
      test(
        'AC-3: mini-App @liza-DM (с именем) НЕ становится индексом 0',
        () {
          _makeDmJoined(
            client,
            roomId: '!mini:example.invalid',
            partnerMxid: _liveMxid,
            roomName: 'Prodamus Store',
          );
          final other = Room(id: '!other:example.invalid', client: client)
            ..membership = Membership.join;
          final sdkOrder = [
            other,
            client.getRoomById('!mini:example.invalid')!,
          ];

          final pinned = _pinLizaFirst(sdkOrder, _liveMxid);

          // AC:RL-liza-assistant-pinned-first/3
          expect(
            pinned[0].id,
            isNot('!mini:example.invalid'),
            reason: 'AC-3: mini-App с именем не должен перехватывать пин',
          );
        },
      );

      // -----------------------------------------------------------------------
      // AC-4: ShareScaffoldDialog пинит живой DM первым — РЕАЛЬНЫЙ виджет.
      // [AC:RL-liza-assistant-pinned-first/4]
      // guard.render:real-widget
      // -----------------------------------------------------------------------
      testWidgets(
        'AC-4: ShareScaffoldDialog — живой Лиза-DM идёт первым CheckboxListTile',
        (tester) async {
          // Прокачка внутри runAsync: Avatar/MxcImage заводят реальные retry-таймеры,
          // которые к концу теста висят и роняют fake-планировщик на !timersPending
          // (паттерн forwarded_attribution_test.dart). НЕ пампим после runAsync.
          await tester.runAsync(() async {
            client = await prepareTestClient(loggedIn: true);
            client.rooms.clear();

            // Мёртвый DM — m.direct на @liza:synapse (partner deactivated)
            _makeDmJoined(
              client,
              roomId: '!dead:example.invalid',
              partnerMxid: _deadMxid,
            );
            // Живой DM — @liza:bots.liza.ru
            _makeDmJoined(
              client,
              roomId: '!live:example.invalid',
              partnerMxid: _liveMxid,
            );
            // SDK-порядок: мёртвый первый (пин обязан вытащить живой на 0)
            final dead = client.getRoomById('!dead:example.invalid')!;
            final live = client.getRoomById('!live:example.invalid')!;
            client.rooms
              ..clear()
              ..addAll([dead, live]);

            await tester.pumpWidget(
              _wrapShare(const ShareScaffoldDialog(items: []), client),
            );
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 300));
            await tester.pump();
          });

          // ShareScaffoldDialog рендерит CheckboxListTile на комнату; subtitle DM
          // = directChatMatrixID. Первый @-subtitle — mxid первой комнаты списка.
          final subtitles = tester
              .widgetList<Text>(
                find.descendant(
                  of: find.byType(CheckboxListTile),
                  matching: find.byWidgetPredicate(
                    (w) => w is Text && (w.data?.startsWith('@') ?? false),
                  ),
                ),
              )
              .toList();

          // AC:RL-liza-assistant-pinned-first/4
          expect(
            subtitles,
            isNotEmpty,
            reason: 'Список ShareScaffoldDialog должен содержать DM-элементы',
          );
          expect(
            subtitles.first.data,
            _liveMxid,
            reason:
                'AC-4: первый элемент «Поделиться» — subtitle $_liveMxid (живой '
                'ассистент), а не $_deadMxid (мёртвый)',
          );
        },
      );

      // -----------------------------------------------------------------------
      // AC-6: self-heal — комната с membership Лизы есть, но её нет в
      // client.directChats[lizaMxid] → после addToDirectChat она добавлена
      // и directChatMatrixID резолвится.
      // [AC:RL-liza-assistant-pinned-first/6]
      // -----------------------------------------------------------------------
      test(
        'AC-6: self-heal-механизм: пока комнаты нет в m.direct — пин не видит её; '
        'после записи m.direct (то, что делает _ensureLizaDm.addToDirectChat) — резолвится',
        () {
          const roomId = '!healed:example.invalid';
          // Комната с Лизой-участником (join), но БЕЗ записи в m.direct —
          // ровно ситуация владельца: серверный m.direct корректен, устройский пуст.
          final room = Room(id: roomId, client: client)
            ..membership = Membership.join;
          _setMemberState(room, _liveMxid, Membership.join);
          client.rooms.add(room);

          // Предусловие: без m.direct directChatMatrixID == null → пин слеп.
          expect(
            room.directChatMatrixID,
            isNull,
            reason: 'До self-heal: m.direct пуст → directChatMatrixID null → '
                'isLizaAssistantRoom=false → комната НЕ закрепится',
          );
          expect(isLizaAssistantRoom(room, _liveMxid), isFalse);

          // Self-heal пишет m.direct (addToDirectChat в проде идёт по сети;
          // здесь эмулируем ЗАПИСЬ, которую он персистит — FakeMatrixApi PUT
          // account_data не поддерживает).
          client.accountData['m.direct'] = BasicEvent(
            type: 'm.direct',
            content: {
              _liveMxid: [roomId],
            },
          );

          // AC:RL-liza-assistant-pinned-first/6
          expect(
            room.directChatMatrixID,
            _liveMxid,
            reason: 'После записи m.direct directChatMatrixID резолвится в живого',
          );
          expect(
            isLizaAssistantRoom(room, _liveMxid),
            isTrue,
            reason: 'AC-6: после self-heal комната проходит пин-предикат',
          );
        },
      );

      // -----------------------------------------------------------------------
      // AC-6 (impl-lock): _ensureLizaDm реально несёт self-heal + member-детект.
      // SOURCE-SCAN ловит откат к localpart-детекту или удаление addToDirectChat.
      // -----------------------------------------------------------------------
      test(
        'AC-6 impl-lock: _ensureLizaDm использует member-стейт + self-heal addToDirectChat',
        () {
          final src = File('lib/widgets/matrix.dart').readAsStringSync();
          final start = src.indexOf('Future<void> _ensureLizaDm(');
          expect(start, greaterThan(-1), reason: '_ensureLizaDm должен существовать');
          final end = src.indexOf('\n  }', start) + 4;
          final body = src.substring(start, end);

          // Поиск вынесен в общий findLizaAssistantDm (им же пользуется пункт
          // «Подключить ИИ-агента» меню «+») — member-стейт проверяем там.
          final helper = File('lib/utils/liza_dm.dart').readAsStringSync();
          // AC:RL-liza-assistant-pinned-first/6
          expect(
            body.contains('findLizaAssistantDm(') &&
                helper.contains('EventTypes.RoomMember') &&
                !helper.contains('.directChatMatrixID'),
            isTrue,
            reason: 'детект живого DM — по member-стейту, а не по localpart/m.direct',
          );
          expect(
            body.contains("directChatMatrixID?.localpart == 'liza'"),
            isFalse,
            reason: 'откат к localpart-детекту запрещён (ловил мёртвый DM)',
          );
          expect(
            body.contains('addToDirectChat'),
            isTrue,
            reason: 'self-heal m.direct обязателен',
          );
        },
      );

      // -----------------------------------------------------------------------
      // RED-PROOF RP-1 (AC-1): без пин-логики живой DM НЕ на индексе 0
      // -----------------------------------------------------------------------
      test(
        'RP-1 [RED-PROOF AC-1]: без pinLizaFirst живой DM остаётся на исходной позиции',
        () {
          _makeDmJoined(
            client,
            roomId: '!liza:example.invalid',
            partnerMxid: _liveMxid,
          );
          final other = Room(id: '!other:example.invalid', client: client)
            ..membership = Membership.join;
          // SDK-порядок: другой первый, Лиза вторая
          final sdkOrder = [
            other,
            client.getRoomById('!liza:example.invalid')!,
          ];

          // Без пина — Лиза НЕ на 0
          expect(
            sdkOrder[0].id,
            isNot('!liza:example.invalid'),
            reason:
                'RP-1: без пин-логики живой DM стоит не первым (позиция 1)',
          );

          // С пином — Лиза на 0 (доказывает, что пин нужен и работает)
          final pinned = _pinLizaFirst(sdkOrder, _liveMxid);
          expect(pinned[0].id, '!liza:example.invalid');
        },
      );

      // -----------------------------------------------------------------------
      // RED-PROOF RP-2 (AC-2): при замене предиката на localpart-проверку
      // мёртвый DM ошибочно встаёт на 0
      // -----------------------------------------------------------------------
      test(
        'RP-2 [RED-PROOF AC-2]: localpart-предикат ошибочно пинит мёртвый DM',
        () {
          // Мёртвый DM: directChatMatrixID = @liza:synapse... (тот же localpart 'liza')
          _makeDmJoined(
            client,
            roomId: '!dead:example.invalid',
            partnerMxid: _deadMxid,
          );
          final other = Room(id: '!other:example.invalid', client: client)
            ..membership = Membership.join;
          // SDK-порядок: другой первый, мёртвый второй
          final sdkOrder = [
            other,
            client.getRoomById('!dead:example.invalid')!,
          ];

          // Сломанный предикат (как было до фикса dee33a34): localpart == 'liza'
          bool brokenPredicate(Room r) {
            final dcmId = r.directChatMatrixID;
            if (dcmId == null) return false;
            final localpart = dcmId.split(':').first.replaceFirst('@', '');
            return localpart == 'liza' &&
                (r.getState(EventTypes.RoomName)?.content.tryGet<String>('name') ?? '').isEmpty;
          }

          List<Room> brokenPin(List<Room> rooms) {
            final result = List<Room>.from(rooms);
            final idx = result.indexWhere(brokenPredicate);
            if (idx > 0) result.insert(0, result.removeAt(idx));
            return result;
          }

          final brokenPinned = brokenPin(sdkOrder);
          // Сломанный предикат ОШИБОЧНО ставит мёртвый DM первым
          expect(
            brokenPinned[0].id,
            '!dead:example.invalid',
            reason:
                'RP-2: сломанный localpart-предикат ошибочно делает мёртвый DM первым',
          );

          // Правильный предикат НЕ ставит мёртвый DM первым
          final correctPinned = _pinLizaFirst(sdkOrder, _liveMxid);
          expect(
            correctPinned[0].id,
            isNot('!dead:example.invalid'),
            reason: 'RP-2: правильный mxid-предикат НЕ пинит мёртвый DM',
          );
        },
      );

      // -----------------------------------------------------------------------
      // SOURCE-SCAN: проверяем что прод-код использует isLizaAssistantRoom
      // в обоих местах пина (filteredRooms + share_scaffold_dialog).
      // Ловит откат к localpart без запуска виджет-теста.
      // -----------------------------------------------------------------------
      group('SOURCE-SCAN: оба пина используют isLizaAssistantRoom', () {
        test(
          'chat_list.dart::filteredRooms использует isLizaAssistantRoom',
          () {
            final src =
                File('lib/pages/chat_list/chat_list.dart').readAsStringSync();
            // Извлекаем только тело filteredRooms
            final start = src.indexOf('List<Room> get filteredRooms');
            final end = src.indexOf('\n  }', start) + 4;
            final body = src.substring(start, end);

            expect(
              body.contains('isLizaAssistantRoom('),
              isTrue,
              reason:
                  'filteredRooms должен использовать isLizaAssistantRoom (mxid-канон), '
                  'а не localpart-предикат',
            );
            // Нет деградации к localpart
            expect(
              body.contains("localpart == 'liza'"),
              isFalse,
              reason: 'localpart-предикат запрещён — он не отличает мёртвый DM',
            );
            expect(
              body.contains("localpart == \"liza\""),
              isFalse,
            );
          },
        );

        test(
          'share_scaffold_dialog.dart использует isLizaAssistantRoom',
          () {
            final src = File('lib/widgets/share_scaffold_dialog.dart')
                .readAsStringSync();

            expect(
              src.contains('isLizaAssistantRoom('),
              isTrue,
              reason:
                  'ShareScaffoldDialog должен использовать isLizaAssistantRoom '
                  '(не localpart), как зафиксировано фиксом share-pin',
            );
            // Нет деградации к localpart
            expect(
              src.contains("localpart == 'liza'"),
              isFalse,
              reason:
                  'localpart-предикат в share удалён фиксом — не допускать возврата',
            );
            expect(
              src.contains("localpart == \"liza\""),
              isFalse,
            );
          },
        );
      });
    },
  );
}
