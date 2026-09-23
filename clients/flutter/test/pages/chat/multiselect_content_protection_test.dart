import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ledger:RL-group-content-protection

// Task 10, Fix round 1 (2026-07-30): контекстное меню одного сообщения
// гейтит копирование/пересылку/сохранение через `room.isContentProtected`
// (message_context_menu.dart), но панель множественного выбора реализует
// те же действия ПАРАЛЛЕЛЬНО (chat_view.dart / chat_input_row.dart) и не
// проверяла тот же флаг — подписчик защищённого канала обходил запрет в
// два тапа: «Выбрать» → «Копировать»/«Переслать»/«Скачать».
//
// Структурный тест по исходнику: сборка виджета с полноценной Room/Client
// (нужны для isContentProtected) в unit-тесте требует подъёма клиента —
// как в channel_uniform_bubbles_test.dart / channel_attribution_test.dart.
// Проверяем, что гейт `!... isContentProtected` стоит РЯДОМ (в том же
// условном блоке) с каждой из трёх точек выноса контента.
void main() {
  String compact(String path) {
    final file = File(path);
    expect(
      file.existsSync(),
      isTrue,
      reason: 'Тест должен запускаться из clients/flutter/',
    );
    return file.readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
  }

  group('гейт isContentProtected на панели множественного выбора', () {
    test('«Скачать» в chat_view.dart гейтится', () {
      final source = compact('lib/pages/chat/chat_view.dart');
      expect(
        source.contains(
          'if (controller.canSaveSelectedEvents && '
          '!controller.room.isContentProtected)',
        ),
        isTrue,
        reason:
            'кнопка "Скачать" в панели выбора должна прятаться при '
            'isContentProtected — иначе подписчик защищённого канала '
            'скачивает вложения в обход запрета одиночного меню',
      );
    });

    test('«Копировать» в chat_view.dart гейтится', () {
      final source = compact('lib/pages/chat/chat_view.dart');
      expect(
        // Fix round 3: к гейту защиты добавился canCopySelectedEvents —
        // условие стало строго сильнее (см. Important 4 в задаче), ассерт
        // не ослаблен, а дополнен второй половиной условия.
        source.contains(
          'if (controller.canCopySelectedEvents && '
          '!controller.room.isContentProtected) IconButton( '
          'icon: const Icon(Icons.copy_outlined),',
        ),
        isTrue,
        reason:
            'кнопка "Копировать" в панели выбора должна прятаться при '
            'isContentProtected — иначе copyEventsAction копирует текст '
            'защищённого поста в обход запрета одиночного меню',
      );
    });

    test('«Переслать» в chat_input_row.dart гейтится', () {
      final source = compact('lib/pages/chat/chat_input_row.dart');
      expect(
        source.contains(
          'else if (!controller.room.isContentProtected) SizedBox( '
          'height: height, child: TextButton( style: selectedTextButtonStyle, '
          'onPressed: controller.forwardEventsAction,',
        ),
        isTrue,
        reason:
            'кнопка "Переслать" в панели выбора должна прятаться при '
            'isContentProtected — иначе forwardEventsAction пересылает '
            'защищённый пост в обход запрета одиночного меню',
      );
    });

    test('удаление в selectMode НЕ гейтится (не выносит контент наружу)', () {
      final source = compact('lib/pages/chat/chat_view.dart');
      // Страховка от чрезмерного гейта: canRedactSelectedEvents не должен
      // обрасти условием isContentProtected — иначе защищённый канал
      // потеряет возможность удалять свои же сообщения не-админом.
      expect(
        source.contains(
          'if (controller.canRedactSelectedEvents && '
          '!controller.room.isContentProtected)',
        ),
        isFalse,
        reason:
            'удаление сообщений не выносит контент из чата, гейтить его '
            'isContentProtected не нужно — это увеличило бы объём правки '
            'без пользы для запрета копирования',
      );
    });
  });
}
