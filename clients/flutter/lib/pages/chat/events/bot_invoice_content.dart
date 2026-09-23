import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';
import 'package:http/http.dart' as http;

import 'package:liza/config/app_config.dart';
import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/bot_payment_web_view.dart';
import 'package:liza/pages/chat/external_link_web_view.dart'
    show isSafeHttpsUrl;
import 'package:liza/utils/phone_number.dart';
import 'package:liza/widgets/matrix.dart';

/// Одна позиция заказа в карточке инвойса бота.
class BotInvoiceItem {
  final String label;

  /// Минорные единицы (копейки) за единицу.
  final int amount;
  final int quantity;

  const BotInvoiceItem({
    required this.label,
    required this.amount,
    this.quantity = 1,
  });

  int get lineTotal => amount * quantity;
}

/// Разобранный контент события `com.liza.invoice`.
///
/// Сумма/состав в карточке — ТОЛЬКО для отображения; авторитетную сумму отдаёт
/// сервер в ответе `/bot-checkout` (`total_amount`). Карточка несёт opaque-ref
/// (`invoice_ref`) — по нему сервер читает персистентный заказ.
class BotInvoiceData {
  final String invoiceRef;
  final String title;
  final List<BotInvoiceItem> items;
  final String currency;

  /// Итог из карточки (минорные единицы) — display-only, для превью до checkout.
  final int totalMinor;

  const BotInvoiceData({
    required this.invoiceRef,
    required this.title,
    required this.items,
    required this.currency,
    required this.totalMinor,
  });

  static BotInvoiceData? parse(Map<String, Object?> content) {
    final ref = content['invoice_ref']?.toString();
    if (ref == null || ref.isEmpty) return null;

    final items = <BotInvoiceItem>[];
    final rawItems = content['items'];
    if (rawItems is List) {
      for (final it in rawItems) {
        if (it is! Map) continue;
        final label = it['label']?.toString() ?? '';
        final amount = _asInt(it['amount']);
        if (label.isEmpty || amount == null) continue;
        final qty = _asInt(it['quantity']) ?? 1;
        items.add(
          BotInvoiceItem(
            label: label,
            amount: amount,
            quantity: qty < 1 ? 1 : qty,
          ),
        );
      }
    }

    return BotInvoiceData(
      invoiceRef: ref,
      title: content['title']?.toString() ?? '',
      items: items,
      currency: (content['currency']?.toString() ?? 'RUB').toUpperCase(),
      totalMinor: _asInt(content['total_minor']) ?? 0,
    );
  }

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}

String botInvoiceFormatAmount(int minor, String currency) {
  final symbol = currency.toUpperCase() == 'RUB' ? '₽' : currency.toUpperCase();
  return '${(minor / 100).toStringAsFixed(2)} $symbol';
}

/// Карточка платёжного инвойса бота (`com.liza.invoice`) с кнопкой «Оформить».
///
/// Рендерит заголовок заказа, список позиций с ценами и итог. Кнопка «Оформить»
/// → нативный лист ввода телефона + подтверждения серверной суммы → `/bot-checkout`
/// → платёжный WebView Prodamus → опрос статуса.
///
/// **Гейт роли `ai`** (`Matrix.of(context).isAiUser`): интерактивную карточку
/// рисуем ТОЛЬКО когда отправитель — бот. Иначе (подделанная карточка от обычного
/// пользователя) — деградация в текст `body`.
///
/// **Гейт `AppConfig.botInvoiceEnabled`:** карточка/позиции видны всегда, но
/// действие оплаты («Оформить») доступно только при включённом флаге (иначе
/// кнопка показывает «Скоро»/недоступна) — чтобы слить код в main до готовности
/// прод-цепочки и включить сборкой.
class BotInvoiceContent extends StatefulWidget {
  final Event event;
  final Color textColor;

  const BotInvoiceContent({
    required this.event,
    required this.textColor,
    super.key,
  });

  /// msgtype события платёжного инвойса бота.
  static const String msgType = 'com.liza.invoice';

  @override
  State<BotInvoiceContent> createState() => _BotInvoiceContentState();
}

class _BotInvoiceContentState extends State<BotInvoiceContent> {
  bool _busy = false;

  BotInvoiceData? get _data => BotInvoiceData.parse(widget.event.content);

  Widget _bodyText() {
    final body = widget.event.body;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(body, style: TextStyle(color: widget.textColor)),
    );
  }

  Future<void> _onCheckout(BotInvoiceData data) async {
    if (_busy) return;
    final l10n = L10n.of(context);
    final phone = await _askPhone(data);
    if (phone == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final client = widget.event.room.client;
      final token = client.accessToken;
      if (token == null) {
        _snack(l10n.botInvoicePaymentError);
        return;
      }
      // Base — per-homeserver: homeserver комнаты, НЕ APP_ENV и НЕ payment-хост.
      final host = widget.event.room.id.split(':').last;
      final base = AppConfig.lizaBotApiBaseForHomeserver(host);
      final resp = await http.post(
        Uri.parse(base).resolve('/bot-checkout'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'invoice_ref': data.invoiceRef, 'phone': phone}),
      );
      if (resp.statusCode != 200) {
        Logs().e('[BotInvoice] bot-checkout: ${resp.statusCode} ${resp.body}');
        _snack(l10n.botInvoicePaymentError);
        return;
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final paymentUrl = body['payment_url'] as String?;
      // Валидируем схему ДО загрузки в WebView: initialUrlRequest НЕ проходит
      // shouldOverrideUrlLoading, поэтому битый/не-https payment_url (сбой сервера)
      // иначе загрузился бы как есть. isSafeHttpsUrl — общий валидатор.
      if (paymentUrl == null || !isSafeHttpsUrl(paymentUrl)) {
        _snack(l10n.botInvoicePaymentUnavailable);
        return;
      }
      if (!mounted) return;
      final status = await BotPaymentWebView.open(
        context: context,
        paymentUrl: paymentUrl,
        invoiceRef: data.invoiceRef,
        lizaBotApiBase: base,
        accessToken: token,
      );
      if (!mounted) return;
      if (status == 'paid') {
        _snack(l10n.botInvoicePaid);
      } else if (status == 'failed') {
        _snack(l10n.botInvoicePaymentError);
      }
      // cancelled / null — тихо (пользователь сам закрыл или таймаут).
    } catch (e) {
      Logs().e('[BotInvoice] checkout error: $e');
      if (mounted) _snack(l10n.botInvoicePaymentError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
    );
  }

  /// Нативный лист ввода телефона + подтверждения суммы.
  ///
  /// Сумму показываем из карточки (`total_minor`) как превью — серверную
  /// (`total_amount` из `/bot-checkout`) увидим на форме Prodamus. Телефон
  /// обязателен (форма Prodamus + чек 54-ФЗ, решение Q3).
  Future<String?> _askPhone(BotInvoiceData data) {
    final l10n = L10n.of(context);
    final controller = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;
        final amount = botInvoiceFormatAmount(data.totalMinor, data.currency);
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 4,
            bottom: 20 + MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.botInvoiceCheckoutTitle,
                textAlign: TextAlign.center,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (data.totalMinor > 0)
                Text(
                  amount,
                  textAlign: TextAlign.center,
                  style: Theme.of(sheetContext).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.phone,
                autofocus: true,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-()\s]')),
                ],
                decoration: InputDecoration(
                  labelText: l10n.botInvoicePhoneLabel,
                  hintText: '+7 900 000-00-00',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  final v = completePhoneOrNull(controller.text);
                  if (v == null) {
                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                      SnackBar(content: Text(l10n.botInvoicePhoneInvalid)),
                    );
                    return;
                  }
                  Navigator.of(sheetContext).pop(v);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  minimumSize: const Size.fromHeight(44),
                ),
                child: Text(l10n.botInvoiceProceedToPay),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: Text(l10n.cancel),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    // Парс не удался (нет ref) → безопасно деградируем в текст.
    if (data == null) return _bodyText();

    // Гейт роли `ai`: карточку-инвойс рисуем только от доверенного отправителя
    // (бот). От обычного пользователя (подделка) — только текст body.
    final senderIsBot = Matrix.of(context).isAiUser(widget.event.senderId);
    if (!senderIsBot) return _bodyText();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = L10n.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppConfig.borderRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Text(
                  data.title.isNotEmpty ? data.title : l10n.botInvoiceTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: widget.textColor,
                  ),
                ),
              ),
              // Позиции заказа: имя слева, цена (× количество) справа.
              for (final item in data.items)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.quantity > 1
                              ? '${item.label} × ${item.quantity}'
                              : item.label,
                          style: TextStyle(
                            fontSize: 14,
                            color: widget.textColor.withAlpha(220),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        botInvoiceFormatAmount(item.lineTotal, data.currency),
                        style: TextStyle(
                          fontSize: 14,
                          color: widget.textColor.withAlpha(220),
                        ),
                      ),
                    ],
                  ),
                ),
              if (data.totalMinor > 0) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Divider(height: 1),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.botInvoiceTotal,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: widget.textColor,
                          ),
                        ),
                      ),
                      Text(
                        botInvoiceFormatAmount(data.totalMinor, data.currency),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: widget.textColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: FilledButton(
                  // Гейт флага: пока путь оплаты не включён сборкой — кнопка
                  // неактивна и показывает «Скоро».
                  onPressed: (AppConfig.botInvoiceEnabled && !_busy)
                      ? () => _onCheckout(data)
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppConfig.borderRadius / 2,
                      ),
                    ),
                    minimumSize: const Size.fromHeight(44),
                  ),
                  child: _busy
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : Text(
                          AppConfig.botInvoiceEnabled
                              ? l10n.botInvoiceProceed
                              : l10n.botInvoiceComingSoon,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
