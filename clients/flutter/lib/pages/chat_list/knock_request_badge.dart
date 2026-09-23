import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:liza/utils/knock_requests.dart';

/// Бейдж-счётчик заявок на вступление (knock) на строке чата/компании.
///
/// Показывается только тем, кто может рассматривать заявки
/// (ownPowerLevel >= moderatorPowerLevel — тот же порог, что серверный
/// knock_notify). Для рядовых участников и не-knock комнат — пустой SizedBox.
///
/// Почему stateful, а не синхронный подсчёт в build():
/// - при room.partial==true (комната не открывалась в сессии) getParticipants()
///   не содержит knock-членов, а participantListComplete слеп к knock →
///   синхронный подсчёт дал бы ложный ноль. requestParticipants() подтягивает
///   членов из локальной БД, закрывая это.
/// - новая заявка приходит в state-секцию /sync, а не в timeline; подписка на
///   onSync обновляет счётчик (штатный _updateSub в chat_members к этому слеп).
class KnockRequestBadge extends StatefulWidget {
  final Room room;

  const KnockRequestBadge({required this.room, super.key});

  @override
  State<KnockRequestBadge> createState() => _KnockRequestBadgeState();
}

class _KnockRequestBadgeState extends State<KnockRequestBadge> {
  int _count = 0;
  bool _refreshing = false;
  bool _pendingRefresh = false;
  StreamSubscription<SyncUpdate>? _sub;

  @override
  void initState() {
    super.initState();
    _subscribe();
    _refresh();
  }

  @override
  void didUpdateWidget(KnockRequestBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    // State может переиспользоваться при смене room — переподписаться и пересчитать.
    if (oldWidget.room.id != widget.room.id) {
      _sub?.cancel();
      _count = 0;
      _subscribe();
      _refresh();
    }
  }

  void _subscribe() {
    _sub = widget.room.client.onSync.stream
        .where(_touchesMembership)
        .listen((_) => _refresh());
  }

  /// Событие membership в НАШЕЙ комнате (state-секция или timeline).
  bool _touchesMembership(SyncUpdate sync) {
    final update = sync.rooms?.join?[widget.room.id];
    if (update == null) return false;
    bool hasMember(List<MatrixEvent>? events) =>
        events?.any((e) => e.type == EventTypes.RoomMember) ?? false;
    return hasMember(update.state) || hasMember(update.timeline?.events);
  }

  Future<void> _refresh() async {
    // Дешёвый гейт первым: не тревожим БД/сеть для рядовых участников.
    if (!canReviewKnockRequests(widget.room)) {
      if (_count != 0 && mounted) setState(() => _count = 0);
      return;
    }
    // Уже идёт refresh — пометим, что нужен ещё один после (не теряем пакет sync).
    if (_refreshing) {
      _pendingRefresh = true;
      return;
    }
    _refreshing = true;
    try {
      // Подтягиваем knock-членов (при partial getParticipants() их не видит).
      await widget.room.requestParticipants(
        const [Membership.join, Membership.invite, Membership.knock],
        true, // suppressWarning
      );
    } catch (_) {
      // Сеть/гонка — используем то, что уже есть в памяти.
    } finally {
      _refreshing = false;
    }
    if (!mounted) return;
    final count = knockRequestCount(widget.room);
    if (count != _count) setState(() => _count = count);
    // Пришёл ещё sync во время await — догоняем.
    if (_pendingRefresh) {
      _pendingRefresh = false;
      unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_count <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 4.0),
      child: Badge(
        label: Text('$_count'),
        backgroundColor: Theme.of(context).colorScheme.tertiary,
      ),
    );
  }
}
