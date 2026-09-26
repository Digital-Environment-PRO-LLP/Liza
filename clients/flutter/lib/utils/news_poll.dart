import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

/// Опросы Liza News (спека docs/superpowers/specs/2026-09-21-liza-news-polls-design.md).
///
/// Голос НЕ пишется в комнату: канал read-only, а событие комнаты увидел бы каждый
/// подписчик. Голос и запрос итогов уходят to-device на устройство бота
/// `@liza-news`, ответы приходят тем же путём. Истина — у бота; свой выбор клиент
/// кэширует в личном account_data (виден только владельцу).
const String newsPollMsgType = 'com.liza.news.poll';
const String newsPollVotesAccountDataType = 'com.liza.news.poll_votes';

const String newsPollVoteType = 'com.liza.news.poll.vote';
const String newsPollMineType = 'com.liza.news.poll.mine';
const String newsPollAckType = 'com.liza.news.poll.ack';
const String newsPollResultsRequestType = 'com.liza.news.poll.results.request';
const String newsPollResultsType = 'com.liza.news.poll.results';

/// Отправитель, от которого карточка опроса интерактивна. Вместе с ролью `ai`
/// (проверка в виджете) это защита от поддельного опроса в чужой комнате.
const Set<String> newsBotMxids = {
  '@liza-news:bots.liza.ru',
  '@liza-news:liza.local',
};

/// Сколько закрытых опросов держим в account_data (лимит события ~65 КБ).
const int newsPollKeepClosed = 50;

/// Личный чат с ботом Liza News — единственное место, где редактор создаёт опрос.
///
/// `directChatMatrixID` полагается на account_data `m.direct`, а чат, созданный
/// САМИМ ботом (`room_create(is_direct: true)` со стороны бота), у пользователя
/// там не отмечен — поле пустое, и пункт «Опрос» в «+» не появлялся (инцидент
/// 2026-09-21, сборка 3764). Поэтому фолбэк по участникам, как у
/// `isBotFatherRoom`: бот среди участников И в комнате только мы вдвоём — так
/// пункт не всплывёт в самом канале Liza News (там бот тоже участник).
bool isNewsBotDm(Room room) {
  final partner = room.directChatMatrixID;
  if (partner != null) return newsBotMxids.contains(partner);
  final myId = room.client.userID;
  final others = room
      .getParticipants()
      .where((m) => m.id != myId)
      .map((m) => m.id)
      .toSet();
  return others.length == 1 && newsBotMxids.contains(others.first);
}

class NewsPollAnswer {
  final String id;
  final String text;
  const NewsPollAnswer(this.id, this.text);
}

/// Разобранная карточка опроса. null — контент битый (рисуем body).
class NewsPollData {
  final String pollId;
  final String text;
  final String question;
  final List<NewsPollAnswer> answers;
  final int maxSelections;
  final String botDevice;
  final bool closed;

  const NewsPollData({
    required this.pollId,
    required this.text,
    required this.question,
    required this.answers,
    required this.maxSelections,
    required this.botDevice,
    required this.closed,
  });

  bool get multiple => maxSelections > 1;

  static NewsPollData? fromContent(Map<String, Object?> content) {
    final inner = content.tryGetMap<String, Object?>(newsPollMsgType);
    if (inner == null) return null;
    final pollId = inner.tryGet<String>('poll_id');
    final question = inner.tryGet<String>('question');
    final botDevice = inner.tryGet<String>('bot_device');
    final raw = inner.tryGetList<Object?>('answers');
    if (pollId == null ||
        question == null ||
        botDevice == null ||
        raw == null) {
      return null;
    }
    final answers = <NewsPollAnswer>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final id = item['id'];
      final text = item['text'];
      if (id is String && text is String) answers.add(NewsPollAnswer(id, text));
    }
    if (answers.length < 2) return null;
    return NewsPollData(
      pollId: pollId,
      text: inner.tryGet<String>('text') ?? '',
      question: question,
      answers: answers,
      maxSelections: inner.tryGet<int>('max_selections') ?? 1,
      botDevice: botDevice,
      closed: inner.tryGet<bool>('closed') ?? false,
    );
  }
}

enum NewsPollVoteStatus { idle, sending, voted, failed }

/// Состояние СВОЕГО голоса по одному опросу.
@immutable
class NewsPollVoteState {
  /// Подтверждённый ботом выбор (пусто — не голосовал или отозвал).
  final List<String> answers;

  /// Выбор «в полёте» — рисуется поверх [answers], пока нет ack.
  final List<String>? pending;
  final NewsPollVoteStatus status;
  final bool closed;
  final String? error;

  const NewsPollVoteState({
    this.answers = const [],
    this.pending,
    this.status = NewsPollVoteStatus.idle,
    this.closed = false,
    this.error,
  });

  List<String> get shown => pending ?? answers;

  NewsPollVoteState copyWith({
    List<String>? answers,
    List<String>? pending,
    bool clearPending = false,
    NewsPollVoteStatus? status,
    bool? closed,
    String? error,
    bool clearError = false,
  }) => NewsPollVoteState(
    answers: answers ?? this.answers,
    pending: clearPending ? null : (pending ?? this.pending),
    status: status ?? this.status,
    closed: closed ?? this.closed,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  bool operator ==(Object other) =>
      other is NewsPollVoteState &&
      const ListEquality<String>().equals(other.answers, answers) &&
      const ListEquality<String>().equals(other.pending, pending) &&
      other.status == status &&
      other.closed == closed &&
      other.error == error;

  @override
  int get hashCode => Object.hash(
    const ListEquality<String>().hash(answers),
    const ListEquality<String>().hash(pending),
    status,
    closed,
    error,
  );
}

class NewsPollOption {
  final String id;
  final String text;
  final List<String> voters;
  const NewsPollOption(this.id, this.text, this.voters);
}

class NewsPollResults {
  final bool closed;
  final int totalVoters;
  final List<NewsPollOption> options;

  /// Платформы аудитории опроса (`ios`/`macos`/`android`); null — для всех.
  /// Старый бот поле не шлёт.
  final List<String>? audience;
  const NewsPollResults(
    this.closed,
    this.totalVoters,
    this.options, {
    this.audience,
  });
}

/// Подписи платформ аудитории — как у бота (`core.PLATFORM_LABELS`), в его порядке.
const Map<String, String> newsAudiencePlatformLabels = {
  'ios': 'iPhone',
  'macos': 'Mac',
  'android': 'Android',
};

String? newsAudienceLabel(List<String>? platforms) {
  if (platforms == null || platforms.isEmpty) return null;
  final labels = [
    for (final e in newsAudiencePlatformLabels.entries)
      if (platforms.contains(e.key)) e.value,
  ];
  return labels.isEmpty ? null : labels.join(', ');
}

/// Бот отказал в итогах (роль ≠ developer или нет в списке редакции).
class NewsPollForbidden implements Exception {
  const NewsPollForbidden();
}

/// Сервис голосов: ОДНА подписка на to-device/account_data на клиента, состояние
/// каждого опроса — в своём [ValueNotifier] (голос по опросу A не перестраивает
/// карточку опроса B).
class NewsPollService {
  NewsPollService._(this.client) {
    _toDeviceSub = client.onToDeviceEvent.stream
        .where(
          (e) => e.type == newsPollAckType || e.type == newsPollResultsType,
        )
        .listen(_onToDevice);
    _accountDataSub = client.onSync.stream.listen((sync) {
      for (final event in sync.accountData ?? const <BasicEvent>[]) {
        if (event.type == newsPollVotesAccountDataType) {
          _applyAccountData(event.content);
        }
      }
    });
    // Выход из аккаунта: сервис живёт в статической карте по клиенту — без этого
    // подписки разлогиненного Client копились бы до конца процесса.
    _loginSub = client.onLoginStateChanged.stream.listen((state) {
      if (state != LoginState.loggedOut) return;
      if (identical(_instances[client], this)) _instances.remove(client);
      dispose();
    });
  }

  static final Map<Client, NewsPollService> _instances = {};

  static NewsPollService of(Client client) =>
      _instances[client] ??= NewsPollService._(client);

  @visibleForTesting
  static void resetForTest() {
    for (final service in _instances.values) {
      service.dispose();
    }
    _instances.clear();
  }

  final Client client;
  StreamSubscription? _toDeviceSub;
  StreamSubscription? _accountDataSub;
  StreamSubscription? _loginSub;

  static const Duration ackTimeout = Duration(seconds: 8);
  static const int maxAttempts = 3;

  final Map<String, ValueNotifier<NewsPollVoteState>> _states = {};
  final Map<String, _InFlightVote> _votes = {};
  final Map<String, Completer<Map<String, Object?>>> _results = {};
  final Set<String> _mineRequested = {};

  /// seq голоса, уже применённого к состоянию опроса (из ack бота). Ответ со
  /// МЕНЬШИМ seq устарел — напр. ответ на «мой голос», пришедший по федерации
  /// позже ack свежего голоса, — и не должен откатить выбор.
  final Map<String, int> _appliedSeq = {};
  int _lastSeq = 0;
  final Random _random = Random.secure();

  ValueNotifier<NewsPollVoteState> stateOf(String pollId) =>
      _states[pollId] ??= ValueNotifier(_fromAccountData(pollId));

  NewsPollVoteState _fromAccountData(String pollId) {
    final stored = client.accountData[newsPollVotesAccountDataType]?.content
        .tryGetMap<String, Object?>(pollId);
    if (stored == null) return const NewsPollVoteState();
    final answers = stored.tryGetList<String>('answers') ?? const [];
    return NewsPollVoteState(
      answers: answers,
      status: answers.isEmpty
          ? NewsPollVoteStatus.idle
          : NewsPollVoteStatus.voted,
      closed: stored.tryGet<bool>('closed') ?? false,
    );
  }

  void _applyAccountData(Map<String, Object?> content) {
    for (final entry in _states.entries) {
      // Голос «в полёте» важнее кэша: account_data догонит после ack.
      if (_votes.containsKey(entry.key)) continue;
      final stored = content.tryGetMap<String, Object?>(entry.key);
      if (stored == null) continue;
      final answers = stored.tryGetList<String>('answers') ?? const [];
      final next = entry.value.value.copyWith(
        answers: answers,
        status: answers.isEmpty
            ? NewsPollVoteStatus.idle
            : NewsPollVoteStatus.voted,
        closed:
            (stored.tryGet<bool>('closed') ?? false) ||
            entry.value.value.closed,
      );
      if (next != entry.value.value) entry.value.value = next;
    }
  }

  String _reqId() =>
      List.generate(12, (_) => _random.nextInt(36).toRadixString(36)).join();

  int _nextSeq() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastSeq = now > _lastSeq ? now : _lastSeq + 1;
    return _lastSeq;
  }

  Future<void> _send(
    String botMxid,
    String botDevice,
    String type,
    Map<String, Object?> content,
  ) => client.sendToDevice(type, client.generateUniqueTransactionId(), {
    botMxid: {botDevice: content},
  });

  /// Подтянуть свой голос у бота, если локально его нет (другой девайс, потерянный
  /// ack, свежая установка). Один раз на опрос за сессию.
  void ensureLoaded(String botMxid, NewsPollData poll) {
    if (!_mineRequested.add(poll.pollId)) return;
    final state = stateOf(poll.pollId);
    if (poll.closed && !state.value.closed) {
      state.value = state.value.copyWith(closed: true);
    }
    if (state.value.status != NewsPollVoteStatus.idle) return;
    _send(botMxid, poll.botDevice, newsPollMineType, {
      'poll_id': poll.pollId,
      'req_id': _reqId(),
    }).catchError((Object e) => Logs().w('[NewsPoll] mine: $e'));
  }

  /// Проголосовать ([answers] пуст — отозвать голос). Оптимистично: выбор виден
  /// сразу со статусом «отправляется», при отсутствии ack — повтор с тем же seq
  /// (бот идемпотентен), после [maxAttempts] — откат.
  void vote(String botMxid, NewsPollData poll, List<String> answers) {
    final state = stateOf(poll.pollId);
    _votes.remove(poll.pollId)?.timer?.cancel();
    final inFlight = _InFlightVote(
      botMxid: botMxid,
      poll: poll,
      answers: List.unmodifiable(answers),
      seq: _nextSeq(),
      reqId: _reqId(),
    );
    _votes[poll.pollId] = inFlight;
    state.value = state.value.copyWith(
      pending: inFlight.answers,
      status: NewsPollVoteStatus.sending,
      clearError: true,
    );
    _attempt(inFlight);
  }

  void _attempt(_InFlightVote v) {
    v.attempts++;
    _send(v.botMxid, v.poll.botDevice, newsPollVoteType, {
      'poll_id': v.poll.pollId,
      'answers': v.answers,
      'seq': v.seq,
      'req_id': v.reqId,
    }).catchError((Object e) => Logs().w('[NewsPoll] vote send: $e'));
    v.timer = Timer(ackTimeout, () {
      if (_votes[v.poll.pollId] != v) return;
      if (v.attempts < maxAttempts) {
        _attempt(v);
        return;
      }
      _votes.remove(v.poll.pollId);
      final state = stateOf(v.poll.pollId);
      state.value = state.value.copyWith(
        clearPending: true,
        status: state.value.answers.isEmpty
            ? NewsPollVoteStatus.failed
            : NewsPollVoteStatus.voted,
        error: 'timeout',
      );
    });
  }

  void _onToDevice(ToDeviceEvent event) {
    final content = event.content;
    final reqId = content.tryGet<String>('req_id');
    final pollId = content.tryGet<String>('poll_id');
    if (reqId == null || pollId == null) return;
    // Ответ — только от бота Liza News (to-device может прислать кто угодно).
    if (!newsBotMxids.contains(event.senderId)) return;
    if (event.type == newsPollResultsType) {
      _results.remove(reqId)?.complete(content);
      return;
    }
    _onAck(pollId, reqId, content);
  }

  void _onAck(String pollId, String reqId, Map<String, Object?> content) {
    final inFlight = _votes[pollId];
    // ack чужого (устаревшего) запроса не должен откатить свежий голос в полёте.
    if (inFlight != null && inFlight.reqId != reqId) return;
    final seq = content.tryGet<int>('seq') ?? 0;
    if (inFlight == null && seq < (_appliedSeq[pollId] ?? 0)) return;
    _appliedSeq[pollId] = seq;
    inFlight?.timer?.cancel();
    _votes.remove(pollId);
    final answers = content.tryGetList<String>('answers') ?? const [];
    final closed = content.tryGet<bool>('closed') ?? false;
    final error = content.tryGet<String>('error');
    final state = stateOf(pollId);
    state.value = NewsPollVoteState(
      answers: answers,
      status: error != null && inFlight != null
          ? NewsPollVoteStatus.failed
          : (answers.isEmpty
                ? NewsPollVoteStatus.idle
                : NewsPollVoteStatus.voted),
      closed: closed || state.value.closed,
      error: inFlight != null ? error : null,
    );
    if (error == null || error == 'closed') {
      _persist(pollId, answers, closed);
    }
  }

  Future<void> _persist(
    String pollId,
    List<String> answers,
    bool closed,
  ) async {
    final userId = client.userID;
    if (userId == null) return;
    final current = Map<String, Object?>.from(
      client.accountData[newsPollVotesAccountDataType]?.content ?? const {},
    );
    final next = Map<String, Object?>.from(current)
      ..[pollId] = {'answers': answers, 'closed': closed};
    final pruned = pruneStoredVotes(next);
    if (const DeepCollectionEquality().equals(pruned, current)) return;
    try {
      await client.setAccountData(userId, newsPollVotesAccountDataType, pruned);
    } catch (e) {
      Logs().w('[NewsPoll] account_data: $e');
    }
  }

  /// Итоги опроса — только разработчикам из списка редакции (решает бот).
  /// Бросает [NewsPollForbidden] при отказе, [TimeoutException] без ответа.
  Future<NewsPollResults> requestResults(
    String botMxid,
    NewsPollData poll,
  ) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final reqId = _reqId();
      final completer = Completer<Map<String, Object?>>();
      _results[reqId] = completer;
      try {
        await _send(botMxid, poll.botDevice, newsPollResultsRequestType, {
          'poll_id': poll.pollId,
          'req_id': reqId,
        });
        final content = await completer.future.timeout(ackTimeout);
        return parseResults(content);
      } on TimeoutException {
        if (attempt == maxAttempts) rethrow;
      } finally {
        _results.remove(reqId);
      }
    }
    throw TimeoutException('results');
  }

  void dispose() {
    _toDeviceSub?.cancel();
    _accountDataSub?.cancel();
    _loginSub?.cancel();
    for (final v in _votes.values) {
      v.timer?.cancel();
    }
  }
}

class _InFlightVote {
  final String botMxid;
  final NewsPollData poll;
  final List<String> answers;
  final int seq;
  final String reqId;
  int attempts = 0;
  Timer? timer;

  _InFlightVote({
    required this.botMxid,
    required this.poll,
    required this.answers,
    required this.seq,
    required this.reqId,
  });
}

/// Ответ бота → итоги; `error: forbidden` → [NewsPollForbidden].
NewsPollResults parseResults(Map<String, Object?> content) {
  if (content.tryGet<String>('error') != null) throw const NewsPollForbidden();
  final options = <NewsPollOption>[];
  for (final item in content.tryGetList<Object?>('options') ?? const []) {
    if (item is! Map) continue;
    final id = item['id'];
    final text = item['text'];
    final voters = item['voters'];
    if (id is! String || text is! String || voters is! List) continue;
    options.add(NewsPollOption(id, text, voters.whereType<String>().toList()));
  }
  return NewsPollResults(
    content.tryGet<bool>('closed') ?? false,
    content.tryGet<int>('total_voters') ?? 0,
    options,
    audience: content.tryGetList<String>('audience'),
  );
}

/// Открытые опросы храним все, закрытые — последние [newsPollKeepClosed]
/// (порядок вставки Map = порядок голосования).
@visibleForTesting
Map<String, Object?> pruneStoredVotes(Map<String, Object?> votes) {
  final closedKeys = [
    for (final e in votes.entries)
      if (e.value is Map && (e.value as Map)['closed'] == true) e.key,
  ];
  final drop = closedKeys.length - newsPollKeepClosed;
  if (drop <= 0) return votes;
  final dropKeys = closedKeys.take(drop).toSet();
  return {
    for (final e in votes.entries)
      if (!dropKeys.contains(e.key)) e.key: e.value,
  };
}
