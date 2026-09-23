import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/main.dart' as app;
import 'package:liza/pages/chat_list/chat_list_body.dart';
import 'package:liza/utils/url_launcher.dart';

import 'liza_flows.dart';

/// Страж device-flow (ledger:RL-channel-link-open-internal).
/// Сквозная проверка на устройстве (iOS+Android): тап по ссылке на канал
/// `https://me.liza.ru/c/<handle>` открывает КАНАЛ ВНУТРИ приложения, а НЕ
/// уходит во внешний браузер (откуда ОС показывала лист «Поделиться»).
///
/// Доказательство «взят внутренний маршрут»: `UrlLauncher.launchUrl` →
/// `resolveInternalRoute` → `context.go('/c/<handle>')` → `_handleChannelHandle`
/// пытается резолвить ник и на несуществующем показывает snackbar-ошибку
/// канал-ссылки. До фикса https-ссылка уходила в
/// `launchUrlString(externalApplication)` — этого snackbar НЕ было бы, экран
/// остался бы списком чатов без навигации.
///
/// Ник заведомо несуществующий, но ВАЛИДНОГО формата (`^[a-z][a-z0-9_]{4,31}$`)
/// — чтобы дойти именно до резолва (невалидный отсёкся бы раньше, тоже внутри,
/// но мы проверяем полный путь резолва).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Liza e2e: ссылка на канал открывает канал, а не «Поделиться»', () {
    testWidgets('тап me.liza.ru/c/<handle> → внутренний маршрут (snackbar '
        'канал-ссылки), не внешний share', (tester) async {
      SharedPreferences.setMockInitialValues({
        'chat.fluffy.show_no_google': false,
      });

      app.main();
      await tester.ensureLizaHome();

      // Список чатов на экране — контекст берём из-под MatrixWidget.
      expect(find.byType(ChatListViewBody), findsOneWidget);
      final context = tester.element(find.byType(ChatListViewBody));

      const link = 'https://me.liza.ru/c/testchannel12345';
      UrlLauncher(context, link).launchUrl();

      // Наблюдаемый эффект внутреннего маршрута: snackbar ошибки канал-ссылки
      // (ник не резолвится). Любой из двух исходов резолва (404 / отказ сети)
      // доказывает, что _handleChannelHandle отработал — то есть маршрут был
      // ВНУТРЕННИМ, а не внешний launch.
      await tester.waitUntil(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              const {
                'Канал не найден или больше не публичный',
                'Channel not found or no longer public',
                'Не удалось открыть канал. Проверьте соединение и попробуйте снова',
                'Could not open the channel. Check your connection and try again',
              }.contains(w.data),
        ),
        timeout: const Duration(seconds: 20),
      );
    });
  });
}
