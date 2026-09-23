// ledger:RL-forwarded-attribution
// Unit-тест общей трубы пересылки buildForwardedContent (LABA-1991): чистка
// m.relates_to (AC-5), маркер com.liza.forwarded, деградация имени без localpart
// (AC-3), неизменность оригинала. Плюс структурный гейт: ВСЕ пути форварда
// (контекстное меню, мультивыбор, просмотр фото) идут через эту трубу — защита от
// регресса «плашка только из одного места» (найден ревью коммита 477b31a1).

// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/forwarded_content_builder.dart';

import '../../utils/test_client.dart';

void main() {
  late Client client;

  setUp(() async {
    client = await prepareTestClient(loggedIn: true);
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await client.dispose(closeDatabase: true);
  });

  Event ev(Map<String, Object?> content) => Event(
        type: EventTypes.Message,
        eventId: '\$fwd:example.invalid',
        senderId: '@ghost:example.invalid',
        originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
        room: Room(id: '!r:example.invalid', client: client),
        content: content,
      );

  // AC:RL-forwarded-attribution/5
  test('AC-5 снимает m.relates_to и НЕ мутирует оригинал', () async {
    final original = <String, Object?>{
      'msgtype': 'm.text',
      'body': 'привет',
      'm.relates_to': {
        'm.in_reply_to': {'event_id': '\$orig:example.invalid'},
      },
    };
    final event = ev(original);
    final out = await buildForwardedContent(event);

    expect(
      out.containsKey('m.relates_to'),
      isFalse,
      reason: 'reply-связь не должна улетать в чужую комнату',
    );
    expect(out['com.liza.forwarded'], isA<Map<String, Object?>>());
    expect(
      event.content.containsKey('m.relates_to'),
      isTrue,
      reason: 'копия независима — оригинальное событие таймлайна не тронуто',
    );
  });

  // AC:RL-forwarded-attribution/3 — деградацию до пустого маркера (без localpart)
  // детерминированно держат widget-тесты (forwarded_attribution AC-3 / forwarded_content).
  // Здесь фиксируем ФОРМУ маркера: from_name — только непустая строка, иначе ключа нет.
  test('from_name в маркере — только непустая строка (иначе ключ отсутствует)',
      () async {
    final out = await buildForwardedContent(
      ev({'msgtype': 'm.text', 'body': 'привет'}),
    );
    final marker = out['com.liza.forwarded'] as Map<String, Object?>;
    final name = marker['from_name'];
    expect(
      name == null || (name is String && name.isNotEmpty),
      isTrue,
      reason: 'НИКОГДА не кладём пустую строку/localpart-заглушку в from_name',
    );
  });

  test('исключение fetchSenderUser не ломает пересылку → маркер без имени', () async {
    // @ghost не в комнате: fetchSenderUser может бросить/вернуть null — труба
    // обязана деградировать в маркер без имени, а не пробросить исключение.
    final out = await buildForwardedContent(
      ev({'msgtype': 'm.image', 'body': 'pic.jpg', 'url': 'mxc://x/y'}),
    );
    expect(out.containsKey('com.liza.forwarded'), isTrue);
  });

  // AC:RL-forwarded-attribution/7
  // Структурный гейт: все ТРИ точки форварда используют общую трубу; ни одна не
  // шлёт сырой content (иначе плашка/чистка relates_to теряются на этом пути).
  test('все пути форварда идут через buildForwardedContent', () {
    final chat = File('lib/pages/chat/chat.dart').readAsStringSync();
    final viewer =
        File('lib/pages/image_viewer/image_viewer.dart').readAsStringSync();

    expect(
      'buildForwardedContent'.allMatches(chat).length,
      greaterThanOrEqualTo(2),
      reason: 'forwardEvent (меню) + forwardEventsAction (мультивыбор)',
    );
    // Просмотрщик ходит не напрямую, а через gallery-aware обёртку
    // `buildForwardedGalleryContents` (она снимает `com.liza.gallery` у
    // одиночного форварда члена альбома и внутри зовёт `buildForwardedContent`
    // на каждый кадр — см. gallery.dart). Страж отстал от этого рефакторинга и
    // был красным на baseline; инвариант «форвард идёт через трубу пометки
    // Переслано» при этом держится.
    expect(
      viewer.contains('buildForwardedContent') ||
          viewer.contains('buildForwardedGalleryContents'),
      isTrue,
      reason: 'ImageViewer.forwardAction (пересылка фото)',
    );
    expect(
      chat.contains('ContentShareItem(event.content)'),
      isFalse,
      reason: 'сырой content в форварде мультивыбора — регресс LABA-1991',
    );
    expect(
      viewer.contains('ContentShareItem(currentEvent.content)'),
      isFalse,
      reason: 'сырой content в форварде фото — регресс LABA-1991',
    );
  });
}
