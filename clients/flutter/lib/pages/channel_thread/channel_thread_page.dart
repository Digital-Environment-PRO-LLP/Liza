import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/config/app_config.dart';
import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/events/message_content.dart';
import 'package:liza/pages/chat/events/message.dart';
import 'package:liza/pages/chat/events/message_reactions.dart';
import 'package:liza/utils/channel_discussion.dart';
import 'package:liza/utils/chat_topology.dart';
import 'package:liza/utils/date_time_extension.dart';
import 'package:liza/utils/room_status_extension.dart';
import 'package:liza/utils/secure_screen.dart';
import 'package:liza/widgets/avatar.dart';
import 'package:liza/widgets/matrix.dart';

/// Потолок итераций подгрузки истории обсуждения.
///
/// Окно загрузки — это окно ВСЕГО привязанного чата, а не треда: в активном
/// обсуждении зеркало старого поста в первую порцию не попадает, и его
/// приходится догонять порциями назад. Потолок обязателен: без него на
/// «болтливом» чате (тысячи сообщений между постом и хвостом) цикл
/// подгрузки не закончится — экран будет вечно грузиться, а трафик расти.
/// Не нашли зеркало за [_maxHistoryBatches] порций — показываем пустой тред,
/// а не ошибку: комментариев к посту, скорее всего, просто нет.
const int _maxHistoryBatches = 3;

/// Размер порции истории обсуждения.
const int _historyBatchSize = 100;

/// Reply-фолбэк в плейн-`body`: ведущие строки-цитаты «> …» плюс пустая
/// строка — так его строит SDK при `inReplyTo`.
final _replyFallbackPrefix = RegExp(r'^(?:>[^\n]*\r?\n)+\r?\n?');

/// Экран треда комментариев к посту канала — как в Liza: закреплённая
/// сверху карточка поста, под ней плоский список комментариев, внизу поле
/// ввода.
///
/// Комментарий в модели данных — обычный reply (`m.in_reply_to`) на «зеркало»
/// поста в привязанном чате; зеркало создаёт сервер и помечает его
/// `com.liza.channel.post_ref`.
class ChannelThreadPage extends StatefulWidget {
  const ChannelThreadPage({
    required this.channelId,
    required this.postEventId,
    super.key,
  });

  /// room_id самого канала (не привязанного чата).
  final String channelId;

  /// event_id поста в канале, чей тред открыт.
  final String postEventId;

  @override
  State<ChannelThreadPage> createState() => _ChannelThreadPageState();
}

class _ChannelThreadPageState extends State<ChannelThreadPage> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// Таймлайн канала — нужен рендеру карточки поста (`MessageContent` и
  /// реакции без таймлайна не собрать).
  Timeline? _channelTimeline;

  /// Живой таймлайн обсуждения. Есть только у члена чата; не-член читает
  /// разовым peek'ом в [_peekedEvents].
  Timeline? _discussionTimeline;

  /// Снимок обсуждения для не-члена: peek через `/messages`. Мёртвый — после
  /// тихого join при отправке комментария заменяется живым таймлайном.
  List<Map<String, dynamic>> _peekedEvents = const [];

  Event? _post;
  bool _loading = true;
  bool _sending = false;

  /// Комментарий, на который сейчас отвечает пользователь (плашка над полем
  /// ввода). null — обычный комментарий к посту.
  Map<String, dynamic>? _replyTo;

  Room? get _channel => Matrix.of(context).client.getRoomById(widget.channelId);

  /// Кандидаты для @упоминания: участники обсуждения (если вступили) либо, в
  /// peek-режиме без членства, авторы уже загруженных комментариев. Возврат —
  /// пары (mxid, displayName) без дублей.
  List<({String id, String name})> get _mentionCandidates {
    final discussion = _channel?.discussionRoom;
    final byId = <String, String>{};
    if (discussion != null && discussion.membership == Membership.join) {
      for (final u in discussion.getParticipants()) {
        if (u.membership == Membership.join) byId[u.id] = u.calcDisplayname();
      }
    }
    // Авторы комментариев — на случай peek без членства (участников не спросить).
    for (final e in _discussionEvents) {
      final sender = e['sender'];
      if (sender is String && !byId.containsKey(sender)) {
        byId[sender] =
            discussion
                ?.unsafeGetUserFromMemoryOrFallback(sender)
                .calcDisplayname() ??
            sender;
      }
    }
    final me = Matrix.of(context).client.userID;
    return [
      for (final entry in byId.entries)
        if (entry.key != me) (id: entry.key, name: entry.value),
    ];
  }

  /// Имя автора комментария, на который отвечаем — для плашки над полем ввода.
  String? get _replyToName {
    final r = _replyTo;
    if (r == null) return null;
    final sender = r['sender'];
    if (sender is! String) return '';
    return _channel?.discussionRoom
            ?.unsafeGetUserFromMemoryOrFallback(sender)
            .calcDisplayname() ??
        sender;
  }

  void _startReply(Map<String, dynamic> comment) {
    setState(() => _replyTo = comment);
  }

  void _cancelReply() {
    setState(() => _replyTo = null);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _channelTimeline?.cancelSubscriptions();
    _discussionTimeline?.cancelSubscriptions();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Все события обсуждения в едином виде «content-map» — независимо от того,
  /// пришли они из живого таймлайна или из peek'а. На этом виде работают
  /// чистые функции отбора из `channel_discussion.dart`.
  List<Map<String, dynamic>> get _discussionEvents {
    final timeline = _discussionTimeline;
    if (timeline == null) return _peekedEvents;
    return [
      for (final e in timeline.events)
        // `sender` кладём наравне с content: по нему тред рисует автора
        // комментария (в чистых функциях отбора он не участвует).
        {'event_id': e.eventId, 'sender': e.senderId, 'content': e.content},
    ];
  }

  String? get _mirrorId =>
      findMirrorEventId(_discussionEvents, widget.postEventId);

  /// Комментарии в хронологическом порядке (снизу — самые новые).
  ///
  /// И живой таймлайн, и `/messages?dir=b` отдают события от новых к старым,
  /// поэтому список разворачиваем.
  ///
  /// Тред ПЛОСКИЙ, но двухуровневый по содержанию — отбор в [threadEvents].
  List<Map<String, dynamic>> get _comments {
    final mirrorId = _mirrorId;
    if (mirrorId == null) return const [];
    return threadEvents(_discussionEvents, mirrorId).reversed.toList();
  }

  /// Комментарий, на который отвечает [e] — для цитаты-заголовка.
  Map<String, dynamic>? _quotedComment(Map<String, dynamic> e) {
    final mirrorId = _mirrorId;
    if (mirrorId == null) return null;
    return quotedComment(_discussionEvents, e, mirrorId);
  }

  Future<void> _load() async {
    final channel = _channel;
    if (channel == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    // Ошибка загрузки не должна ломать экран: показываем что успели собрать.
    try {
      final timeline = await channel.getTimeline(onUpdate: _onUpdate);
      if (!mounted) {
        timeline.cancelSubscriptions();
        return;
      }
      setState(() => _channelTimeline = timeline);
      final post = await channel.getEventById(widget.postEventId);
      if (!mounted) return;
      setState(() => _post = post);
    } catch (e, s) {
      Logs().w('Тред: не удалось загрузить пост ${widget.postEventId}', e, s);
    }
    await _loadDiscussion();
    if (mounted) setState(() => _loading = false);
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  /// Загружает ленту обсуждения в одном из двух режимов — тем же приёмом, что
  /// `ChatController.reloadDiscussionEvents`: член чата получает живой
  /// таймлайн, не-член читает разовым peek'ом (у открытого канала чат
  /// `world_readable`).
  Future<void> _loadDiscussion() async {
    final channel = _channel;
    if (channel == null || !channel.hasComments) return;
    final discussion = channel.discussionRoom;
    if (discussion != null && discussion.membership == Membership.join) {
      if (_discussionTimeline != null) return;
      try {
        final timeline = await discussion.getTimeline(onUpdate: _onUpdate);
        if (!mounted) {
          timeline.cancelSubscriptions();
          return;
        }
        setState(() {
          _discussionTimeline?.cancelSubscriptions();
          _discussionTimeline = timeline;
        });
        await _requestMoreHistoryUntilMirror();
      } catch (e, s) {
        Logs().w('Тред: живой таймлайн обсуждения не поднялся', e, s);
      }
      return;
    }
    await _peekDiscussion();
  }

  /// Догоняет зеркало поста по живому таймлайну, порциями назад.
  Future<void> _requestMoreHistoryUntilMirror() async {
    final timeline = _discussionTimeline;
    if (timeline == null) return;
    var loadedBatches = 0;
    while (needsMoreHistory(
      events: _discussionEvents,
      postEventId: widget.postEventId,
      loadedBatches: loadedBatches,
      maxBatches: _maxHistoryBatches,
    )) {
      if (!timeline.canRequestHistory) return;
      try {
        await timeline.requestHistory(historyCount: _historyBatchSize);
      } catch (e, s) {
        Logs().w('Тред: подгрузка истории обсуждения не удалась', e, s);
        return;
      }
      if (!mounted) return;
      loadedBatches++;
    }
  }

  /// Peek для не-члена: читаем `/messages` порциями назад, пока не найдём
  /// зеркало поста или не упрёмся в потолок.
  Future<void> _peekDiscussion() async {
    final channel = _channel;
    final discussionId = channel?.discussionRoomId;
    if (channel == null || discussionId == null) return;
    final collected = <Map<String, dynamic>>[];
    String? from;
    var loadedBatches = 0;
    do {
      try {
        final response = await channel.client.getRoomEvents(
          discussionId,
          Direction.b,
          from: from,
          limit: _historyBatchSize,
        );
        collected.addAll(
          response.chunk.map(
            (e) => {
              'event_id': e.eventId,
              'sender': e.senderId,
              'content': e.content,
            },
          ),
        );
        from = response.end;
      } catch (e, s) {
        // Закрытый канал без инвайта — peek законно запрещён: показываем
        // пустой тред, а не ошибку.
        Logs().w('Тред: peek обсуждения $discussionId не удался', e, s);
        break;
      }
      if (!mounted) return;
      loadedBatches++;
      // Хвост чата исчерпан — дальше листать некуда.
      if (from == null) break;
    } while (needsMoreHistory(
      events: collected,
      postEventId: widget.postEventId,
      loadedBatches: loadedBatches,
      maxBatches: _maxHistoryBatches,
    ));
    if (!mounted) return;
    setState(() => _peekedEvents = collected);
  }

  /// Отправляет комментарий как reply на зеркало поста.
  ///
  /// Намеренно НЕ раскрывает чат в списке чатов (метод `revealChatForMe`
  /// здесь вызывать нельзя, и страж-тест это проверяет): тред — это режим
  /// «комментирую, не вступая», привязанный чат обязан остаться скрытым.
  /// Осознанный вход в чат есть только через кнопку «Обсуждение» в деталях
  /// канала. Добавить сюда раскрытие = сломать модель комментариев.
  Future<void> _send() async {
    final text = _inputController.text.trim();
    final channel = _channel;
    if (text.isEmpty || channel == null || _sending) return;
    setState(() => _sending = true);
    final failedText = L10n.of(context).channelDiscussionOpenFailed;
    final slowText = L10n.of(context).channelDiscussionOpenSlow;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final joinResult = await channel.ensureDiscussionMembershipResult();
      final discussion = joinResult.room;
      if (!joinResult.isJoined || discussion == null) {
        if (mounted) {
          // «join принят, комната не приехала в sync» — не «нет доступа»:
          // предлагаем повторить, а не сообщаем о запрете.
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                joinResult.outcome == DiscussionJoinOutcome.timedOut
                    ? slowText
                    : failedText,
              ),
            ),
          );
        }
        return;
      }
      // После тихого join мёртвый снимок peek'а надо заменить живым
      // таймлайном — иначе свежий комментарий в тред не попадёт.
      await _loadDiscussion();
      if (!mounted) return;
      final mirrorId = _mirrorId;
      if (mirrorId == null) {
        messenger.showSnackBar(SnackBar(content: Text(failedText)));
        return;
      }
      // Адресат ответа: обычный комментарий → зеркало; ответ на комментарий →
      // схлопнутый анкор (см. threadReplyAnchorId), чтобы остаться в плоском
      // 2-уровневом треде и не выпасть из счётчика.
      final replyTo = _replyTo;
      final anchorId = replyTo != null
          ? threadReplyAnchorId(replyTo, mirrorId)
          : mirrorId;
      final anchor =
          await discussion.getEventById(anchorId) ??
          await discussion.getEventById(mirrorId);
      if (!mounted) return;
      if (anchor == null) {
        messenger.showSnackBar(SnackBar(content: Text(failedText)));
        return;
      }
      await discussion.sendTextEvent(text, inReplyTo: anchor);
      if (!mounted) return;
      _inputController.clear();
      setState(() => _replyTo = null);
    } catch (e, s) {
      Logs().w('Тред: отправка комментария не удалась', e, s);
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(failedText)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _openFullDiscussion() {
    final discussionId = _channel?.discussionRoomId;
    if (discussionId == null) return;
    context.go('/rooms/${Uri.encodeComponent(discussionId)}');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final channel = _channel;
    final comments = _comments;
    // Тред открывается поверх ленты канала, но и по прямой ссылке тоже —
    // поэтому у него свой страж. Признак берём с САМОГО канала: карточка поста
    // сверху треда — это контент канала, и запрет должен на неё действовать
    // даже если привязанный чат обсуждения ничем не защищён.
    return SecureScreenGuard(
      enabled: channel?.isContentProtected ?? false,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.channelComments),
          actions: [
            if (channel?.hasComments ?? false)
              TextButton(
                onPressed: _openFullDiscussion,
                child: Text(l10n.channelOpenFullDiscussion),
              ),
          ],
        ),
        body: Column(
          children: [
            if (_post != null && _channelTimeline != null)
              _ThreadPostCard(post: _post!, timeline: _channelTimeline!),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator.adaptive())
                  : comments.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          l10n.channelThreadEmpty,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: comments.length,
                      itemBuilder: (context, i) => _CommentTile(
                        comment: comments[i],
                        room: channel?.discussionRoom,
                        quoted: _quotedComment(comments[i]),
                        onReply: () => _startReply(comments[i]),
                      ),
                    ),
            ),
            _ThreadComposer(
              controller: _inputController,
              sending: _sending,
              onSend: _send,
              replyToName: _replyToName,
              replyToBody: _replyTo == null
                  ? null
                  : _CommentTile._bodyOf(_replyTo!),
              onCancelReply: _cancelReply,
              mentionCandidates: _mentionCandidates,
            ),
          ],
        ),
      ),
    );
  }
}

/// Карточка поста, закреплённая сверху треда: сам контент поста плюс строка
/// статистики (реакции, просмотры, время) — тот же рендер, что в ленте.
class _ThreadPostCard extends StatelessWidget {
  const _ThreadPostCard({required this.post, required this.timeline});

  final Event post;
  final Timeline timeline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Статистика считается ровно так же, как в ленте (`Message` →
    // `ChannelPostFooter`): реакции — агрегаты события в таймлайне, просмотры
    // — число квитанций прочтения, севших на этот пост. Захардкоженные
    // `reactions: null, viewCount: 0` показывали бы «0 просмотров» и пустоту
    // на посте, у которого в ленте 40 реакций и 5000 просмотров.
    final hasReactions = post.hasAggregatedEvents(
      timeline,
      RelationshipTypes.reaction,
    );
    final viewCount =
        post.room.getReadReceiptsPerMessage(timeline)[post.eventId]?.length ??
        0;
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      // Карточка закреплена и не скроллится со списком, но длинный пост не
      // должен съедать весь экран — ограничиваем высоту и скроллим внутри.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height / 3,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: MessageContent(
                post,
                timeline: timeline,
                textColor: theme.colorScheme.onSurface,
                linkColor: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                selected: false,
              ),
            ),
            ChannelPostStatsRow(
              reactionChips: hasReactions
                  ? MessageReactions.chipsFor(context, post, timeline)
                  : null,
              viewCount: viewCount,
              time: post.originServerTs.localizedTimeOfDay(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Один комментарий: аватар, имя автора, текст. Тред плоский — ответ на ответ
/// рисуется цитатой-заголовком, а не вложенным уровнем (как в Liza).
class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.room,
    required this.quoted,
    required this.onReply,
  });

  final Map<String, dynamic> comment;
  final Room? room;

  /// Долгое нажатие по комментарию → ответить на него (как в задании: «по
  /// зажатию внутри треда отвечать»).
  final VoidCallback onReply;

  /// Комментарий, на который отвечает этот, — рисуется цитатой-заголовком.
  /// null для ответа прямо на пост.
  final Map<String, dynamic>? quoted;

  String _nameOf(Map<String, dynamic> event) {
    final senderId = event['sender'];
    if (senderId is! String) return '';
    return room
            ?.unsafeGetUserFromMemoryOrFallback(senderId)
            .calcDisplayname() ??
        senderId;
  }

  static String _bodyOf(Map<String, dynamic> event) {
    final content = event['content'];
    final body = content is Map ? content['body'] : null;
    if (body is! String) return '';
    // Срезаем reply-фолбэк («> …» строки + пустая строка), который SDK
    // добавляет в плейн-body при `inReplyTo`: адресата тред уже показывает
    // цитатой-заголовком, дублировать его в тексте не нужно.
    return body.replaceFirst(_replyFallbackPrefix, '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = _bodyOf(comment);
    final senderId = comment['sender'];
    final displayName = _nameOf(comment);
    final quoted = this.quoted;
    return InkWell(
      onLongPress: onReply,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Avatar(
              name: displayName,
              size: 32,
              mxContent: senderId is String
                  ? room?.unsafeGetUserFromMemoryOrFallback(senderId).avatarUrl
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Ответ на ответ: адресат — цитатой-заголовком, без
                  // вложенного уровня (тред плоский, как в Liza).
                  if (quoted != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            width: 2,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _nameOf(quoted),
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          Text(
                            _bodyOf(quoted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text(body, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Поле ввода комментария: плашка «ответ на …» сверху, @упоминание участников,
/// само поле и кнопка отправки.
class _ThreadComposer extends StatefulWidget {
  const _ThreadComposer({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.replyToName,
    required this.replyToBody,
    required this.onCancelReply,
    required this.mentionCandidates,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  /// Имя/текст комментария, на который отвечаем (null — обычный комментарий).
  final String? replyToName;
  final String? replyToBody;
  final VoidCallback onCancelReply;

  /// Кандидаты @упоминания (mxid + отображаемое имя).
  final List<({String id, String name})> mentionCandidates;

  @override
  State<_ThreadComposer> createState() => _ThreadComposerState();
}

class _ThreadComposerState extends State<_ThreadComposer> {
  /// `@токен` в конце текста ДО курсора (по началу строки или после пробела).
  static final _mentionTrigger = RegExp(
    r'(^|\s)@([\p{L}\p{N}_.-]*)$',
    unicode: true,
  );

  List<({String id, String name})> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final sel = widget.controller.selection;
    final text = widget.controller.text;
    if (!sel.isValid || !sel.isCollapsed || sel.baseOffset > text.length) {
      _setSuggestions(const []);
      return;
    }
    final before = text.substring(0, sel.baseOffset);
    final match = _mentionTrigger.firstMatch(before);
    if (match == null) {
      _setSuggestions(const []);
      return;
    }
    final query = match.group(2)!.toLowerCase();
    _setSuggestions(
      widget.mentionCandidates
          .where(
            (c) =>
                c.name.toLowerCase().contains(query) ||
                c.id.toLowerCase().contains(query),
          )
          .take(6)
          .toList(),
    );
  }

  void _setSuggestions(List<({String id, String name})> next) {
    if (_suggestions.length == next.length &&
        _suggestions.isEmpty &&
        next.isEmpty) {
      return;
    }
    setState(() => _suggestions = next);
  }

  void _insertMention(({String id, String name}) c) {
    final sel = widget.controller.selection;
    final text = widget.controller.text;
    final before = text.substring(0, sel.baseOffset);
    final after = text.substring(sel.baseOffset);
    final match = _mentionTrigger.firstMatch(before);
    if (match == null) return;
    // group(1) — ведущий пробел/начало строки; сам `@токен` начинается после
    // него. Сохраняем ведущий символ, заменяем токен на `@Имя `.
    final tokenStart = match.start + match.group(1)!.length;
    final newBefore = '${before.substring(0, tokenStart)}@${c.name} ';
    widget.controller.value = TextEditingValue(
      text: '$newBefore$after',
      selection: TextSelection.collapsed(offset: newBefore.length),
    );
    _setSuggestions(const []);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_suggestions.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: Material(
                color: theme.colorScheme.surfaceContainerHighest,
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    for (final c in _suggestions)
                      ListTile(
                        dense: true,
                        leading: Avatar(name: c.name, size: 28),
                        title: Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _insertMention(c),
                      ),
                  ],
                ),
              ),
            ),
          if (widget.replyToName != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 0),
              child: Row(
                children: [
                  Icon(
                    Icons.reply_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.replyToName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        if ((widget.replyToBody ?? '').isNotEmpty)
                          Text(
                            widget.replyToBody!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: widget.onCancelReply,
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: L10n.of(context).channelAddComment,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          AppConfig.borderRadius,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: widget.sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.send_outlined),
                  color: theme.colorScheme.primary,
                  onPressed: widget.sending ? null : widget.onSend,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
