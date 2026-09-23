import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/l10n/l10n.dart';

/// Карточка заказа / данных из Mini App в чате.
///
/// Рендерит сообщение с `msgtype: "com.liza.miniapp.data"` как структурированную
/// карточку с деталями заказа (товары, сумма, статус).
class MiniAppDataContent extends StatelessWidget {
  final Event event;
  final Color textColor;

  const MiniAppDataContent({
    required this.event,
    required this.textColor,
    super.key,
  });

  static const String msgType = 'com.liza.miniapp.data';

  static const _statusIcons = {
    'pending': '⏳',
    'paid': '✅',
    'processing': '📋',
    'shipped': '📦',
    'delivered': '🎉',
    'cancelled': '❌',
    'failed': '⚠️',
  };

  static String? _statusLabel(L10n l10n, String status) {
    switch (status) {
      case 'pending':
        return l10n.miniAppStatusPending;
      case 'paid':
        return l10n.miniAppStatusPaid;
      case 'processing':
        return l10n.miniAppStatusProcessing;
      case 'shipped':
        return l10n.miniAppStatusShipped;
      case 'delivered':
        return l10n.miniAppStatusDelivered;
      case 'cancelled':
        return l10n.miniAppStatusCancelled;
      case 'failed':
        return l10n.miniAppStatusFailed;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final data = event.content.tryGetMap<String, Object?>('data');

    // Управляющие сигналы (например `kind: "miniapp_created"` из страницы
    // подключения) приходят тем же msgtype com.liza.miniapp.data, но это НЕ
    // карточка заказа — без полей заказа рендерить нечего, иначе показывался бы
    // пустой «🛒 Заказ / ⏳ Ожидает оплату».
    if (data == null ||
        (data['order_id'] == null &&
            data['items'] == null &&
            data['total'] == null)) {
      return const SizedBox.shrink();
    }

    final orderId = data['order_id'];
    final status = (data['status'] as String?) ?? 'pending';
    final total = data['total'];
    final items = data['items'];
    final trackingNumber = data['tracking_number'] as String?;

    final statusIcon = _statusIcons[status] ?? 'ℹ️';
    final statusLabel = _statusLabel(l10n, status) ?? status;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Заголовок заказа
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(
                children: [
                  Text(
                    '🛒',
                    style: TextStyle(fontSize: 18, color: textColor),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      orderId != null
                          ? l10n.miniAppOrderNumber('$orderId')
                          : l10n.miniAppOrder,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: textColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Товары
            if (items is List && items.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Divider(height: 1),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  children: [
                    for (final item in items)
                      if (item is Map)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  (item['name'] as String?) ?? '',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: textColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (item['qty'] != null)
                                Text(
                                  '  x${item['qty']}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: textColor.withAlpha(153),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              Text(
                                _formatPrice(item['price']),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: textColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ],

            // Итого + статус
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Divider(height: 1),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                children: [
                  if (total != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n.miniAppOrderTotal,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        Text(
                          _formatPrice(total),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '$statusIcon $statusLabel',
                        style: TextStyle(
                          fontSize: 13,
                          color: textColor.withAlpha(178),
                        ),
                      ),
                      if (trackingNumber != null) ...[
                        const Spacer(),
                        Text(
                          trackingNumber,
                          style: TextStyle(
                            fontSize: 12,
                            color: textColor.withAlpha(153),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatPrice(Object? price) {
    if (price == null) return '';
    final num = double.tryParse(price.toString());
    if (num == null) return price.toString();
    // Форматируем с разделителем тысяч и символом рубля
    final formatted = num
        .toStringAsFixed(num.truncateToDouble() == num ? 0 : 2)
        .replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]} ',
        );
    return '$formatted ₽';
  }
}
