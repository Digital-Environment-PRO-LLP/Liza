import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ledger:RL-group-content-protection

// Task 10, Fix round 3 (2026-07-30): независимое ревью нашло два Critical-обхода,
// которые прошлые раунды не закрыли, потому что структурные тесты по построению
// проверяют присутствие гейта в УЖЕ известных точках и не могут найти
// незакрытое место:
//
// 1. `ImageViewer` — полноэкранный просмотрщик медиа, достижимый тапом по любой
//    картинке/видео (пузырь, галерея, вкладка «Изображения» в поиске). Все три
//    кнопки его AppBar (переслать / скачать / поделиться) выносили контент без
//    какого-либо гейта — два тапа от любого фото, на всех платформах.
// 2. Поиск по чату — тап по файлу скачивал его (`saveFile`), а `SelectionArea`
//    вокруг результатов стояла безусловно и БЕЗ гейта `!PlatformInfos.isMobile`,
//    то есть выделение+копирование работало даже на телефоне.
//
// Плюс fallback-кнопки «Скачать» на экране/в снекбаре ошибки полноэкранного
// видеоплеера (гейтились только `storyMode`) и асимметрия кнопки «Копировать»
// в selectMode.
//
// Принцип прежний: просмотр не запрещаем, запрещаем ВЫНОС контента наружу.
//
// Структурный тест по исходнику — тот же паттерн, что в
// multiselect_content_protection_test.dart и media_content_protection_test.dart
// (полноценная Room/Client в unit-окружении неподъёмна). Мутационная проверка
// задокументирована в отчёте задачи.
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

  group('Critical 1: ImageViewer — гейт выноса контента', () {
    test('контроллер отдаёт isContentProtected по комнате текущего медиа', () {
      final source = compact('lib/pages/image_viewer/image_viewer.dart');
      expect(
        source.contains(
          'bool get isContentProtected => currentEvent.room.isContentProtected;',
        ),
        isTrue,
        reason:
            'просмотрщик листает карусель — гейт должен считаться по событию '
            'текущей страницы, а не по одной комнате на весь виджет',
      );
    });

    test('forwardAction гейтится в самом методе', () {
      final source = compact('lib/pages/image_viewer/image_viewer.dart');
      expect(
        source.contains(
          'void forwardAction() async { if (isContentProtected) return;',
        ),
        isTrue,
        reason:
            'пересылка медиа из просмотрщика — вынос контента; гейт в методе '
            'устойчив к новым точкам вызова, скрытие кнопки — только UX',
      );
    });

    test('saveFileAction гейтится в самом методе', () {
      final source = compact('lib/pages/image_viewer/image_viewer.dart');
      expect(
        source.contains(
          'void saveFileAction(BuildContext context) { '
          'if (isContentProtected) return; currentEvent.saveFile(context); }',
        ),
        isTrue,
        reason: 'скачивание медиа из просмотрщика должно быть закрыто',
      );
    });

    test('shareFileAction гейтится в самом методе', () {
      final source = compact('lib/pages/image_viewer/image_viewer.dart');
      expect(
        source.contains(
          'void shareFileAction(BuildContext context) { '
          'if (isContentProtected) return; currentEvent.shareFile(context); }',
        ),
        isTrue,
        reason:
            'системный share-sheet выносит файл в любое другое приложение — '
            'самый широкий путь выноса на мобильных',
      );
    });

    test('кнопки «переслать»/«скачать» в AppBar скрыты при защите', () {
      final source = compact('lib/pages/image_viewer/image_viewer_view.dart');
      expect(
        source.contains('if (!controller.isContentProtected) ...['),
        isTrue,
        reason:
            'кнопки выноса контента не должны рисоваться в защищённом канале '
            '— иначе нажатие молча ничего не делает, это плохой UX',
      );
    });

    test('кнопка «поделиться» скрыта при защите', () {
      final source = compact('lib/pages/image_viewer/image_viewer_view.dart');
      expect(
        source.contains(
          'if (PlatformInfos.isMobile && !controller.isContentProtected)',
        ),
        isTrue,
        reason: 'share-кнопка гейтится дополнительно к своему isMobile',
      );
    });

    test('просмотр медиа НЕ гейтится (PageView строится всегда)', () {
      final source = compact('lib/pages/image_viewer/image_viewer_view.dart');
      expect(
        source.contains('PageView.builder('),
        isTrue,
        reason:
            'смотреть медиа в защищённом канале можно — закрыт только вынос',
      );
    });
  });

  group('Critical 2: поиск по чату — гейт скачивания и выделения', () {
    test('тап по файлу в поиске не скачивает при защите', () {
      final source = compact(
        'lib/pages/chat_search/chat_search_files_tab.dart',
      );
      expect(
        source.contains(
          'onTap: contentProtected ? null : () => event.saveFile(context),',
        ),
        isTrue,
        reason:
            'тап по результату во вкладке «Файлы» вызывает saveFile напрямую '
            '— скачивание в обход и меню, и панели множественного выбора',
      );
    });

    test('SelectionArea во вкладке «Файлы» гейтится', () {
      final source = compact(
        'lib/pages/chat_search/chat_search_files_tab.dart',
      );
      expect(
        source.contains(
          'return protectedSelectionArea( selectable: !contentProtected,',
        ),
        isTrue,
        reason:
            'безусловная SelectionArea вокруг результатов давала выделение и '
            'нативное меню «Copy», причём и на мобильных тоже',
      );
    });

    test('SelectionArea во вкладке «Сообщения» гейтится', () {
      final source = compact(
        'lib/pages/chat_search/chat_search_message_tab.dart',
      );
      expect(
        source.contains(
          'return protectedSelectionArea( '
          'selectable: !room.isContentProtected,',
        ),
        isTrue,
        reason:
            'текст найденных сообщений выделялся мышью и копировался в обход '
            'гейтов ленты',
      );
    });

    test('protectedSelectionArea не создаёт обёртку при запрете', () {
      final source = compact('lib/utils/protected_selection.dart');
      expect(
        source.contains('selectable ? SelectionArea(child: child) : child;'),
        isTrue,
        reason:
            'обёртку нужно именно НЕ создавать: SelectionArea без параметра '
            '«выключено» всё равно даёт нативное контекстное меню',
      );
    });
  });

  // ⚠️ ПЕРЕСМОТРЕНО 2026-09-04 (LABA-2541). Раньше здесь проверялось, что
  // «Скачать» на экране ошибки видео и в снекбаре гейтится по
  // isContentProtected. С 2026-08-31 обе кнопки УДАЛЕНЫ целиком (error overlay =
  // постер + «Повторить»), то есть пути выноса больше нет вовсе — это строго
  // сильнее гейта. Стражим именно отсутствие пути: если «Скачать» вернут, он
  // обязан вернуться с гейтом, и этот тест покраснеет, заставив пересмотреть.
  group('Important 3: в полноэкранном видеоплеере нет пути «Скачать»', () {
    test('на экране ошибки не предлагается скачивание', () {
      final source = compact('lib/pages/image_viewer/video_player.dart');
      expect(
        source.contains('saveFile(') || source.contains('downloadFile'),
        isFalse,
        reason:
            'вернувшийся путь скачивания из полноэкранного плеера обязан '
            'гейтиться isContentProtected — пересмотри страж вместе с ним',
      );
    });
  });

  group('Important 4: симметрия кнопки «Копировать» в selectMode', () {
    test('кнопка требует и hasCopyableText, и снятой защиты', () {
      final source = compact('lib/pages/chat/chat_view.dart');
      expect(
        source.contains(
          'if (controller.canCopySelectedEvents && '
          '!controller.room.isContentProtected)',
        ),
        isTrue,
        reason:
            'в незащищённом чате кнопка рисовалась безусловно и копировала '
            'generic-заглушку («Отправил картинку») с медиа без подписи — '
            'контекстное меню в этом случае пункт прячет',
      );
    });

    test('canCopySelectedEvents переиспользует shouldOfferCopyText', () {
      final source = compact('lib/pages/chat/chat.dart');
      expect(
        source.contains(
          'bool get canCopySelectedEvents => selectedEvents.any((event) {',
        ) &&
            source.contains(
              'return shouldOfferCopyText( isMedia: display.isMediaEvent,',
            ),
        isTrue,
        reason:
            'критерий «есть ли что копировать» должен быть один и тот же в '
            'меню одиночного сообщения и в панели множественного выбора',
      );
    });
  });

  group('Minor 5: гейт в методах контроллера, а не только на кнопках', () {
    test('copyEventsAction гейтится', () {
      final source = compact('lib/pages/chat/chat.dart');
      expect(
        source.contains('void copyEventsAction() { // Гейт в самом методе'),
        isTrue,
        reason: 'новая точка вызова иначе снова обойдёт запрет',
      );
      expect(
        source.contains(
          'if (room.isContentProtected) return; unawaited( '
          'Clipboard.setData(ClipboardData(text: _getSelectedEventString())), );',
        ),
        isTrue,
        reason: 'проверка должна стоять ПЕРЕД записью в буфер обмена',
      );
    });

    test('forwardEventsAction гейтится', () {
      final source = compact('lib/pages/chat/chat.dart');
      expect(
        source.contains(
          'void forwardEventsAction() async { // Гейт в самом методе, а не '
          'только на кнопке (см. copyEventsAction). '
          'if (room.isContentProtected) return;',
        ),
        isTrue,
        reason: 'пересылка выбранных событий должна отсекаться в методе',
      );
    });

    test('saveSelectedFiles гейтится', () {
      final source = compact('lib/pages/chat/chat.dart');
      expect(
        source.contains(
          'Future<void> saveSelectedFiles(BuildContext context) async { '
          '// Гейт в самом методе, а не только на кнопке '
          '(см. copyEventsAction). if (room.isContentProtected) return;',
        ),
        isTrue,
        reason: 'массовое сохранение вложений должно отсекаться в методе',
      );
    });
  });

  group('Minor 6: текст настройки честно описывает защиту от скриншотов', () {
    // Инвариант группы (смысл прежний: описание НЕ должно врать о поведении),
    // но обе крайние формулировки — ложь, и тест обязан отсекать обе:
    //  1) «...и делать скриншоты постов» — обещало блокировку везде, а на
    //     desktop/web её нет и не будет;
    //  2) «Скриншоты не блокируются.» — отрицало блокировку везде, но на
    //     Android она РЕАЛЬНО есть: MainActivity.kt дёргает FLAG_SECURE по
    //     каналу `SECURE_SCREEN_CHANNEL`.
    // Честная формулировка — «зависит от устройства/платформы».
    //
    // ⚠️ УСИЛЕНО 2026-09-04 (LABA-2541): «зависит от устройства» формально не
    // ложь, но неинформативно — пользователь читает «зависит», а на его
    // iPhone, компьютере и в браузере скриншот не запрещён ВООБЩЕ. Подпись
    // теперь называет платформы поимённо.
    test('RU-описание не обещает и не отрицает блокировку скриншотов', () {
      final arb = File('lib/l10n/intl_ru.arb').readAsStringSync();
      expect(
        arb.contains('Скриншоты запрещает только Android'),
        isTrue,
        reason:
            'блокировка скриншотов платформозависима (Android — FLAG_SECURE, '
            'iOS/desktop/web — нет), и описание обязано называть это прямо, а '
            'не прятаться за «зависит от устройства»',
      );
      expect(
        arb.contains('и делать скриншоты постов'),
        isFalse,
        reason: 'старая переобещающая формулировка должна быть убрана',
      );
      expect(
        arb.contains('Скриншоты не блокируются.'),
        isFalse,
        reason:
            'обратная ложь: на Android скриншоты блокируются через FLAG_SECURE',
      );
      expect(
        arb.contains('Не действует на модераторов и администраторов.'),
        isTrue,
        reason:
            'оговорка про модераторов и администраторов — часть честного '
            'описания поведения гейта (порог PL >= 50, задача 2026-08-12), '
            'её нельзя потерять при переформулировках',
      );
    });

    test('EN-описание синхронно с RU', () {
      final arb = File('lib/l10n/intl_en.arb').readAsStringSync();
      expect(
        arb.contains('Screenshots are blocked on Android only'),
        isTrue,
        reason: 'ключ обязан существовать в обоих .arb с тем же смыслом',
      );
      expect(arb.contains('copy or screenshot posts'), isFalse);
      expect(
        arb.contains('Screenshots are not blocked.'),
        isFalse,
        reason: 'та же обратная ложь, что и в RU',
      );
      expect(arb.contains('Moderators and admins are not affected.'), isTrue);
    });

    test('нативный гейт FLAG_SECURE существует — иначе текст снова врёт', () {
      final source = compact(
        'android/app/src/main/kotlin/com/prodamus/laba/liza/android/'
        'MainActivity.kt',
      );
      expect(
        source.contains(
          'window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)',
        ),
        isTrue,
        reason:
            'формулировка «защита от скриншотов зависит от устройства» честна '
            'ровно пока хотя бы одна платформа её реализует; выпадет '
            'FLAG_SECURE — текст снова станет ложью и его надо будет менять',
      );
    });
  });
}
