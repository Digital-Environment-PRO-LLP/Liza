import 'package:flutter/material.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/formatting_text_controller.dart';
import 'package:liza/widgets/adaptive_dialogs/show_text_input_dialog.dart';

Widget markdownContextBuilder(
  BuildContext context,
  EditableTextState editableTextState,
  TextEditingController controller, {
  VoidCallback? onPasteImage,
}) {
  final value = editableTextState.textEditingValue;
  final selectedText = value.selection.textInside(value.text);
  final buttonItems = editableTextState.contextMenuButtonItems
      .where((item) => item.type != ContextMenuButtonType.liveTextInput)
      .toList();
  final l10n = L10n.of(context);

  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: [
      ...buttonItems,
      if (onPasteImage != null)
        ContextMenuButtonItem(
          label: l10n.sendImage,
          onPressed: () {
            ContextMenuController.removeAny();
            onPasteImage();
          },
        ),
      if (selectedText.isNotEmpty) ...[
        ContextMenuButtonItem(
          label: l10n.link,
          onPressed: () async {
            final input = await showTextInputDialog(
              context: context,
              title: l10n.addLink,
              okLabel: l10n.ok,
              cancelLabel: l10n.cancel,
              validator: (text) {
                if (text.isEmpty) {
                  return l10n.pleaseFillOut;
                }
                try {
                  text.startsWith('http') ? Uri.parse(text) : Uri.https(text);
                } catch (_) {
                  return l10n.invalidUrl;
                }
                return null;
              },
              hintText: 'www...',
              keyboardType: TextInputType.url,
            );
            final urlString = input;
            if (urlString == null) return;
            final url = urlString.startsWith('http')
                ? Uri.parse(urlString)
                : Uri.https(urlString);
            final selection = controller.selection;
            controller.text = controller.text.replaceRange(
              selection.start,
              selection.end,
              '[$selectedText](${url.toString()})',
            );
            ContextMenuController.removeAny();
          },
        ),
        ContextMenuButtonItem(
          label: l10n.checkList,
          onPressed: () {
            final text = controller.text;
            final selection = controller.selection;

            var start = selection.textBefore(text).lastIndexOf('\n');
            if (start == -1) start = 0;
            final end = selection.end;

            final fullLineSelection = TextSelection(
              baseOffset: start,
              extentOffset: end,
            );

            const checkBox = '- [ ]';

            final replacedRange = fullLineSelection
                .textInside(text)
                .split('\n')
                .map(
                  (line) => line.startsWith(checkBox) || line.isEmpty
                      ? line
                      : '$checkBox $line',
                )
                .join('\n');
            controller.text = controller.text.replaceRange(
              start,
              end,
              replacedRange,
            );
            ContextMenuController.removeAny();
          },
        ),
        // Форматирование через боковой канал спанов (кандидат A). Символы
        // markdown в текст НЕ вставляем — тоглим формат на выделении, поэтому
        // formatted_body строится на отправке, а набранные вручную `* _ ~`
        // остаются буквальными (parseMarkdown:false не трогаем).
        if (controller is FormattingTextEditingController) ...[
          _formatButton(l10n.boldText, MessageFormat.bold, controller),
          _formatButton(l10n.italicText, MessageFormat.italic, controller),
          _formatButton(l10n.underline, MessageFormat.underline, controller),
          _formatButton(l10n.strikeThrough, MessageFormat.strikethrough, controller),
          _formatButton(l10n.monospace, MessageFormat.monospace, controller),
          _formatButton(l10n.spoiler, MessageFormat.spoiler, controller),
        ],
      ],
    ],
  );
}

ContextMenuButtonItem _formatButton(
  String label,
  MessageFormat format,
  FormattingTextEditingController controller,
) => ContextMenuButtonItem(
  label: label,
  onPressed: () {
    controller.toggleFormat(format);
    ContextMenuController.removeAny();
  },
);
