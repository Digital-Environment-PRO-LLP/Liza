import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:liza/config/app_config.dart';
import 'package:liza/config/setting_keys.dart';
import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/forced_list_artifact.dart';
import 'package:liza/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:liza/utils/message_link.dart';

/// Карточка-превью ссылки на сообщение (аналог Liza message-link preview).
/// Резолвит комнату и событие локально и показывает имя чата + фрагмент текста.
/// Используется в двух местах:
///   * в композере при вставке ссылки (с крестиком — снаружи, в ReplyDisplay);
///   * в пузыре у получателя, когда тело сообщения — голая ссылка ([onTap]).
class MessageLinkPreview extends StatefulWidget {
  final MessageLink link;
  final Client client;
  final VoidCallback? onTap;

  const MessageLinkPreview({
    required this.link,
    required this.client,
    this.onTap,
    super.key,
  });

  @override
  State<MessageLinkPreview> createState() => _MessageLinkPreviewState();
}

class _MessageLinkPreviewState extends State<MessageLinkPreview> {
  Room? _room;
  late Future<Event?> _eventFuture;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant MessageLinkPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.link != widget.link) _resolve();
  }

  void _resolve() {
    _room = widget.client.getRoomById(widget.link.roomId);
    _eventFuture =
        _room?.getEventById(widget.link.eventId).catchError((_) => null) ??
        Future<Event?>.value();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fontSize =
        AppConfig.messageFontSize * AppSettings.fontSizeFactor.value;
    final color = theme.colorScheme.primary;
    final title = _room?.getLocalizedDisplayname() ??
        L10n.of(context).chat;

    final card = Material(
      color: Colors.transparent,
      child: Row(
        mainAxisSize: .min,
        children: <Widget>[
          Container(
            width: 5,
            height: fontSize * 2 + 16,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppConfig.borderRadius),
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: .start,
              mainAxisAlignment: .center,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: fontSize,
                  ),
                ),
                FutureBuilder<Event?>(
                  future: _eventFuture,
                  builder: (context, snapshot) {
                    final event = snapshot.data;
                    final snippet = event != null
                        ? event.calcLocalizedBodyFallback(
                            MatrixLocals(L10n.of(context)),
                            withSenderNamePrefix: true,
                            hideReply: true,
                            plaintextBody: !event.isForcedListArtifactBody,
                          )
                        : snapshot.connectionState == ConnectionState.done
                        ? ''
                        : '…';
                    if (snippet.isEmpty) return const SizedBox.shrink();
                    return Text(
                      snippet,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: fontSize,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );

    final onTap = widget.onTap;
    if (onTap == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
      onTap: onTap,
      child: card,
    );
  }
}
