// Страж РЕГРЕССИИ ledger:RL-composer-emoji-picker-toggle.
//
// Фича: кнопка эмодзи в композере на ПК/веб (фидбек Нади — на десктопе/вебе нет
// системного эмодзи-пикера). Кнопка гейтится `!PlatformInfos.isMobile`, вызывает
// готовый `controller.emojiPickerAction`, открывает панель ChatEmojiPicker.
//
// Блокер-правка, которую фича разоблачила (KILLER-1 комиссии /brainstorm): новый
// вход к `typeEmoji` через кнопку открывает пикер на нефокусированном поле, где
// `TextEditingController.selection == TextSelection.collapsed(offset:-1)`. Наивный
// `replaceRange(-1,-1)` на непустом тексте бросал бы RangeError, а `baseOffset+len`
// ставил курсор ВНУТРЬ эмодзи. Логика вынесена в статику
// `ChatController.insertEmojiIntoText` — тестируем РЕАЛЬНУЮ статику, не реплику.
//
// Гейт `!PlatformInfos.isMobile` читает `dart:io Platform` (не
// `defaultTargetPlatform`), поэтому `debugDefaultTargetPlatformOverride` для него
// бесполезен — фиксируем инвариант выражения source-scan'ом (прецедент
// media_content_protection_test.dart). Реальное скрытие на iOS/Android — device-flow.

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:liza/pages/chat/chat.dart';

// Читается ВНУТРИ теста (не на уровне group), иначе expect бросит
// OutsideTestException. Отсутствие файла → readAsStringSync бросит и завалит тест.
String _compact(String path) =>
    File(path).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');

const _inputRow = 'lib/pages/chat/chat_input_row.dart';

void main() {
  group('AC-1 — кнопка эмодзи гейтится !PlatformInfos.isMobile (source-scan)', () {
    test('AC:RL-composer-emoji-picker-toggle/1 — гейт !isMobile присутствует', () {
      final source = _compact(_inputRow);
      expect(
        source.contains('if (!PlatformInfos.isMobile)'),
        isTrue,
        reason:
            'Кнопка эмодзи должна показываться ТОЛЬКО на ПК/веб — мобильный '
            'композер не меняем (там системная клавиатура даёт эмодзи).',
      );
    });

    test(
        'AC:RL-composer-emoji-picker-toggle/2 — кнопка вызывает готовый '
        'emojiPickerAction и тогглит иконку', () {
      final source = _compact(_inputRow);
      expect(
        source.contains('onPressed: controller.emojiPickerAction'),
        isTrue,
        reason: 'Переиспользуем существующий тумблер, не плодим новый метод.',
      );
      expect(
        source.contains('Icons.emoji_emotions_outlined') &&
            source.contains('Icons.keyboard_outlined'),
        isTrue,
        reason:
            'Иконка-тумблер emoji↔клавиатура по controller.showEmojiPicker.',
      );
    });
  });

  group('AC-3 — insertEmojiIntoText: вставка в позицию курсора + нормализация', () {
    const smile = '🙂';

    test('AC:RL-composer-emoji-picker-toggle/3a — пустой текст', () {
      final v = ChatController.insertEmojiIntoText(
        '',
        const TextSelection.collapsed(offset: -1),
        smile,
      );
      expect(v.text, smile);
      expect(v.selection.baseOffset, smile.length); // курсор ЗА эмодзи, не -1+len
    });

    test(
      'AC:RL-composer-emoji-picker-toggle/3b — непустой текст + невалидная каретка '
      '(offset -1) НЕ бросает, вставка в конец [red-proof KILLER-1]',
      () {
        // На коде до фикса это был бы text.replaceRange(-1,-1,…) → RangeError.
        final v = ChatController.insertEmojiIntoText(
          'привет',
          const TextSelection.collapsed(offset: -1),
          smile,
        );
        expect(v.text, 'привет$smile');
        expect(v.selection.baseOffset, 'привет'.length + smile.length);
      },
    );

    test('AC:RL-composer-emoji-picker-toggle/3c — каретка в середине', () {
      final v = ChatController.insertEmojiIntoText(
        'абвг',
        const TextSelection.collapsed(offset: 2),
        smile,
      );
      expect(v.text, 'аб$smile' 'вг');
      expect(v.selection.baseOffset, 2 + smile.length);
    });

    test('AC:RL-composer-emoji-picker-toggle/3d — выделение заменяется эмодзи', () {
      final v = ChatController.insertEmojiIntoText(
        'абвг',
        const TextSelection(baseOffset: 1, extentOffset: 3),
        smile,
      );
      expect(v.text, 'а$smile' 'г');
      expect(v.selection.baseOffset, 1 + smile.length);
    });

    test(
      'AC:RL-composer-emoji-picker-toggle/3e — UTF-8 combined emoji длиной >1: '
      'курсор ЗА символом',
      () {
        const family = '👨‍👩‍👧'; // combined, length > 1
        expect(family.length > 1, isTrue);
        final v = ChatController.insertEmojiIntoText(
          'x',
          const TextSelection.collapsed(offset: 1),
          family,
        );
        expect(v.text, 'x$family');
        expect(v.selection.baseOffset, 1 + family.length);
      },
    );
  });

  group('AC-4 — эмодзи-кнопка вне selectMode-ветки Row', () {
    test(
        'AC:RL-composer-emoji-picker-toggle/4 — кнопка эмодзи статична (не в '
        'схлопывающемся AnimatedContainer «+»)', () {
      final source = _compact(_inputRow);
      // Регресс-защита: эмодзи-кнопка не должна прятаться при наборе текста
      // (эмодзи добавляют В сообщение). Она — отдельная ячейка ПЕРЕД «+».
      final emojiIdx = source.indexOf('Icons.emoji_emotions_outlined');
      final plusIdx = source.indexOf('Icons.add_circle_outline');
      expect(emojiIdx, greaterThanOrEqualTo(0));
      expect(plusIdx, greaterThanOrEqualTo(0));
      expect(
        emojiIdx < plusIdx,
        isTrue,
        reason: 'Кнопка эмодзи размещается перед кнопкой «+».',
      );
    });
  });
}
