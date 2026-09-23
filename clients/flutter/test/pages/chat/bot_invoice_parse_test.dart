// Страж RL-bot-invoice-checkout (парс + резолв базы).
//
// Инварианты:
//  • BotInvoiceData.parse корректно достаёт ref/title/items/currency/total_minor
//    и отбрасывает мусорные позиции (AC-9: карточка несёт display-поля + ref).
//  • bot-checkout идёт на lizaBotApiBaseForHomeserver(<homeserver>), НЕ на
//    miniAppPaymentBaseUrl; local-хост НЕ получает prod-базу (AC-5, red-proof).

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/config/app_config.dart';
import 'package:liza/pages/chat/events/bot_invoice_content.dart';

void main() {
  group('BotInvoiceData.parse', () {
    test('достаёт ref/title/items/currency/total_minor', () {
      final data = BotInvoiceData.parse({
        'msgtype': BotInvoiceContent.msgType,
        'body': 'fallback',
        'invoice_ref': 'ref-1',
        'title': 'Заказ',
        'currency': 'rub',
        'total_minor': 15000,
        'items': [
          {'label': 'Товар A', 'amount': 10000, 'quantity': 1},
          {'label': 'Товар B', 'amount': 2500, 'quantity': 2},
        ],
      });
      expect(data, isNotNull);
      expect(data!.invoiceRef, 'ref-1');
      expect(data.title, 'Заказ');
      expect(data.currency, 'RUB'); // нормализуется в upper
      expect(data.totalMinor, 15000);
      expect(data.items.length, 2);
      expect(data.items[1].quantity, 2);
      expect(data.items[1].lineTotal, 5000); // 2500 × 2
    });

    test('без invoice_ref → null (нельзя оплатить без opaque-ref)', () {
      expect(
        BotInvoiceData.parse({
          'msgtype': BotInvoiceContent.msgType,
          'title': 'Заказ',
          'items': [
            {'label': 'A', 'amount': 100},
          ],
        }),
        isNull,
      );
    });

    test('мусорные позиции отбрасываются, валидные остаются', () {
      final data = BotInvoiceData.parse({
        'invoice_ref': 'r',
        'items': [
          {'label': '', 'amount': 100}, // пустой label — отброшен
          {'label': 'X'}, // без amount — отброшен
          {
            'label': 'OK',
            'amount': 500,
            'quantity': 0,
          }, // qty<1 → нормализ. в 1
          'garbage',
        ],
      });
      expect(data, isNotNull);
      expect(data!.items.length, 1);
      expect(data.items.first.label, 'OK');
      expect(data.items.first.quantity, 1);
    });
  });

  group('bot-checkout база (AC-5, per-homeserver)', () {
    // AC:RL-bot-invoice-checkout/5
    final paymentHost = Uri.parse(AppConfig.miniAppPaymentBaseUrl).host;

    test(
      'prod-homeserver комнаты → prod Liza Bot API base, НЕ payment-хост',
      () {
        final base = AppConfig.lizaBotApiBaseForHomeserver('bots.liza.ru');
        final host = Uri.parse(base).host;
        expect(host, 'bot.tech.liza.ru');
        expect(host, isNot(paymentHost));
      },
    );

    test('local-homeserver → local Liza Bot API base (red-proof: не prod)', () {
      final base = AppConfig.lizaBotApiBaseForHomeserver('liza.local');
      expect(base, 'http://localhost:9997');
      expect(base, isNot(contains('prodamus.tech')));
    });
  });

  test('botInvoiceFormatAmount форматирует минорные единицы', () {
    expect(botInvoiceFormatAmount(30000, 'RUB'), '300.00 ₽');
    expect(botInvoiceFormatAmount(150, 'usd'), '1.50 USD');
  });
}
