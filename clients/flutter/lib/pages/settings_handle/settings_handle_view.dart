import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/settings_handle/settings_handle.dart';

class SettingsHandleView extends StatefulWidget {
  const SettingsHandleView(this.controller, {super.key});

  final SettingsHandleController controller;

  @override
  State<SettingsHandleView> createState() => _SettingsHandleViewState();
}

class _SettingsHandleViewState extends State<SettingsHandleView> {
  late final TextEditingController _field = TextEditingController(
    text: widget.controller.handle ?? widget.controller.suggestion ?? '',
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SettingsHandleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Значение поля обновляем из контроллера только когда сам текст ещё
    // пуст — иначе перерисовка после каждой setState стирала бы ввод
    // пользователя.
    final next = widget.controller.handle ?? widget.controller.suggestion;
    if (_field.text.isEmpty && next != null) {
      _field.text = next;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final controller = widget.controller;
    final hasSavedHandle = controller.handle != null;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(l10n.handleSettingsTitle),
      ),
      body: ListTileTheme(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (controller.isLoading)
              const LinearProgressIndicator()
            else ...[
              TextField(
                controller: _field,
                enabled: !controller.isSaving,
                // Ник — не слово языка и не логин: подсказки браузера и
                // автокоррекция тут только мешают.
                autocorrect: false,
                enableSuggestions: false,
                // Собачка — ДЕКОРАТИВНЫЙ prefixText, в значение поля она не
                // входит. Но человек, видя «@» слева, печатает её сам —
                // и ник «@asdasd» не проходит валидацию («начиная с буквы»),
                // хотя выглядит правильным. Фильтр не пускает в поле ничего
                // лишнего: ни «@», ни кириллицу, ни пробелы.
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
                  LengthLimitingTextInputFormatter(32),
                ],
                decoration: InputDecoration(
                  prefixText: '@',
                  labelText: l10n.handleFieldLabel,
                  helperText: l10n.handleHint,
                  border: const OutlineInputBorder(),
                ),
                // Причина отказа относится к ПРЕДЫДУЩЕМУ значению: как только
                // человек начал править имя, старый текст («имя занято»)
                // перестаёт быть правдой и обязан исчезнуть.
                onChanged: (_) => setState(controller.clearError),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.handleRulesHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                // Дизейбл ТОЛЬКО по состояниям, при которых отправка заведомо
                // бессмысленна (идёт сохранение, пустое поле, фича выключена
                // на сервере). По невалидности формата кнопку НЕ гасим: тогда
                // пришлось бы валидировать сырой текст поля на каждый ввод, а
                // автозаполненный браузером MXID `@name:server` сырым выглядит
                // невалидным, хотя после санитайза сохраняется успешно.
                onPressed: controller.isSaving ||
                        !controller.available ||
                        _field.text.trim().isEmpty
                    ? null
                    : () => controller.save(_field.text.trim()),
                child: Text(l10n.settingsEmailChange),
              ),
              if (controller.saved) ...[
                const SizedBox(height: 16),
                Text(
                  l10n.handleSaved,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
              if (!hasSavedHandle && controller.suggestion != null) ...[
                const SizedBox(height: 8),
                Text(
                  '@${controller.suggestion}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
            if (controller.errorText != null) ...[
              const SizedBox(height: 16),
              Text(
                controller.errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
