import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:liza/pages/chat/events/xl_buttons_content.dart';
import 'package:liza/pages/chat/external_link_web_view.dart';

// Девайсный device-flow (Ярус C, iOS+Android) для правки «оплата бота открывается
// ВНУТРИ мессенджера, а не в браузере» (RL-xl-button-url-inapp-webview, M5 спеки
// 2026-08-13-bot-payment-inapp-webview).
//
// Проверяет РЕАЛЬНУЮ навигацию `openXlButtonUrl` (production-функция, которую зовёт
// XlButtonsContent._onTap) на НАСТОЯЩИХ движках: iOS WKWebView и Android WebView —
// РАЗНЫЕ реализации, host-widget-тест (мок-платформа) их не покрывает. Тап url-кнопки
// с https-`payment_url` → встроенный `ExternalLinkWebView` появляется в дереве и
// показывает host-бар (пользователь остаётся в приложении), внешний браузер НЕ
// открывается.
//
// Сервер/seed НЕ нужны: тестируем клиентскую навигацию напрямую (как render_widgets
// инстанцирует прод-виджеты). На реальном устройстве платформа webview доступна,
// поэтому НЕ используем pumpAndSettle (реальная загрузка формы Prodamus по сети
// повесила бы settle) — только pump с фикс. длительностью до появления маршрута.

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const paymentUrl = 'https://demo.payform.ru/pay/flowtest';

  Widget host() => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => openXlButtonUrl(ctx, paymentUrl),
                child: const Text('Оплатить'),
              ),
            ),
          ),
        ),
      );

  testWidgets(
    'тап «Оплатить» (https payment_url) → встроенный webview, НЕ браузер',
    (tester) async {
      await tester.pumpWidget(host());
      await tester.pump();

      await tester.tap(find.text('Оплатить'));
      // Даём маршруту webview встроиться (без settle — реальный webview грузит сеть).
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      // Оплата открылась ВНУТРИ приложения (встроенный webview в стеке навигации).
      expect(find.byType(ExternalLinkWebView), findsOneWidget);
      // Пользователь видит host-бар формы оплаты — он в контексте мессенджера,
      // а не в системном браузере.
      expect(find.text('demo.payform.ru'), findsOneWidget);
    },
  );
}
