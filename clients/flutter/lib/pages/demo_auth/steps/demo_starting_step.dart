import 'package:flutter/material.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/demo_auth/demo_auth_flow.dart';
import 'package:liza/pages/demo_auth/widgets/demo_auth_scaffold.dart';

/// Ожидание ответа `/phone/start`: код ещё заказывается, канал неизвестен.
///
/// Канал доставки выбирает сервер, и до его ответа нельзя честно написать ни
/// «Код из СМС», ни «Код из письма». Раньше флоу по умолчанию рисовал экран
/// СМС и перерисовывал его в письмо, когда приходил `channel: email`, —
/// человек видел мигание чужого экрана. Здесь нейтральный текст без канала.
///
/// Каркас тот же ([DemoAuthScaffold]) и с иконкой того же размера, что на
/// экранах кода: так смена шага не сдвигает вёрстку.
class DemoAuthStartingStep extends StatelessWidget {
  const DemoAuthStartingStep({
    super.key,
    this.controller,
    this.error,
    this.errorCode,
  });

  /// `null` — только в тестах вёрстки: живой контроллер тянет за собой
  /// Matrix-клиент и сеть, а этому шагу от него нужны лишь «назад» и тикет.
  final DemoAuthFlowController? controller;

  /// Отказ запроса `/phone/start` в обход контроллера — только для тестов:
  /// поднимать ради состояния ошибки живой контроллер (а с ним Matrix и
  /// сеть) незачем, а проверять состояние надо на ЭТОМ виджете, а не на
  /// его реплике из `DemoAuthScaffold`.
  final String? error;
  final String? errorCode;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    // Запрос не удался — код не заказан, и ждать больше нечего. Показываем
    // отказ здесь же: перевод на экран ввода кода означал бы, что код
    // отправлен, хотя его не отправляли (LABA-2531).
    final error = this.error ?? controller?.error;
    final hasError = error != null;

    return DemoAuthScaffold(
      title: l10n.demoAuthStartingTitle,
      subtitle: hasError ? null : l10n.demoAuthStartingHint,
      icon: hasError
          ? const Icon(Icons.error_outline, size: 56)
          : const SizedBox(
              width: 56,
              height: 56,
              child: Center(child: CircularProgressIndicator()),
            ),
      onBack: controller?.back,
      error: error,
      errorCode: errorCode ?? controller?.errorCode,
      ticket: controller?.ticket,
      step: 'starting',
      // Пока запрос идёт, жаловаться не на что — выход в поддержку появляется
      // только вместе с ошибкой.
      showBottomSupport: hasError,
      child: const SizedBox.shrink(),
    );
  }
}
