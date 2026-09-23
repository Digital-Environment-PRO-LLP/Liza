import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ledger:RL-group-content-protection
//
// LABA-2541. Прокурорский свип по точкам выноса контента, доступным участнику
// с PL < 50 при включённом «Запретить сохранение контента». Все три дыры ниже
// были ЖИВЫМИ на момент правки и по отдельности делали жалобу «сообщения можно
// копировать / сохранять» буквально верной.
//
// Структурный тест по исходнику — тот же паттерн, что в
// multiselect_/media_/viewer_search_content_protection_test.dart: поднимать
// полный ChatController с Room/Client в unit-окружении неподъёмно, поэтому
// проверяем точный текст гейта рядом с каждой точкой.
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

  group('«Информация о сообщении» не отдаёт тело мимо гейтов', () {
    test('пункт в меню режима выделения закрыт ролью разработчика', () {
      // Диалог показывает СЫРОЙ JSON события выделяемым текстом
      // (event_info_dialog.dart → SelectableText(prettyJson)) — это
      // полноценный путь копирования тела. В контекстном меню пункт уже был под
      // ролью разработчика, а в меню выделения оставался открыт всем: участник
      // защищённого чата копировал текст в три тапа.
      final source = compact('lib/pages/chat/chat_view.dart');
      // AC:RL-group-content-protection/13
      expect(
        source.contains(
          'if (Matrix.of(context).isCurrentUserDeveloper) '
          'PopupMenuItem( value: _EventContextAction.info,',
        ),
        isTrue,
        reason:
            'пункт «Информация о сообщении» в ⋮-меню режима выделения обязан '
            'быть под тем же гейтом, что и в контекстном меню, иначе он '
            'выносит тело сообщения в обход запрета сохранения контента',
      );
    });

    test('обе точки входа гейтятся одинаково', () {
      // AC:RL-group-content-protection/13
      final menu = compact('lib/pages/chat/events/message_context_menu.dart');
      expect(
        menu.contains('if (Matrix.of(context).isCurrentUserDeveloper)'),
        isTrue,
        reason: 'контекстное меню потеряло гейт — точки входа разъехались',
      );
    });
  });

  group('тап по карточке файла не выносит файл', () {
    test('onTap гейтится isContentProtected', () {
      // `openFile` — тоже вынос: на web делегирует прямо в `saveFile`
      // (скачивание браузером), на нативных пишет РАСШИФРОВАННЫЕ байты во
      // временный файл и открывает во внешнем приложении, откуда доступны
      // «Сохранить как» и «Поделиться».
      final source = compact(
        'lib/pages/chat/events/message_download_content.dart',
      );
      // AC:RL-group-content-protection/14
      expect(
        source.contains(
          'onTap: event.room.isContentProtected ? null '
          ': () => event.openFile(context),',
        ),
        isTrue,
        reason:
            'тап по карточке файла обязан быть закрыт тем же гейтом, что и '
            'кнопка «Скачать» рядом — он выносит файл ничуть не меньше',
      );
    });

    test('openFile на web действительно сохраняет — комментарий не должен лгать', () {
      // Страж на факт, ради которого стоит гейт: если реализация openFile
      // перестанет уходить в saveFile, обоснование гейта надо пересмотреть.
      final source = compact('lib/utils/matrix_sdk_extensions/event_extension.dart');
      // AC:RL-group-content-protection/14
      expect(
        source.contains('void openFile(BuildContext context) async { if (kIsWeb) { saveFile(context);'),
        isTrue,
        reason: 'openFile на web = saveFile; на этом основан гейт onTap',
      );
    });
  });

  group('гейт в ТЕЛЕ метода, а не только на пункте меню', () {
    // Правило проекта, записанное в самом коде (chat.dart, copyEventsAction):
    // «новая точка вызова иначе снова обошла бы запрет». Оно соблюдалось для
    // мультивыбора и нарушалось для одиночных действий.
    test('copyEvent / saveEvent / copyMediaEvent проверяют защиту сами', () {
      final source = compact('lib/pages/chat/chat.dart');
      for (final signature in const [
        'void copyEvent(Event event) { '
            '// Гейт в самом методе, а не только на пункте меню (см. copyEventsAction). '
            'if (room.isContentProtected) return;',
        'void saveEvent(Event event) { '
            '// Гейт в самом методе, а не только на пункте меню (см. copyEventsAction). '
            'if (room.isContentProtected) return;',
        'Future<void> copyMediaEvent(Event event) async { '
            '// Гейт в самом методе, а не только на пункте меню (см. copyEventsAction). '
            'if (room.isContentProtected) return;',
      ]) {
        // AC:RL-group-content-protection/15
        expect(
          source.contains(signature),
          isTrue,
          reason:
              'без гейта в теле метода любая новая точка вызова (горячая '
              'клавиша, другой экран) снова обойдёт запрет: ${signature.split('(').first}',
        );
      }
    });

    test('гейты мультивыбора на месте (не потеряны при правке)', () {
      final source = compact('lib/pages/chat/chat.dart');
      // AC:RL-group-content-protection/15
      expect(
        RegExp(r'if \(room\.isContentProtected\) return;')
            .allMatches(source)
            .length,
        greaterThanOrEqualTo(6),
        reason:
            'три действия мультивыбора (copy/forward/save) + три одиночных '
            'обязаны иметь гейт в теле',
      );
    });
  });

  group('пуш не выносит тело защищённого сообщения', () {
    test('тело подменяется плейсхолдером при isContentProtected', () {
      // Шторка и экран блокировки — ДРУГОЕ окно: FLAG_SECURE самого чата на них
      // не распространяется, и текст оказался бы скриншотабелен в обход всех
      // гейтов приложения.
      final source = compact('lib/utils/push_helper.dart');
      // AC:RL-group-content-protection/16
      expect(
        source.contains(
          'final rawBody = event.type == EventTypes.Encrypted || '
          'event.room.isContentProtected ? l10n.newMessageInLiza',
        ),
        isTrue,
        reason:
            'в чате с запретом сохранения контента тело сообщения в пуш класть '
            'нельзя — оно утекает мимо всех экранных гейтов',
      );
    });
  });

  group('парность локализации', () {
    test('новые и изменённые строки есть в обоих .arb', () {
      final ru = compact('lib/l10n/intl_ru.arb');
      final en = compact('lib/l10n/intl_en.arb');
      // AC:RL-group-content-protection/17
      expect(
        ru.contains('"protectContentExemptHint"'),
        isTrue,
        reason: 'без ключа в ru Flutter молча подставит английский',
      );
      expect(en.contains('"protectContentExemptHint"'), isTrue);

      // Подпись обязана называть платформенную правду, а не расплывчатое
      // «зависит от устройства»: на iPhone, компьютере и в браузере скриншот
      // не запрещается вовсе, и обещать обратное — вводить в заблуждение.
      // AC:RL-group-content-protection/17
      expect(ru.contains('Скриншоты запрещает только Android'), isTrue);
      expect(en.contains('Screenshots are blocked on Android only'), isTrue);

      // Существующие finders завязаны на эту подстроку — не терять.
      // AC:RL-group-content-protection/17
      expect(
        ru.contains('Не действует на модераторов и администраторов.'),
        isTrue,
      );
      expect(en.contains('Moderators and admins are not affected.'), isTrue);
    });
  });
}
