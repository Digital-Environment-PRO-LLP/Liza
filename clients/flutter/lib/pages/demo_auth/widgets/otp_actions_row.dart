import 'package:flutter/material.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/demo_auth/demo_auth_flow.dart';
import 'package:liza/pages/demo_auth/widgets/support_dialog.dart';
import 'package:liza/widgets/adaptive_dialogs/show_modal_action_popup.dart';

/// Ряд кнопок под полем кода: «Другой способ» и «Написать в поддержку».
///
/// Второстепенный ряд: он стоит ПОД текстом таймера («Отправить повторно
/// через N с»), и тот важнее — по нему человек понимает, когда сможет
/// действовать. Поэтому кнопки здесь мельче и приглушённее обычных
/// [TextButton.icon]: иерархия задаётся сверху вниз, а не размером кегля
/// по умолчанию.
///
/// «Другой способ» показывается ТОЛЬКО когда есть из чего выбирать —
/// при входе (не регистрации) и при подтверждённых телефоне и почте
/// одновременно. Иначе кнопка предлагала бы канал, которого у человека нет.
class OtpActionsRow extends StatelessWidget {
  const OtpActionsRow({
    super.key,
    required this.step,
    this.ticket,
    this.errorCode,
    this.channels = const [],
    this.currentChannel,
    this.onSelectChannel,
  });

  /// Шаг флоу — уходит в обращение поддержки вместе с тикетом.
  final String step;
  final String? ticket;
  final String? errorCode;

  /// Способы доставки для меню. Пустой список — выбирать не из чего,
  /// кнопка не рисуется.
  final List<DemoAuthChannel> channels;

  /// Канал, которым код доставляется сейчас, — в меню помечается активным.
  final DemoAuthChannel? currentChannel;

  /// `null` — альтернативного канала нет, кнопка не рисуется.
  final ValueChanged<DemoAuthChannel>? onSelectChannel;

  /// Меню выбора способа — штатный [showModalActionPopup]: он сам разводит
  /// bottom sheet на Android и action sheet на iOS.
  ///
  /// Плоского переключателя здесь больше нет: он молча слал код по «другому»
  /// каналу, и при третьем способе выбирать было бы не из чего. Отправка
  /// уходит только по клику на КОНКРЕТНЫЙ пункт.
  Future<void> _pickChannel(BuildContext context) async {
    final l10n = L10n.of(context);
    final onSelectChannel = this.onSelectChannel;
    if (onSelectChannel == null) return;

    final picked = await showModalActionPopup<DemoAuthChannel>(
      context: context,
      title: l10n.demoAuthChannelPickerTitle,
      cancelLabel: l10n.cancel,
      actions: [
        for (final channel in channels)
          AdaptiveModalAction(
            value: channel,
            label: channel == currentChannel
                ? l10n.demoAuthChannelCurrent(_labelOf(channel, l10n))
                : _labelOf(channel, l10n),
            icon: Icon(_iconOf(channel)),
            isDefaultAction: channel == currentChannel,
          ),
      ],
    );
    if (picked == null) return;
    onSelectChannel(picked);
  }

  static String _labelOf(DemoAuthChannel channel, L10n l10n) =>
      switch (channel) {
        DemoAuthChannel.phone => l10n.demoAuthChannelPhone,
        DemoAuthChannel.email => l10n.demoAuthChannelEmail,
        DemoAuthChannel.password => l10n.demoAuthPasswordLabel,
      };

  static IconData _iconOf(DemoAuthChannel channel) => switch (channel) {
        DemoAuthChannel.phone => Icons.sms_outlined,
        DemoAuthChannel.email => Icons.mail_outline,
        DemoAuthChannel.password => Icons.lock_outline,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    // Приглушённый цвет и кегль мельче bodySmall: ряд обязан читаться
    // легче текста таймера над ним. Цвета — из темы, иначе в тёмной теме
    // кнопки пропали бы.
    final buttonStyle = TextButton.styleFrom(
      foregroundColor: theme.colorScheme.onSurfaceVariant,
      textStyle: theme.textTheme.labelMedium,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      minimumSize: const Size(0, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    const iconSize = 15.0;

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      children: [
        if (onSelectChannel != null && channels.isNotEmpty)
          TextButton.icon(
            style: buttonStyle,
            icon: const Icon(Icons.swap_horiz, size: iconSize),
            label: Text(l10n.demoAuthOtherChannel),
            onPressed: () => _pickChannel(context),
          ),
        TextButton.icon(
          style: buttonStyle,
          icon: const Icon(Icons.support_agent, size: iconSize),
          label: Text(l10n.supportContactButton),
          onPressed: () => showSupportDialog(
            context,
            ticket: ticket,
            step: step,
            errorCode: errorCode,
          ),
        ),
      ],
    );
  }
}
