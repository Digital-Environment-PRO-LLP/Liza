import 'package:flutter/material.dart';

import 'package:flutter_linkify/flutter_linkify.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/url_launcher.dart';
import 'package:liza/widgets/adaptive_dialogs/adaptive_dialog_action.dart';
import 'package:liza/widgets/adaptive_dialogs/dialog_text_field.dart';

Future<String?> showTextInputDialog({
  required BuildContext context,
  required String title,
  String? message,
  String? okLabel,
  String? cancelLabel,
  bool useRootNavigator = true,
  String? hintText,
  String? labelText,
  String? initialText,
  String? prefixText,
  String? suffixText,
  bool obscureText = false,
  bool isDestructive = false,
  int? minLines,
  int? maxLines,
  String? Function(String input)? validator,
  TextInputType? keyboardType,
  int? maxLength,
  bool autocorrect = true,
}) {
  return showAdaptiveDialog<String>(
    context: context,
    useRootNavigator: useRootNavigator,
    builder: (context) => _TextInputDialog(
      title: title,
      message: message,
      okLabel: okLabel,
      cancelLabel: cancelLabel,
      hintText: hintText,
      labelText: labelText,
      initialText: initialText,
      prefixText: prefixText,
      suffixText: suffixText,
      obscureText: obscureText,
      isDestructive: isDestructive,
      minLines: minLines,
      maxLines: maxLines,
      validator: validator,
      keyboardType: keyboardType,
      maxLength: maxLength,
    ),
  );
}

/// Тело диалога вынесено в State ради жизненного цикла [TextEditingController]
/// и нотифаера ошибки: раньше оба создавались функцией и не освобождались
/// НИКОГДА (утечка на каждый из 20 вызовов обёртки). Освобождать их по
/// завершению future нельзя — маршрут ещё доигрывает анимацию закрытия и
/// строит поле, получая «controller used after being disposed».
class _TextInputDialog extends StatefulWidget {
  final String title;
  final String? message;
  final String? okLabel;
  final String? cancelLabel;
  final String? hintText;
  final String? labelText;
  final String? initialText;
  final String? prefixText;
  final String? suffixText;
  final bool obscureText;
  final bool isDestructive;
  final int? minLines;
  final int? maxLines;
  final String? Function(String input)? validator;
  final TextInputType? keyboardType;
  final int? maxLength;

  const _TextInputDialog({
    required this.title,
    required this.message,
    required this.okLabel,
    required this.cancelLabel,
    required this.hintText,
    required this.labelText,
    required this.initialText,
    required this.prefixText,
    required this.suffixText,
    required this.obscureText,
    required this.isDestructive,
    required this.minLines,
    required this.maxLines,
    required this.validator,
    required this.keyboardType,
    required this.maxLength,
  });

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController controller = TextEditingController(
    text: widget.initialText,
  );
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);

  @override
  void initState() {
    super.initState();
    // Ошибка ставится только по «Ок» и обязана гаснуть при правке ввода: иначе
    // «Введите название» висит красным под уже заполненным полем (LABA-2535).
    // Для вызовов без validator слушатель — no-op: error всегда null.
    controller.addListener(_clearError);
  }

  void _clearError() {
    if (error.value != null) error.value = null;
  }

  @override
  void dispose() {
    controller.dispose();
    error.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final message = widget.message;
    final okLabel = widget.okLabel;
    final cancelLabel = widget.cancelLabel;
    final hintText = widget.hintText;
    final labelText = widget.labelText;
    final initialText = widget.initialText;
    final prefixText = widget.prefixText;
    final suffixText = widget.suffixText;
    final obscureText = widget.obscureText;
    final isDestructive = widget.isDestructive;
    final minLines = widget.minLines;
    final maxLines = widget.maxLines;
    final validator = widget.validator;
    final keyboardType = widget.keyboardType;
    final maxLength = widget.maxLength;
    return AlertDialog.adaptive(
      title: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 256),
        child: Text(title),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 256),
        child: Column(
          mainAxisSize: .min,
          children: [
            if (message != null)
              SelectableLinkify(
                text: message,
                textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
                linkStyle: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  decorationColor: Theme.of(context).colorScheme.primary,
                ),
                options: const LinkifyOptions(humanize: false),
                onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
              ),
            const SizedBox(height: 16),
            ValueListenableBuilder<String?>(
              valueListenable: error,
              builder: (context, error, _) {
                return DialogTextField(
                  hintText: hintText,
                  errorText: error,
                  labelText: labelText,
                  controller: controller,
                  initialText: initialText,
                  prefixText: prefixText,
                  suffixText: suffixText,
                  minLines: minLines,
                  maxLines: maxLines,
                  maxLength: maxLength,
                  keyboardType: keyboardType,
                  obscureText: obscureText,
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        AdaptiveDialogAction(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(cancelLabel ?? L10n.of(context).cancel),
        ),
        AdaptiveDialogAction(
          onPressed: () {
            final input = controller.text;
            final errorText = validator?.call(input);
            if (errorText != null) {
              error.value = errorText;
              return;
            }
            Navigator.of(context).pop<String>(input);
          },
          autofocus: true,
          child: Text(
            okLabel ?? L10n.of(context).ok,
            style: isDestructive
                ? TextStyle(color: Theme.of(context).colorScheme.error)
                : null,
          ),
        ),
      ],
    );
  }
}
