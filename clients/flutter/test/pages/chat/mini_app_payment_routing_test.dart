import 'package:flutter_test/flutter_test.dart';

import 'package:liza/config/app_config.dart';
import 'package:liza/pages/chat/mini_app_web_view.dart';

// Страж реестра регрессии: ledger:RL-thirdparty-invoice-target (см. tests/registry/).
//
// Инвариант (что нельзя сломать и почему): для СТОРОННЕГО (third_party) mini App
// клиент обязан слать create-invoice/status на НАШ платёжный модуль
// (AppConfig.miniAppPaymentBaseUrl), а НЕ на домен приложения. Иначе подписанная
// X-Liza-Init-Data пользователя уходит на сервер разработчика, который вернёт
// произвольный payment_url (дыра §8.6 п.8). Для first_party поведение прежнее
// (резолв от appUrl) — рабочий путь оплаты не трогаем.
//
// Тестируем РЕАЛЬНУЮ функцию miniAppPaymentResolve из mini_app_web_view.dart
// (а не копию), поэтому смена роутинга в проде детерминированно роняет тест.

void main() {
  group('miniAppPaymentResolve (RL-thirdparty-invoice-target)', () {
    const evilAppUrl = 'https://evil-developer.example';
    final paymentHost = Uri.parse(AppConfig.miniAppPaymentBaseUrl).host;

    test(
      'third_party: create-invoice идёт на наш payment-хост, не на appUrl',
      () {
        final uri = miniAppPaymentResolve(
          isThirdParty: true,
          appUrl: evilAppUrl,
          path: '/api/payment/create-invoice',
        );
        expect(uri.host, paymentHost);
        expect(uri.host, isNot('evil-developer.example'));
        expect(uri.path, '/api/payment/create-invoice');
      },
    );

    test('third_party: status идёт на наш payment-хост, не на appUrl', () {
      final uri = miniAppPaymentResolve(
        isThirdParty: true,
        appUrl: evilAppUrl,
        path: '/api/payment/invoice/42/status',
      );
      expect(uri.host, paymentHost);
      expect(uri.path, '/api/payment/invoice/42/status');
    });

    test('first_party: резолв от appUrl (прежнее поведение, инвариант)', () {
      final uri = miniAppPaymentResolve(
        isThirdParty: false,
        appUrl: 'https://store.app.tech.liza.ru',
        path: '/api/payment/create-invoice',
      );
      expect(uri.host, 'store.app.tech.liza.ru');
      expect(uri.path, '/api/payment/create-invoice');
    });
  });

  group('isProdamusPaymentHost (сужение платёжного allowlist)', () {
    test('пропускает фактические платёжные хосты Prodamus', () {
      expect(isProdamusPaymentHost('mariconsult.payform.ru'), isTrue);
      expect(isProdamusPaymentHost('midget.payform.ru'), isTrue);
      expect(isProdamusPaymentHost('payform.ru'), isTrue);
      expect(isProdamusPaymentHost('securepayform.ru'), isTrue);
      expect(isProdamusPaymentHost('gw.payform.online'), isTrue);
    });

    test('НЕ пропускает наш периметр .prodamus.tech / .prodamus.ru', () {
      // Раньше широкий matcher пускал third_party-навигацию на нашу инфраструктуру.
      expect(isProdamusPaymentHost('synapse.liza.laba.prodamus.tech'), isFalse);
      // Старый auth-хост — только входной алиас, не платёжный origin.
      // domain-migration-legacy:flutter-payment-return-host
      expect(isProdamusPaymentHost('auth.liza.laba.prodamus.tech'), isFalse);
      expect(isProdamusPaymentHost('store.app.tech.liza.ru'), isFalse);
      expect(isProdamusPaymentHost('id.prodamus.ru'), isFalse);
    });

    test('НЕ пропускает похожие-но-чужие домены и null', () {
      expect(isProdamusPaymentHost('notpayform.ru'), isFalse);
      expect(isProdamusPaymentHost('payform.ru.evil.com'), isFalse);
      expect(isProdamusPaymentHost(null), isFalse);
    });
  });

  group('thirdPartyPaymentAllowed (G2 gated on isolation)', () {
    test('third_party разрешён ТОЛЬКО при включённом shell-host', () {
      expect(
        thirdPartyPaymentAllowed(isThirdParty: true, shellHostEnabled: false),
        isFalse,
      );
      expect(
        thirdPartyPaymentAllowed(isThirdParty: true, shellHostEnabled: true),
        isTrue,
      );
    });

    test(
      'first_party не зависит от shell-host (платёж всегда доступен своему)',
      () {
        // first_party оплату гейтит не эта функция (она про third_party); проверяем,
        // что для isThirdParty=false результат false (ветка G2 к нему не применяется).
        expect(
          thirdPartyPaymentAllowed(
            isThirdParty: false,
            shellHostEnabled: false,
          ),
          isFalse,
        );
      },
    );
  });
}
