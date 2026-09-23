import 'dart:async';

import 'package:flutter/material.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/demo_auth/demo_auth_flow.dart';
import 'package:liza/pages/demo_auth/resend_countdown_format.dart';
import 'package:liza/pages/demo_auth/widgets/code_input.dart';
import 'package:liza/pages/demo_auth/widgets/demo_auth_scaffold.dart';
import 'package:liza/pages/demo_auth/widgets/otp_actions_row.dart';
import 'package:liza/pages/demo_auth/widgets/support_dialog.dart';

/// Шаг 4: код из письма.
///
/// Код заказывает auth-proxy у сервиса otpverification: штатных ручек
/// «отправь код на email + проверь» у Keycloak нет.
class DemoEmailCodeStep extends StatefulWidget {
  const DemoEmailCodeStep({super.key, required this.controller});

  final DemoAuthFlowController controller;

  @override
  State<DemoEmailCodeStep> createState() => _DemoEmailCodeStepState();
}

class _DemoEmailCodeStepState extends State<DemoEmailCodeStep> {
  /// Запасное значение — на случай, если сервер не прислал
  /// `resend_available_in` (старый auth-proxy).
  static const _resendDelaySeconds = 60;

  Timer? _timer;
  int _secondsLeft = 0;

  /// Эпоха серверного значения, по которой отсчёт уже запущен.
  int _seenEpoch = -1;

  @override
  void initState() {
    super.initState();
    _syncCountdown();
  }

  @override
  void didUpdateWidget(DemoEmailCodeStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Перезапуск отсчёта только по новому ответу сервера — та же эпоха, что
  /// у шага СМС (см. `_DemoSmsStepState._syncCountdown`).
  void _syncCountdown() {
    final controller = widget.controller;
    if (controller.resendEpoch == _seenEpoch) return;
    _seenEpoch = controller.resendEpoch;
    final fromServer = controller.resendAvailableIn;
    if (fromServer == null) {
      _startCountdown();
    } else if (fromServer > 0) {
      _startCountdown(fromServer);
    } else {
      _timer?.cancel();
      _secondsLeft = 0;
    }
  }

  /// Запускает отсчёт. Перерисовку НЕ дёргает сам: вызывается в том числе
  /// из initState, где setState запрещён — обновление приезжает либо
  /// первым build, либо ближайшим тиком таймера.
  void _startCountdown([int? seconds]) {
    _secondsLeft = seconds ?? _resendDelaySeconds;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _secondsLeft--;
        if (_secondsLeft <= 0) timer.cancel();
      });
    });
  }

  Future<void> _resend() => widget.controller.resendEmailCode();

  Widget _resendArea(L10n l10n, DemoAuthFlowController controller) {
    if (controller.errorCode == 'resend_limit_reached') {
      return ElevatedButton.icon(
        icon: const Icon(Icons.support_agent),
        label: Text(l10n.supportContactButton),
        onPressed: () => showSupportDialog(
          context,
          ticket: controller.ticket,
          step: 'email',
          errorCode: controller.errorCode,
        ),
      );
    }
    if (_secondsLeft > 0) {
      // Размер подзаголовка, а не bodySmall: пока идёт отсчёт, это главный
      // текст экрана после самого поля кода. Ряд кнопок ниже — мельче.
      return Text(
        l10n.demoAuthResendIn(formatResendCountdown(_secondsLeft)),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    // Тот же текст и та же иконка, что на экране кода из СМС: действие
    // одно, и называть его по-разному в зависимости от канала незачем.
    return TextButton.icon(
      onPressed: controller.isLoading ? null : _resend,
      icon: const Icon(Icons.refresh),
      label: Text(l10n.demoAuthResendAgain),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final controller = widget.controller;

    return DemoAuthScaffold(
      title: l10n.demoAuthEmailCodeTitle,
      subtitle: l10n.demoAuthEmailCodeHint(controller.maskedEmail ?? ''),
      icon: const Icon(Icons.mail_outline, size: 56),
      onBack: controller.back,
      error: controller.error,
      errorCode: controller.errorCode,
      ticket: controller.ticket,
      step: 'email',
      // Выход в поддержку даёт OtpActionsRow под полем кода —
      // нижняя кнопка каркаса стала бы вторым таким же рядом.
      showBottomSupport: false,
      child: Column(
        children: [
          CodeInput(
            length: 6,
            enabled: !controller.isLoading,
            onCompleted: controller.submitEmailCode,
          ),
          const SizedBox(height: 24),
          if (controller.isLoading)
            const CircularProgressIndicator()
          else
            _resendArea(l10n, controller),
          const SizedBox(height: 8),
          OtpActionsRow(
            step: 'email',
            ticket: controller.ticket,
            errorCode: controller.errorCode,
            channels: controller.availableChannels,
            currentChannel: controller.currentChannel,
            // Второй экран кода вообще существует только у входа с
            // подтверждённой почтой, но условие держим явным — оно должно
            // читаться на месте, а не выводиться из истории шагов.
            onSelectChannel: controller.canSwitchChannel
                ? controller.switchChannel
                : null,
          ),
        ],
      ),
    );
  }
}
