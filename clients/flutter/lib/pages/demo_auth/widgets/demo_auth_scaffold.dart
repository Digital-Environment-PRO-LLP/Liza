import 'package:flutter/material.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/demo_auth/widgets/support_dialog.dart';

/// Коды ошибок, из которых повторная попытка бессмысленна — вместо текста
/// показываем прямой выход в поддержку.
///
/// `resend_limit_reached` сюда не входит: на шагах sms/email под него уже
/// есть своя кнопка вместо таймера («_resendArea»), дублировать не нужно.
const deadEndErrorCodes = {
  'otp_attempts_exhausted',
  // Сбой SMS-провайдера. `otp_send_failed` приходит из `/phone/start`, когда
  // bypass выключен (прод-подобная конфигурация) — это основной сценарий
  // «код не дошёл не по вине человека». `otp_delivery_failed` возникает
  // только на `/phone/verify` при включённом bypass.
  'otp_send_failed',
  'otp_delivery_failed',
  'email_send_failed',
  // Keycloak отверг карточку при регистрации (`/complete` → 422). Код уже
  // подтверждён и сожжён, а причина — в самом номере/данных: ни повтор кода,
  // ни другой канал не помогут. Выход — назад и другой номер либо поддержка
  // (LABA-2527).
  'registration_rejected',
  'network_error',
  'internal_error',
};

/// Общий каркас экранов демо-флоу: стрелка назад, заголовок, подпись и
/// постоянная ссылка в поддержку внизу экрана.
///
/// Иконки «?» в AppBar больше нет: выход в поддержку продублирован явной
/// кнопкой под содержимым и кнопкой под полем кода, а тупиковые ошибки
/// (`deadEndErrorCodes`) по-прежнему показывают её прямо под текстом.
class DemoAuthScaffold extends StatelessWidget {
  const DemoAuthScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.subtitleIsWarning = false,
    this.subtitleDetail,
    this.icon,
    this.onBack,
    this.error,
    this.errorCode,
    this.ticket,
    this.step,
    this.showBottomSupport = true,
  });

  final String title;
  final String? subtitle;

  /// Подзаголовок несёт СБОЙ, а не подсказку (код не отправлен). Рисуем
  /// цветом ошибки и со знаком внимания: обычным текстом такое сообщение
  /// теряется среди инструкций и выглядит как норма.
  final bool subtitleIsWarning;

  /// Техническое пояснение под сообщением (ответ внешнего сервиса).
  /// Мелким шрифтом: конкретнее нашей формулировки, но человеку без
  /// контекста непонятно — потому вторым планом, а не вместо.
  final String? subtitleDetail;

  final Widget? icon;
  final Widget child;
  final VoidCallback? onBack;
  final String? error;

  /// Код последней ошибки от сервера — определяет, тупиковая ли она.
  final String? errorCode;

  /// Тикет и шаг текущего флоу — передаются в форму поддержки, чтобы
  /// обращение было привязано к конкретной попытке входа.
  final String? ticket;
  final String? step;

  /// Рисовать ли постоянную кнопку поддержки внизу. Экраны кода ставят
  /// `false`: они дают тот же выход в `OtpActionsRow` под полем, и две
  /// одинаковые кнопки подряд читаются как ошибка вёрстки.
  final bool showBottomSupport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final isDeadEnd =
        errorCode != null && deadEndErrorCodes.contains(errorCode);

    return Scaffold(
      appBar: AppBar(
        leading: onBack == null
            ? null
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (icon != null) ...[
                    Center(child: icon!),
                    const SizedBox(height: 24),
                  ],
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 12),
                    if (subtitleIsWarning)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 18,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              subtitle!,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        subtitle!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (subtitleDetail != null &&
                        subtitleDetail!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitleDetail!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 32),
                  child,
                  if (error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      error!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                    if (isDeadEnd) ...[
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.support_agent),
                        label: Text(l10n.supportContactButton),
                        onPressed: () => showSupportDialog(
                          context,
                          ticket: ticket,
                          step: step,
                          errorCode: errorCode,
                        ),
                      ),
                    ],
                  ],
                  // Постоянный выход в поддержку внизу экрана: тупиковая
                  // кнопка выше появляется только на ошибках, а человек
                  // застревает и без них (код не приходит, номер не тот).
                  // На экранах кода его уже даёт OtpActionsRow — там флаг
                  // выключен, иначе кнопка дублируется встык.
                  if (showBottomSupport) ...[
                    const SizedBox(height: 32),
                    Center(
                      child: TextButton.icon(
                        icon: const Icon(Icons.support_agent, size: 18),
                        label: Text(l10n.supportContactButton),
                        onPressed: () => showSupportDialog(
                          context,
                          ticket: ticket,
                          step: step,
                          errorCode: errorCode,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
