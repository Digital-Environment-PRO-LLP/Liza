// ledger:RL-channel-access-settings-layout
//
// AC-8 (2026-08-25). Подзаголовок плитки «Доступность и видимость» в деталях
// КАНАЛА говорил «...войти в этот ЧАТ...» вместо «...канал...». Плитка живёт в
// chat_details_view.dart и видна каналу (гейт canEditChannelSettings, НЕ
// !isChannel), поэтому ветвление обязано быть по room.isChannel — иначе обычная
// группа получит «канал».
//
// Файл ВЫНЕСЕН отдельно от chat_access_settings_layout_test.dart намеренно:
// тот экран правит параллельная сессия (group-chat-rights), не смешиваем.
//
// Red-proof: убрать room.isChannel-ветку subtitle в chat_details_view.dart →
// source-scan не находит accessAndVisibilityDescriptionChannel → тест краснеет.

// AC:RL-channel-access-settings-layout/8

// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/l10n/l10n.dart';

void main() {
  group('AC-8 [AC:RL-channel-access-settings-layout/8] — subtitle доступности в канале', () {
    test('chat_details_view ветвит subtitle по room.isChannel', () {
      final src = File(
        'lib/pages/chat_details/chat_details_view.dart',
      ).readAsStringSync();
      expect(
        src.contains('accessAndVisibilityDescriptionChannel'),
        isTrue,
        reason: 'канальный вариант описания обязан быть на call-site',
      );
      expect(
        RegExp(r'room\.isChannel[\s\S]{0,160}accessAndVisibilityDescriptionChannel')
            .hasMatch(src),
        isTrue,
        reason: 'ветвление по room.isChannel (не canEditChannelSettings) — '
            'иначе обычная группа получит «канал»',
      );
    });

    testWidgets('паритет RU: канальное описание доступности', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: Scaffold(
            body: Builder(
              builder: (c) =>
                  Text(L10n.of(c).accessAndVisibilityDescriptionChannel),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Кому разрешено войти в этот канал и как этот канал может быть обнаружен.',
        ),
        findsOneWidget,
        reason: 'RU-строка обязана быть в intl_ru.arb',
      );
      expect(
        find.text(
          'Who is allowed to join this channel and how the channel can be discovered.',
        ),
        findsNothing,
        reason: 'EN не должен всплыть при locale=ru',
      );
    });
  });
}
