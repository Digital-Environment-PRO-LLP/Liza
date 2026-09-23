import 'package:flutter/material.dart';

/// Оборачивает [child] в [SelectionArea] только когда выделение разрешено.
///
/// В защищённом канале (`Room.isContentProtected`) выделение текста мышью —
/// такой же путь выноса контента, как «Копировать» в меню: выделил → Ctrl+C
/// либо нативное контекстное меню «Copy». Поэтому при `selectable == false`
/// обёртка не создаётся вовсе, и выделять становится нечего.
Widget protectedSelectionArea({
  required bool selectable,
  required Widget child,
}) => selectable ? SelectionArea(child: child) : child;
