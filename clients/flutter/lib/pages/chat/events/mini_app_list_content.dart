import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/config/app_config.dart';
import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/string_color.dart';
import 'package:liza/widgets/matrix.dart';
import 'package:liza/widgets/mxc_image.dart';

/// Список подключённых mini App в стиле «My bots» Liza.
///
/// Рендерит сообщение с `msgtype: "com.liza.miniapp.list"` как компактный
/// список строк (иконка + название + описание + шеврон) на мягком
/// полупрозрачном фоне — без карточек. Новые сверху (порядок задаёт сервер).
/// Наверху опциональная строка «＋ Создать mini App».
///
/// Тап по строке отправляет `com.liza.miniapp.callback` (тот же контракт, что и
/// у [MiniAppChoiceContent]) с `action_button_id` строки — сервер отвечает
/// detail-карточкой. Msgtype аддитивен: launch-карточка не затрагивается.
class MiniAppListContent extends StatefulWidget {
  final Event event;
  final Color textColor;

  const MiniAppListContent({
    required this.event,
    required this.textColor,
    super.key,
  });

  /// msgtype списка mini App.
  static const String msgType = 'com.liza.miniapp.list';

  /// rel_type, которым callback связывается со списком.
  static const String answerRelType = 'com.liza.miniapp.answer';

  /// msgtype callback-события (клиент → комната).
  static const String callbackMsgType = 'com.liza.miniapp.callback';

  /// Максимум строк в одном списке — защита от гигантского виджета.
  static const int maxItems = 50;

  /// Разбирает поле `items` контента в строки списка. Чистая функция (без
  /// контекста/виджета) — пропускает записи без `action_button_id`/`title`,
  /// режет длинные значения, сохраняет порядок (сервер отдаёт новые сверху),
  /// ограничивает [maxItems]. Тестируется отдельно (mini_app_list_parse_test).
  static List<MiniAppListItem> parseItems(List<Object?>? raw) {
    if (raw == null) return const [];
    final result = <MiniAppListItem>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final buttonId = item['action_button_id'];
      final title = item['title'];
      if (buttonId is! String || buttonId.isEmpty) continue;
      if (title is! String || title.isEmpty) continue;
      final subtitle = item['subtitle'];
      final iconRaw = item['icon'];
      result.add(
        MiniAppListItem(
          itemId: (item['item_id'] as String?) ?? buttonId,
          title: title.length <= 96 ? title : title.substring(0, 96),
          subtitle: subtitle is String
              ? (subtitle.length <= 120 ? subtitle : subtitle.substring(0, 120))
              : '',
          buttonId: buttonId,
          icon: iconRaw is String ? Uri.tryParse(iconRaw) : null,
        ),
      );
      if (result.length >= maxItems) break;
    }
    return result;
  }

  @override
  State<MiniAppListContent> createState() => _MiniAppListContentState();
}

class MiniAppListItem {
  final String itemId;
  final String title;
  final String subtitle;
  final String buttonId;
  final Uri? icon;

  MiniAppListItem({
    required this.itemId,
    required this.title,
    required this.subtitle,
    required this.buttonId,
    this.icon,
  });
}

class _MiniAppListContentState extends State<MiniAppListContent> {
  /// button_id строки, по которой сейчас летит callback (гард от дабл-тапа).
  /// Транзиентный: список не «залипает» после выбора (в отличие от choice —
  /// пользователь может открывать разные приложения).
  String? _pending;

  /// Гард: роль отправителя дозагружаем не более одного раза на виджет.
  bool _roleFetchRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Список рисуется только для ai-отправителя (isAiUser в build). В group-комнате
    // роль отправителя в кэш не попадает → дозагружаем по факту незагрузки
    // (getRole == null), рендер перестроится по rolesVersion. См.
    // mini_app_choice_content.dart (тот же фикс).
    final service = Matrix.of(context).userRoleService;
    final senderId = widget.event.senderId;
    if (!_roleFetchRequested && service.getRole(senderId) == null) {
      _roleFetchRequested = true;
      service.refreshIfStale([senderId]);
    }
  }

  String get _title {
    final raw = widget.event.content.tryGet<String>('title');
    if (raw == null || raw.isEmpty) return L10n.of(context).miniAppListDefaultTitle;
    return raw.length <= 96 ? raw : raw.substring(0, 96);
  }

  String? get _text {
    final raw = widget.event.content.tryGet<String>('text');
    if (raw == null || raw.isEmpty) return null;
    return raw.length <= 256 ? raw : raw.substring(0, 256);
  }

  List<MiniAppListItem> get _items => MiniAppListContent.parseItems(
        widget.event.content.tryGetList<Object?>('items'),
      );

  String? get _createButtonId {
    final raw = widget.event.content.tryGet<String>('create_button_id');
    return (raw != null && raw.isNotEmpty) ? raw : null;
  }

  String get _createText {
    final raw = widget.event.content.tryGet<String>('create_text');
    if (raw != null && raw.isNotEmpty && raw.length <= 48) return raw;
    return L10n.of(context).botFatherCreateApp;
  }

  Future<void> _sendCallback(String buttonId, String label) async {
    if (_pending != null) return;
    final body = L10n.of(context).miniAppChoiceSelected(label);
    setState(() => _pending = buttonId);
    try {
      await widget.event.room.sendEvent({
        'msgtype': MiniAppListContent.callbackMsgType,
        'body': body,
        'button_id': buttonId,
        'm.relates_to': {
          'rel_type': MiniAppListContent.answerRelType,
          'event_id': widget.event.eventId,
        },
      });
    } catch (e) {
      Logs().e('[MiniAppList] callback failed: $e');
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Перестраиваемся по rolesVersion — кнопки/список появятся, как только роль
    // отправителя подгрузится (didChangeDependencies). См. mini_app_choice_content.
    return ValueListenableBuilder<int>(
      valueListenable: Matrix.of(context).userRoleService.rolesVersion,
      builder: (context, _, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final items = _items;
    final senderIsBot = Matrix.of(context).isAiUser(widget.event.senderId);

    // Интерактивный список рисуем только от бота (роль `ai`) и при наличии
    // строк. Иначе — текстовый fallback (body): его же видят старые клиенты,
    // не знающие msgtype.
    if (!senderIsBot || items.isEmpty) {
      final body = widget.event.body;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          body.isNotEmpty ? body : _title,
          style: TextStyle(
            color: widget.textColor,
            fontSize: 14,
            height: 1.35,
          ),
        ),
      );
    }

    // Liza-стиль: мягкий полупрозрачный тон (как пузырь бота в
    // mini_app_choice_content.dart) — без жёсткой карточки. Msgtype исключён
    // из пузыря чата в message.dart → noBubble.
    final panelColor = isDark
        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
        : Colors.white.withValues(alpha: 0.62);
    final titleColor = colorScheme.onSurface;
    final subtitleColor = colorScheme.onSurfaceVariant;

    final createId = _createButtonId;
    final rows = <Widget>[];
    if (createId != null) {
      rows.add(_buildCreateRow(colorScheme, createId));
      rows.add(_divider(colorScheme));
    }
    for (var i = 0; i < items.length; i++) {
      rows.add(_buildItemRow(items[i], titleColor, subtitleColor, colorScheme));
      if (i < items.length - 1) rows.add(_divider(colorScheme));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      height: 1.25,
                      color: titleColor,
                    ),
                  ),
                  if (_text != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _text!,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: subtitleColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppConfig.borderRadius),
              child: Material(
                color: panelColor,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: rows,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(ColorScheme colorScheme) => Divider(
        height: 1,
        thickness: 1,
        indent: 64,
        color: colorScheme.onSurface.withValues(alpha: 0.06),
      );

  Widget _buildItemRow(
    MiniAppListItem item,
    Color titleColor,
    Color subtitleColor,
    ColorScheme colorScheme,
  ) {
    final disabled = _pending != null;
    return InkWell(
      onTap: disabled ? null : () => _sendCallback(item.buttonId, item.title),
      splashColor: colorScheme.primary.withValues(alpha: 0.12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _avatar(item),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: subtitleColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (_pending == item.buttonId)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                )
              else
                Icon(
                  Icons.chevron_right,
                  size: 24,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatar(MiniAppListItem item) {
    if (item.icon != null) {
      return SizedBox(
        width: 40,
        height: 40,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: MxcImage(
            uri: item.icon,
            event: widget.event,
            fit: BoxFit.cover,
            width: 40,
            height: 40,
          ),
        ),
      );
    }
    final letter =
        item.title.isNotEmpty ? item.title.characters.first.toUpperCase() : '?';
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: item.title.lightColorAvatar,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        letter,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildCreateRow(ColorScheme colorScheme, String createId) {
    final disabled = _pending != null;
    return InkWell(
      onTap: disabled ? null : () => _sendCallback(createId, _createText),
      splashColor: colorScheme.primary.withValues(alpha: 0.12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  Icons.add_circle_outline,
                  size: 28,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _createText,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              if (_pending == createId)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                )
              else
                Icon(
                  Icons.chevron_right,
                  size: 24,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
