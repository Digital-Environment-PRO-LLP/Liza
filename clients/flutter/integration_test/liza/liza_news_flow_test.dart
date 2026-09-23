import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:liza/main.dart' as app;
import 'package:liza/pages/chat/chat_view.dart';

import 'e2e_actor.dart';
import 'e2e_config.dart';
import 'liza_flows.dart';

/// Device-flow бота «Liza News» на РЕАЛЬНОМ бинаре: редактор (testuser ∈
/// LIZA_NEWS_EDITORS) шлёт пост боту @liza-news → бот отвечает карточкой
/// «Отправлено N? [Подтвердить][Изменить]» (рендерится ТОЛЬКО если @liza-news
/// распознан как ai — через _fallbackAiMxids) → тап «Изменить» → бот просит
/// исправленный вариант.
///
/// Требует запущенного локального стека + бота liza_news.py (LIZA_NEWS_EDITORS
/// содержит @testuser:liza.local). Логин UI — testuser/testpass через
/// «Локальный сервер (пароль)» (ensureLizaHome).
const _newsBot = String.fromEnvironment(
  'LIZA_NEWS_BOT_MXID',
  defaultValue: '@liza-news:liza.local',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Liza News: пост редактора → карточка [Подтвердить][Изменить] → Изменить',
      (tester) async {
    // Редактор (testuser) через API создаёт DM с ботом и шлёт пост — бот отвечает
    // карточкой. UI открывает этот чат и проверяет рендер карточки на устройстве.
    final editor = await E2eActor.login(E2eConfig.homeserver, E2eConfig.userA);
    final roomId = await editor.createDirectChat(_newsBot);
    final beacon = 'Новость об обновлении ${DateTime.now().millisecondsSinceEpoch}';
    // даём боту принять инвайт до отправки поста
    await Future<void>.delayed(const Duration(seconds: 3));
    await editor.sendText(roomId, beacon);

    app.main();
    await tester.ensureLizaHome();

    // Открываем чат с ботом (плитка с текстом-маяком поста).
    final tile = find.textContaining(beacon);
    for (var i = 0; i < 40 && tile.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.waitUntil(tile, timeout: const Duration(seconds: 40));
    await tester.tap(tile.first);
    await tester.waitUntil(find.byType(ChatView), timeout: const Duration(seconds: 40));

    // Карточка подтверждения отрендерилась: обе кнопки видимы (⇒ @liza-news
    // распознан как ai через _fallbackAiMxids, иначе была бы деградация в текст).
    await tester.waitUntil(find.text('Подтвердить'), timeout: const Duration(seconds: 90));
    expect(find.text('Изменить'), findsWidgets);
    expect(find.textContaining('будет отправлено', findRichText: true), findsWidgets);

    // Тап «Изменить» → бот просит исправленный вариант (callback round-trip на устройстве).
    await tester.tap(find.text('Изменить').first);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.waitUntil(
      find.textContaining('исправленный вариант', findRichText: true),
      timeout: const Duration(seconds: 60),
    );
  });

  // Чат заводит САМ бот (как greet_all_editors на проде), редактор входит через
  // API — в его m.direct чат не помечен. Именно на этом пункт «Опрос» пропадал в
  // 3764; host-тест AC-14 строит Room руками, а живого клиента после свежего
  // /sync с ленивой загрузкой участников не видел ни один прогон на Android.
  // Бот здесь — только аккаунт, сам liza_news.py не нужен.
  // ledger:RL-liza-news-poll-editor-flow AC:RL-liza-news-poll-editor-flow/16
  testWidgets('Liza News: чат, созданный ботом → в «+» есть «Опрос», в личке с человеком нет',
      (tester) async {
    const botPass = String.fromEnvironment('LIZA_NEWS_BOT_PASS', defaultValue: 'testpass');
    final bot = await E2eActor.login(
      E2eConfig.homeserver,
      E2eUser(_newsBot.substring(1).split(':').first, botPass),
    );
    final editor = await E2eActor.login(E2eConfig.homeserver, E2eConfig.userA);
    final stamp = DateTime.now().millisecondsSinceEpoch;

    final newsDm = await bot.createDirectChat(editor.userId);
    await editor.joinRoom(newsDm);
    final newsBeacon = 'Приветствие редактору $stamp';
    await bot.sendText(newsDm, newsBeacon);

    final peer = await E2eActor.login(E2eConfig.homeserver, E2eConfig.userB);
    final peerDm = await peer.createDirectChat(editor.userId);
    await editor.joinRoom(peerDm);
    final peerBeacon = 'Обычная личка $stamp';
    await peer.sendText(peerDm, peerBeacon);

    app.main();
    await tester.ensureLizaHome();

    Future<void> openChat(String beacon) async {
      final tile = find.textContaining(beacon);
      await tester.waitUntil(tile, timeout: const Duration(seconds: 60));
      await tester.tap(tile.first);
      await tester.waitUntil(find.byType(ChatView), timeout: const Duration(seconds: 40));
    }

    Future<bool> pollItemInPlusMenu() async {
      await tester.tap(find.byIcon(Icons.add_circle_outline).first);
      await tester.pump(const Duration(milliseconds: 800));
      await tester.waitUntil(find.text('Отправить файл'), timeout: const Duration(seconds: 10));
      final present = find.text('Начать опрос').evaluate().isNotEmpty;
      await tester.tapAt(const Offset(5, 5));
      await tester.pump(const Duration(milliseconds: 800));
      return present;
    }

    await openChat(newsBeacon);
    expect(await pollItemInPlusMenu(), isTrue, reason: 'чат с @liza-news: пункт «Опрос» обязан быть');

    await tester.tap(find.byType(BackButton).first);
    await tester.pump(const Duration(milliseconds: 800));

    await openChat(peerBeacon);
    expect(await pollItemInPlusMenu(), isFalse, reason: 'личка с человеком: пункта «Опрос» быть не должно');
  });
}
