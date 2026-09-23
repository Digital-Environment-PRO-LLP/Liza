// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/pages/chat_details/chat_details.dart';
import 'package:liza/utils/channel_discussion.dart';

import 'test_client.dart';

/// ledger:RL-channel-discussion-federated-join
///
/// Баг: тап «Прокомментировать» под постом канала давал snackbar «Не удалось
/// открыть обсуждение», хотя join на сервере проходил успешно. Причина —
/// федеративный join в чат обсуждения на ЧУЖОМ хоумсервере не укладывался в
/// 5-секундный бюджет `waitForRoomInSync`, а `ensureDiscussionMembership`
/// схлопывала все четыре исхода в один `null`.
/// Ключ маршрута в FakeMatrixApi: он матчит путь ВМЕСТЕ с query, а
/// `ensureDiscussionMembership` всегда передаёт `via` (`discussionViaServers`).
/// Все комнаты в этом файле — на `example.invalid`, поэтому via ровно один.
String _joinPath(String roomId) =>
    '/client/v3/join/${Uri.encodeComponent(roomId)}?via=example.invalid';

void main() {
  group('discussionJoinSyncTimeout — бюджет ожидания sync', () {
    // AC:RL-channel-discussion-federated-join/1
    test('чужой хоумсервер: бюджет заметно больше локального', () {
      final federated = discussionJoinSyncTimeout(
        discussionRoomId: '!mfdTYXVAQpplDCNTJA:nadezhda.liza.ru',
        userId: '@daniel.furman:synapse.liza.laba.prodamus.tech',
      );
      final local = discussionJoinSyncTimeout(
        discussionRoomId: '!mfdTYXVAQpplDCNTJA:nadezhda.liza.ru',
        userId: '@nadezhda.rozental:nadezhda.liza.ru',
      );
      expect(
        federated,
        greaterThan(local),
        reason: 'ровно этот случай (подписчик с чужого HS) и давал ложный '
            'отказ на проде',
      );
      expect(
        federated.inSeconds,
        greaterThanOrEqualTo(20),
        reason: 'send_join к чужому HS упирается в федеративный таймаут '
            'Synapse (~20 с) — меньший бюджет обрывает ожидание раньше, чем '
            'сервер вообще успевает ответить',
      );
    });

    // AC:RL-channel-discussion-federated-join/2
    test('своя комната остаётся на прежних 5 с', () {
      expect(
        discussionJoinSyncTimeout(
          discussionRoomId: '!disc:example.invalid',
          userId: '@alice:example.invalid',
        ),
        const Duration(seconds: 5),
        reason: 'локальный join ждёт только свой sync-цикл — раздувать бюджет '
            'значит удлинять спиннер при реальном сбое',
      );
    });

    test('порт в имени сервера не ломает сравнение доменов', () {
      expect(
        discussionJoinSyncTimeout(
          discussionRoomId: '!disc:example.invalid:8448',
          userId: '@alice:example.invalid:8448',
        ),
        const Duration(seconds: 5),
      );
    });

    test('неизвестный userID трактуем как локальный (не раздуваем спиннер)', () {
      expect(
        discussionJoinSyncTimeout(
          discussionRoomId: '!disc:example.invalid',
          userId: null,
        ),
        const Duration(seconds: 5),
      );
    });

    test('бюджет НЕ зашит глобально в waitForRoomInSync', () {
      // Дефолт waitForRoomInSync обязан остаться прежним: его зовут ещё из
      // routes.dart, chat_list, new_group, public_room_dialog и stories —
      // «полечить» федеративный join глобальным раздуванием таймаута значило
      // бы удлинить спиннер во всех этих сценариях.
      final source = File('lib/utils/wait_for_room_in_sync.dart')
          .readAsStringSync()
          .replaceAll(RegExp(r'\s+'), ' ');
      expect(
        source.contains('Duration timeout = const Duration(seconds: 5)'),
        isTrue,
        reason: 'дефолтный бюджет waitForRoomInSync менять нельзя — '
            'федеративный случай передаёт свой параметром',
      );
    });
  });

  group('ensureDiscussionMembershipResult — различимые исходы', () {
    late Client client;
    late Room channel;

    setUp(() async {
      client = await prepareTestClient(loggedIn: true);
      channel = Room(id: '!chan:example.invalid', client: client);
    });

    tearDown(() async {
      await client.dispose(closeDatabase: true);
    });

    void bindDiscussion(String? roomId) {
      channel.setState(
        Event(
          eventId: '\$discussion',
          senderId: '@creator:example.invalid',
          originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
          type: channelDiscussionState,
          content: roomId == null ? {} : {'room_id': roomId},
          room: channel,
          stateKey: '',
        ),
      );
    }

    test('комментарии выключены — noDiscussion, а не «не удалось»', () async {
      bindDiscussion(null);
      final result = await channel.ensureDiscussionMembershipResult();
      expect(result.outcome, DiscussionJoinOutcome.noDiscussion);
      expect(result.isJoined, isFalse);
    });

    test('уже член — joined без сетевого join', () async {
      const discussionId = '!disc:example.invalid';
      bindDiscussion(discussionId);
      final discussion = Room(
        id: discussionId,
        client: client,
        membership: Membership.join,
      );
      client.rooms.add(discussion);
      final result = await channel.ensureDiscussionMembershipResult();
      expect(result.outcome, DiscussionJoinOutcome.joined);
      expect(result.isJoined, isTrue);
      expect(result.room?.id, discussionId);
    });

    // AC:RL-channel-discussion-federated-join/3
    test('сервер отверг join — rejected + errcode в результате', () async {
      const discussionId = '!forbidden:example.invalid';
      bindDiscussion(discussionId);
      final fakeApi = FakeMatrixApi.currentApi!;
      final path = _joinPath(discussionId);
      fakeApi.api['POST']![path] = (var req) => {
            'errcode': 'M_FORBIDDEN',
            'error': 'You are not invited to this room.',
          };
      addTearDown(() => fakeApi.api['POST']!.remove(path));

      final result = await channel.ensureDiscussionMembershipResult();
      expect(
        result.outcome,
        DiscussionJoinOutcome.rejected,
        reason: 'отказ сервера повтором не лечится — сообщение обязано '
            'отличаться от таймаута',
      );
      expect(
        result.errcode,
        'M_FORBIDDEN',
        reason: 'errcode обязан доезжать до вызывающего/лога — без него баг '
            'с прода не диагностируется',
      );
      expect(result.isJoined, isFalse);
    });

    // AC:RL-channel-discussion-federated-join/4
    test(
      'join принят, комната не приехала в sync — timedOut, НЕ rejected',
      () async {
        // Это и есть прод-сценарий: join прошёл, но комната не успела
        // приехать. Раньше пользователь видел «Не удалось открыть
        // обсуждение», то есть враньё про отсутствие доступа.
        const discussionId = '!slow:example.invalid';
        bindDiscussion(discussionId);
        final fakeApi = FakeMatrixApi.currentApi!;
        final path = _joinPath(discussionId);
        fakeApi.api['POST']![path] = (var req) => {'room_id': discussionId};
        addTearDown(() => fakeApi.api['POST']!.remove(path));

        final sw = Stopwatch()..start();
        final result = await channel.ensureDiscussionMembershipResult();
        sw.stop();
        expect(
          result.outcome,
          DiscussionJoinOutcome.timedOut,
          reason: 'сервер не отказывал — комната просто не приехала в sync',
        );
        expect(result.errcode, isNull);
        expect(result.isJoined, isFalse);
        // Клиент тестового стенда живёт на fakeServer.notExisting, а комната —
        // на example.invalid, то есть это ровно ФЕДЕРАТИВНЫЙ случай. Значит
        // сквозной прогон обязан израсходовать увеличенный бюджет: на прежних
        // 5 с он оборвался бы втрое раньше — и именно так на проде возникал
        // ложный «Не удалось открыть обсуждение».
        expect(
          sw.elapsed,
          greaterThanOrEqualTo(const Duration(seconds: 19)),
          reason: 'федеративный join обязан ждать увеличенный бюджет, а не 5 с',
        );
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );

    test('старое API ensureDiscussionMembership отдаёт ту же комнату', () async {
      const discussionId = '!disc:example.invalid';
      bindDiscussion(discussionId);
      client.rooms.add(
        Room(id: discussionId, client: client, membership: Membership.join),
      );
      final room = await channel.ensureDiscussionMembership();
      expect(room?.id, discussionId);
    });
  });

  group('идемпотентность создания чата обсуждения', () {
    // Причина дубля на проде (!imFpwmDxzbZyFMaFtN: две комнаты обсуждения,
    // созданные РАЗНЫМИ версиями клиента — разные шаблоны имени): guard
    // `discussionRoomId != null` и findDetachedDiscussion читают ЛОКАЛЬНЫЙ
    // снимок sync, который отстаёт и бывает неполон.

    // AC:RL-channel-discussion-federated-join/5
    test('серверная привязка распознаётся и отменяет создание', () {
      expect(
        boundDiscussionFromState({'room_id': '!mfdTYXVAQpplDCNTJA:nadezhda'}),
        '!mfdTYXVAQpplDCNTJA:nadezhda',
      );
    });

    test('пустой content — привязки нет, создаём', () {
      expect(boundDiscussionFromState(const {}), isNull);
      expect(boundDiscussionFromState(null), isNull);
    });

    test('пустая строка привязкой не считается', () {
      expect(boundDiscussionFromState({'room_id': ''}), isNull);
    });

    test('маркер удаления канала привязкой не считается', () {
      // Тот же контракт, что у Room.discussionRoomId: иначе включение
      // комментариев на канале с сорвавшимся удалением молча не сработало бы.
      expect(
        boundDiscussionFromState({
          'room_id': '!disc:h',
          channelDeletedKey: true,
        }),
        isNull,
      );
    });

    test('room_id не-строка не роняет разбор', () {
      expect(boundDiscussionFromState({'room_id': 42}), isNull);
    });

    // AC:RL-channel-discussion-federated-join/6
    test('перед createRoom стоит перечитывание привязки С СЕРВЕРА', () {
      // Полноценный интеграционный тест недостижим без живого Matrix-клиента
      // (createRoom + два параллельных нажатия). Структурный страж проверяет
      // ПОРЯДОК: серверная сверка обязана стоять РАНЬШЕ createRoom, иначе
      // дубль возвращается.
      final source = File('lib/pages/chat_details/chat_details.dart')
          .readAsStringSync();
      // Якорь — ОБЪЯВЛЕНИЕ метода, а не первое вхождение имени: вызов
      // `await _enableChannelCommentsInner(...)` стоит выше, и окно от него
      // захватило бы определение `_serverDiscussionRoomId`, из-за чего тест
      // зеленел даже с вырезанной сверкой (проверено мутацией).
      final start =
          source.indexOf('Future<void> _enableChannelCommentsInner(');
      expect(start, greaterThan(-1),
          reason: 'создание чата обсуждения переименовано/перенесено?');
      final recheck = source.indexOf('await _serverDiscussionRoomId(', start);
      final create = source.indexOf('client.createRoom(', start);
      expect(recheck, greaterThan(-1),
          reason: 'локальный снимок sync отстаёт — перед созданием комнаты '
              'привязку обязательно перечитать с сервера');
      expect(create, greaterThan(-1));
      expect(
        recheck,
        lessThan(create),
        reason: 'сверка ПОСЛЕ createRoom бесполезна — дубль уже создан',
      );
    });

    // AC:RL-channel-discussion-federated-join/7
    test('повторный тап отсекается флагом до первого await', () {
      // showFutureLoadingDialog от двойного тапа не спасает: он поднимается
      // уже ПОСЛЕ await requestParticipants(), а два быстрых тапа успевают
      // пройти guard оба.
      final source = File('lib/pages/chat_details/chat_details.dart')
          .readAsStringSync()
          .replaceAll(RegExp(r'\s+'), ' ');
      final start = source.indexOf('void enableChannelComments() async {');
      expect(start, greaterThan(-1));
      final body = source.substring(start, start + 400);
      expect(
        body.contains('if (_enablingComments) return;'),
        isTrue,
        reason: 'без in-flight флага два быстрых тапа создают два чата',
      );
      expect(
        source.contains('_enablingComments = false;'),
        isTrue,
        reason: 'флаг обязан сниматься в finally, иначе кнопка залипнет '
            'навсегда после первой же ошибки',
      );
      expect(
        source.contains('} finally { _enablingComments = false; }'),
        isTrue,
        reason: 'снятие флага только в finally',
      );
    });
  });

  group('различимые сообщения пользователю', () {
    // AC:RL-channel-discussion-federated-join/8
    test('оба ключа заведены и в en, и в ru', () {
      // Гейта на полноту intl_ru.arb нет — без ключа Flutter молча подставит
      // английский.
      for (final path in ['lib/l10n/intl_en.arb', 'lib/l10n/intl_ru.arb']) {
        final source = File(path).readAsStringSync();
        expect(source.contains('"channelDiscussionOpenFailed"'), isTrue,
            reason: 'нет ключа в $path');
        expect(source.contains('"channelDiscussionOpenSlow"'), isTrue,
            reason: 'нет ключа в $path');
      }
    });

    test('таймаут и отказ показывают РАЗНЫЕ строки на всех трёх сайтах', () {
      for (final path in [
        'lib/pages/chat/events/channel_post_comments.dart',
        'lib/pages/channel_thread/channel_thread_page.dart',
        'lib/pages/chat_details/chat_details.dart',
      ]) {
        final source =
            File(path).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
        expect(
          source.contains('DiscussionJoinOutcome.timedOut'),
          isTrue,
          reason: '$path обязан отличать таймаут sync от отказа сервера — '
              'иначе пользователю снова врут про «нет доступа»',
        );
        expect(
          source.contains('channelDiscussionOpenSlow'),
          isTrue,
          reason: '$path показывает предложение повторить при таймауте',
        );
      }
    });

    test('MatrixException больше не глотается без errcode', () {
      final source = File('lib/utils/channel_discussion.dart')
          .readAsStringSync()
          .replaceAll(RegExp(r'\s+'), ' ');
      expect(
        source.contains('on MatrixException catch'),
        isTrue,
        reason: 'отказ сервера обязан ловиться отдельно от прочих ошибок',
      );
      expect(
        source.contains(r'${e.errcode}'),
        isTrue,
        reason: 'errcode обязан попадать в лог — именно его отсутствие и '
            'сделало баг недиагностируемым',
      );
    });
  });
}
