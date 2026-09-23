// Страж: возврат с платёжной формы закрывает webview (не показывает «Liza Wall»).
//
// ledger:RL-payment-webview-return-close
//
// Инвариант (design 2026-08-18-bot-payment-return-and-confirmation):
//   url-кнопка «Оплатить» бота открывается во встроенном ExternalLinkWebView; после
//   оплаты форма Prodamus редиректит на наш urlSuccess (`/payment/success`) или
//   urlReturn (`/payment/return`). isPaymentReturnUrl ловит эти sentinel-пути →
//   webview закрывается и возвращает пользователя в чат бота, а НЕ грузит SPA
//   магазина (дефолтный экран «Liza Wall»). Проверяем РЕАЛЬНУЮ функцию-предикат,
//   которую использует shouldOverrideUrlLoading (не реплику).
import 'package:flutter_test/flutter_test.dart';
import 'package:liza/pages/chat/external_link_web_view.dart';

void main() {
  group('isPaymentReturnUrl', () {
    test('AC:RL-payment-webview-return-close/1 — urlSuccess закрывает', () {
      expect(
        isPaymentReturnUrl('https://store.app.tech.liza.ru/payment/success'),
        isTrue,
      );
      // С query/фрагментом (нативный возврат кладёт payment_result в hash).
      expect(
        isPaymentReturnUrl(
          'https://store.app.tech.liza.ru/payment/success?x=1',
        ),
        isTrue,
      );
    });

    test(
      'AC:RL-payment-webview-return-close/2 — urlReturn (отмена) закрывает',
      () {
        expect(
          isPaymentReturnUrl('https://store.app.tech.liza.ru/payment/return'),
          isTrue,
        );
      },
    );

    test('legacy host временно поддерживается для выпущенных WebView', () {
      // domain-migration-legacy:flutter-payment-return-host
      expect(
        isPaymentReturnUrl(
          'https://store.liza.laba.prodamus.tech/payment/success',
        ),
        isTrue,
      );
    });

    test(
      'AC:RL-payment-webview-return-close/3 — платёжная форма/сторонний хост НЕ закрывают',
      () {
        // Пока идёт оплата — не закрываем (форма, 3DS, СБП-редиректы).
        expect(
          isPaymentReturnUrl('https://mariconsult.payform.ru/?do=pay'),
          isFalse,
        );
        expect(isPaymentReturnUrl('https://bank.example/3ds/confirm'), isFalse);
        // Иные страницы магазина (лента) — не путать с возвратом оплаты.
        expect(isPaymentReturnUrl('https://store.app.tech.liza.ru/'), isFalse);
        expect(isPaymentReturnUrl(null), isFalse);
        expect(isPaymentReturnUrl(''), isFalse);
      },
    );

    test('AC:RL-payment-webview-return-close/5 — путь /payment/* на ЧУЖОМ хосте НЕ закрывает', () {
      // Защита от ложного закрытия: сторонний сайт (открытый url-кнопкой бота) с
      // тем же путём НЕ должен схлопнуть webview (иначе — навигационный баг).
      expect(isPaymentReturnUrl('https://evil.com/payment/success'), isFalse);
      expect(isPaymentReturnUrl('https://payform.ru/payment/return'), isFalse);
      // Подставной хост под общей зоной prodamus.tech — не закрываем.
      expect(
        isPaymentReturnUrl('https://evil-liza.prodamus.tech/payment/success'),
        isFalse,
      );
    });

    // Переезд доменов 2026-09-15: miniapp-store уезжает на store.app.tech.liza.ru,
    // старые сборки и уже выставленные счета ходят на старый хост — оба обязаны
    // закрывать webview.
    test('AC:RL-payment-webview-return-close/6 — старый И новый хост стора закрывают', () {
      for (final host in const [
        'store.liza.laba.prodamus.tech',
        'store.app.tech.liza.ru',
      ]) {
        for (final path in const ['/payment/success', '/payment/return']) {
          for (final tail in const ['', '/', '?x=1', '#payment_result=ok']) {
            final url = 'https://$host$path$tail';
            expect(isPaymentReturnUrl(url), isTrue, reason: url);
          }
        }
      }
    });

    test('AC:RL-payment-webview-return-close/7 — соседи по зоне и подставные хосты НЕ закрывают', () {
      // Под обеими зонами живут сторонние мини-аппы (*.apps.liza.laba…,
      // *.store.app.tech.liza.ru) и наши же не-сторовые сервисы — суффикс-матч зоны
      // дал бы им досрочно закрыть платёжный webview.
      for (final host in const [
        'x.store.app.tech.liza.ru',
        'x.apps.liza.laba.prodamus.tech',
        'dev.liza.laba.prodamus.tech',
        'auth.tech.liza.ru',
        'tech.liza.ru',
        'store.app.tech.liza.ru.evil.com',
        'store.liza.laba.prodamus.tech.evil.com',
      ]) {
        final url = 'https://$host/payment/success';
        expect(isPaymentReturnUrl(url), isFalse, reason: url);
      }
      expect(isPaymentReturnUrl('http://store.app.tech.liza.ru/payment/success'),
          isFalse);
      expect(
          isPaymentReturnUrl(
              'http://store.liza.laba.prodamus.tech/payment/return'),
          isFalse);
    });

    test('AC:RL-payment-webview-return-close/8 — не sentinel-путь на хосте стора НЕ закрывает', () {
      for (final host in const [
        'store.liza.laba.prodamus.tech',
        'store.app.tech.liza.ru',
      ]) {
        for (final path in const [
          '/payment',
          '/payment/',
          '/payment/successX',
          '/payment/success/extra',
          '/api/payment/webhook',
        ]) {
          final url = 'https://$host$path';
          expect(isPaymentReturnUrl(url), isFalse, reason: url);
        }
      }
    });
  });
}
