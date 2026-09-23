// ignore_for_file: depend_on_referenced_packages
//
// Страж RL-bot-invoice-checkout / RL-xl-buttons-ai-gate (клиентская часть).
//
// Инварианты (что нельзя сломать и почему):
//  1. Карточка `com.liza.invoice` от отправителя с ролью `ai` (бот) → видна
//     кнопка «Оформить» + позиции/итог (AC-1, реальный виджет).
//  2. Карточка от отправителя БЕЗ роли `ai` → кнопки НЕТ, деградация в текст
//     body (AC-2, red-proof: подделанная карточка обычного юзера не даёт
//     платёжной кнопки).
//  3. Парс контента (items/total/currency/ref) — display-поля из события,
//     авторитетную сумму даёт сервер (AC-9).
//  4. bot-checkout резолвится через lizaBotApiBaseForHomeserver, НЕ
//     miniAppPaymentBaseUrl (AC-5, две разные оси базы).
//
// Рендерит РЕАЛЬНЫЙ виджет BotInvoiceContent через Matrix.of(context) с
// подменённым UserRoleService (как user_role_badge_real_ai_only_test).

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:liza/config/app_config.dart';
import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/events/bot_invoice_content.dart';
import 'package:liza/utils/user_role_service.dart';
import 'package:liza/widgets/matrix.dart' as liza_matrix;

import '../../utils/test_client.dart';

class _TestMatrixState extends liza_matrix.MatrixState {
  _TestMatrixState(this._client, this._roleService);

  final Client _client;
  final UserRoleService _roleService;

  @override
  Client get client => _client;

  @override
  UserRoleService get userRoleService => _roleService;
}

Widget _wrap(Widget child, liza_matrix.MatrixState state) => MaterialApp(
  localizationsDelegates: const [
    L10n.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: L10n.supportedLocales,
  locale: const Locale('ru'),
  home: Provider<liza_matrix.MatrixState>.value(
    value: state,
    child: Scaffold(body: child),
  ),
);

Event _invoiceEvent(Room room, String senderId) => Event(
  type: EventTypes.Message,
  content: {
    'msgtype': BotInvoiceContent.msgType,
    'body': 'Ваш заказ на 300 ₽',
    'invoice_ref': 'ref-abc-123',
    'title': 'Фудкорт Тест',
    'currency': 'RUB',
    'total_minor': 30000,
    'items': [
      {'label': 'Бургер', 'amount': 20000, 'quantity': 1},
      {'label': 'Кола', 'amount': 5000, 'quantity': 2},
    ],
  },
  eventId: '\$inv1',
  senderId: senderId,
  originServerTs: DateTime.now(),
  room: room,
);

void main() {
  late Client client;

  setUp(() async {
    client = await prepareTestClient();
  });

  tearDown(() async {
    await client.dispose(closeDatabase: true);
  });

  UserRoleService roleService({String? aiUser}) {
    final service = UserRoleService(() => client);
    if (aiUser != null) {
      service.applyToDeviceEvent(aiUser, {'code': 'ai', 'label': 'ИИ'});
    }
    return service;
  }

  // AC-1: карточка от бота (роль ai) → кнопка «Оформить» (или «Скоро» при
  // выключенном флаге) + позиции + итог.
  // AC:RL-bot-invoice-checkout/1
  testWidgets('от бота (роль ai): карточка с позициями, итогом и кнопкой', (
    tester,
  ) async {
    const bot = '@foodcourt:bots.liza.ru';
    final room = Room(id: '!r:bots.liza.ru', client: client);
    final event = _invoiceEvent(room, bot);
    final state = _TestMatrixState(client, roleService(aiUser: bot));

    await tester.pumpWidget(
      _wrap(BotInvoiceContent(event: event, textColor: Colors.black), state),
    );
    await tester.pumpAndSettle();

    // Заголовок и позиции видны.
    expect(find.text('Фудкорт Тест'), findsOneWidget);
    expect(find.text('Бургер'), findsOneWidget);
    // Количество > 1 показывается в строке позиции.
    expect(find.text('Кола × 2'), findsOneWidget);
    // Итог.
    expect(find.text('Итого'), findsOneWidget);
    expect(find.text('300.00 ₽'), findsWidgets);

    // Кнопка действия присутствует (лейбл зависит от флага botInvoiceEnabled).
    final expectedLabel = AppConfig.botInvoiceEnabled ? 'Оформить' : 'Скоро';
    expect(find.widgetWithText(FilledButton, expectedLabel), findsOneWidget);
  });

  // AC-2 (red-proof): карточка от отправителя БЕЗ роли ai → кнопки НЕТ,
  // деградация в текст body. Спуфинг платёжной карточки обычным юзером не должен
  // давать платёжную кнопку.
  // AC:RL-bot-invoice-checkout/2
  testWidgets('НЕ от бота: кнопки нет, только текст body (red-proof)', (
    tester,
  ) async {
    const human = '@mallory:example.test';
    final room = Room(id: '!r:example.test', client: client);
    final event = _invoiceEvent(room, human);
    // roleService без ai-роли для отправителя.
    final state = _TestMatrixState(client, roleService());

    await tester.pumpWidget(
      _wrap(BotInvoiceContent(event: event, textColor: Colors.black), state),
    );
    await tester.pumpAndSettle();

    // Никакой кнопки «Оформить»/«Скоро».
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('Оформить'), findsNothing);
    expect(find.text('Скоро'), findsNothing);
    // Карточных элементов (позиции/итог) нет — только текст body.
    expect(find.text('Итого'), findsNothing);
    expect(find.text('Бургер'), findsNothing);
    expect(find.text('Ваш заказ на 300 ₽'), findsOneWidget);
  });
}
