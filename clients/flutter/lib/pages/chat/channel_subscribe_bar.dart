import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/wait_for_room_in_sync.dart';

/// Кнопка «Подписаться» внизу экрана канала — вместо композера для читателя,
/// который на канал не подписан (Liza-модель).
///
/// `_busy`-состояние структурно как в `company_subscribe_banner.dart`, но там
/// после `joinRoom` сразу `setState` без ожидания sync — здесь ждём явно
/// (через `waitForRoomInSync`), чтобы `onSubscribed()` вызывался с уже
/// видимой клиенту комнатой.
class ChannelSubscribeBar extends StatefulWidget {
  const ChannelSubscribeBar({
    super.key,
    required this.roomId,
    required this.client,
    required this.onSubscribed,
  });

  final String roomId;
  final Client client;
  final VoidCallback onSubscribed;

  @override
  State<ChannelSubscribeBar> createState() => _ChannelSubscribeBarState();
}

class _ChannelSubscribeBarState extends State<ChannelSubscribeBar> {
  bool _busy = false;

  Future<void> _subscribe() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.client.joinRoom(widget.roomId);
      // Утилита проекта, а НЕ Client.waitForRoomInSync из пакета matrix:
      // тот вариант без таймаута ждёт onSync.stream.firstWhere(...) и
      // виснет навечно при гонке (join уже попал в sync-батч, обработанный
      // ДО подписки на стрим). Возвращает false по таймауту (5 с) — это не
      // отказ join, а «не успели», поэтому подписку всё равно считаем
      // состоявшейся: экран сам перестроится, когда комната доедет позже.
      await waitForRoomInSync(widget.client, widget.roomId);
      if (!mounted) return;
      widget.onSubscribed();
    } catch (e, s) {
      Logs().w('ChannelSubscribeBar: подписка не удалась', e, s);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _subscribe,
            child: _busy
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.onPrimary,
                    ),
                  )
                : Text(L10n.of(context).channelSubscribe),
          ),
        ),
      ),
    );
  }
}
