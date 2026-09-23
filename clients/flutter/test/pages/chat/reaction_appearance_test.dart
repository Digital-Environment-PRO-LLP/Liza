import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/pages/chat/events/message_reactions.dart';

// Спек 2026-07-30 §1.7. Два дефекта со скриншотов:
// 1) у автора канала реакции уезжали вправо (пост канала не «своё
//    сообщение», выравнивание всегда слева);
// 2) непоставленная реакция была неотличима от текста поста — рамка
//    совпадала по цвету с подложкой.
void main() {
  group('reactionAlignment', () {
    test('в канале реакции всегда слева, даже у автора поста', () {
      expect(
        reactionAlignment(ownMessage: true, isChannel: true),
        WrapAlignment.start,
      );
    });

    test('в обычном чате своё сообщение — реакции справа', () {
      expect(
        reactionAlignment(ownMessage: true, isChannel: false),
        WrapAlignment.end,
      );
    });

    test('в обычном чате чужое сообщение — реакции слева', () {
      expect(
        reactionAlignment(ownMessage: false, isChannel: false),
        WrapAlignment.start,
      );
    });
  });
}
