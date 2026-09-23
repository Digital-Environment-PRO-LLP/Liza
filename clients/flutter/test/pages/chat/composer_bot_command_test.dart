// Страж РЕГРЕССИИ ledger:RL-composer-bot-command-passthrough.
//
// Набранная в композере `/`-команда бота-ассистента (BotFather/Лиза) должна
// уходить боту КАК ТЕКСТ (parseCommands:false), а не резаться клиентским
// диалогом «Недопустимая команда». Проверяем РЕАЛЬНЫЕ статики ChatController,
// которые использует send() (не реплику): паттерн извлечения имени и allowlist.
//
// Первопричина бага: `/miniapp-constraction` не работала на проде — (1) её не
// было в allowlist, (2) старый паттерн `^\/(\w+)` не захватывал дефис → имя
// обрезалось до `miniapp`. Сервер был готов, но команда не доходила.

import 'package:flutter_test/flutter_test.dart';
import 'package:liza/pages/chat/chat.dart';

void main() {
  group('ChatController.composerCommandPattern — извлечение имени команды', () {
    String? name(String input) =>
        ChatController.composerCommandPattern.firstMatch(input)?.group(1);

    test('AC:RL-composer-bot-command-passthrough/1 — дефис захватывается целиком',
        () {
      // Регрессия исходного бага: `\w+` обрезал до "miniapp".
      expect(name('/miniapp-constraction'), 'miniapp-constraction');
      expect(name('/miniapp-construction'), 'miniapp-construction');
    });

    test('обычные команды без дефиса — без изменений', () {
      expect(name('/newapp'), 'newapp');
      expect(name('/myapps'), 'myapps');
      expect(name('/start hello'), 'start'); // аргументы отсекаются
    });

    test('не команда → null', () {
      expect(name('привет'), isNull);
      expect(name('текст /newapp внутри'), isNull);
    });
  });

  group('ChatController.isBotComposerCommand — allowlist bot-команд', () {
    test(
        'AC:RL-composer-bot-command-passthrough/2 — конструктор в allowlist '
        '(команда доходит боту, а не режется)', () {
      expect(ChatController.isBotComposerCommand('miniapp-constraction'), isTrue);
      expect(ChatController.isBotComposerCommand('miniapp-construction'), isTrue);
    });

    test('существующие bot-команды остаются (регрессия)', () {
      for (final c in ['newapp', 'createminiapp', 'myapps', 'newbot', 'mybots',
        'deletebot', 'cancel', 'start', 'menu']) {
        expect(ChatController.isBotComposerCommand(c), isTrue, reason: c);
      }
    });

    test('регистронезависимо', () {
      expect(ChatController.isBotComposerCommand('MiniApp-Constraction'), isTrue);
      expect(ChatController.isBotComposerCommand('NEWAPP'), isTrue);
    });

    test('чужая/неизвестная команда → false (диалог «недопустимая» остаётся)',
        () {
      expect(ChatController.isBotComposerCommand('miniapp'), isFalse); // голый префикс
      expect(ChatController.isBotComposerCommand('shrug'), isFalse);
      expect(ChatController.isBotComposerCommand('ban'), isFalse); // Matrix-команда SDK
    });
  });

  test(
      'AC:RL-composer-bot-command-passthrough/3 — сквозной путь: '
      '/miniapp-constraction извлекается И классифицируется как bot-команда', () {
    final n = ChatController.composerCommandPattern
        .firstMatch('/miniapp-constraction')
        ?.group(1);
    expect(n, isNotNull);
    expect(ChatController.isBotComposerCommand(n!), isTrue);
  });
}
