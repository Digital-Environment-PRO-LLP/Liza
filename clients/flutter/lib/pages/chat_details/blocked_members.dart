import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:liza/utils/auth_proxy_service.dart';
import 'package:liza/utils/miniapp_member_block.dart';
import '../../widgets/matrix.dart';
import 'blocked_members_view.dart';

/// Фильтрация списка блокировок по статусу и поисковому запросу (имя/логин).
/// Чистая функция — вынесена для тестируемости без поднятия виджета.
List<MemberBlockInfo> filterMemberBlocks(
  List<MemberBlockInfo> blocks, {
  String statusFilter = 'all',
  String query = '',
}) {
  final q = query.toLowerCase().trim();
  return blocks.where((b) {
    if (statusFilter != 'all' && b.status != statusFilter) return false;
    if (q.isEmpty) return true;
    return (b.displayName?.toLowerCase().contains(q) ?? false) ||
        b.mxid.toLowerCase().contains(q);
  }).toList();
}

/// Раздел «Заблокированные/удалённые участники» магазина (mini App).
/// Источник списка — auth-proxy (blocklist), там же статус и причина.
class BlockedMembersPage extends StatefulWidget {
  final String roomId;

  const BlockedMembersPage({required this.roomId, super.key});

  @override
  State<BlockedMembersPage> createState() => BlockedMembersController();
}

class BlockedMembersController extends State<BlockedMembersPage> {
  List<MemberBlockInfo>? blocks;
  List<MemberBlockInfo>? filteredBlocks;
  Object? error;

  /// 'all' | 'banned' | 'removed' | 'invite_revoked'.
  String statusFilter = 'all';

  final TextEditingController filterController = TextEditingController();

  int countForStatus(String status) =>
      blocks?.where((b) => b.status == status).length ?? 0;

  void setStatusFilter(String status) {
    statusFilter = status;
    setFilter();
  }

  void setFilter([dynamic _]) {
    final list = blocks;
    setState(() {
      filteredBlocks = list == null
          ? null
          : filterMemberBlocks(
              list,
              statusFilter: statusFilter,
              query: filterController.text,
            );
    });
  }

  Future<void> refresh([dynamic _]) async {
    try {
      setState(() {
        error = null;
      });
      final room = Matrix.of(context).client.getRoomById(widget.roomId);
      if (room == null) throw StateError('room not found');
      final result = await listStoreBlocks(room);
      if (!mounted) return;
      setState(() {
        blocks = result;
      });
      setFilter();
    } catch (e, s) {
      Logs().w('[BlockedMembers] load failed', e, s);
      if (!mounted) return;
      setState(() {
        error = e;
      });
    }
  }

  /// Восстановление: снять блок в auth-proxy + Matrix-unban (если был бан) +
  /// переприглашение обратно в чат. Matrix-unban только снимает запрет, но НЕ
  /// возвращает участника; чтобы «снова сделать чат доступным» (как в задаче),
  /// сразу шлём invite — участник появляется как «Приглашён» и возвращается в
  /// один тап (а также снова может воспользоваться ссылкой — гейт снят).
  Future<void> restore(MemberBlockInfo block) async {
    final room = Matrix.of(context).client.getRoomById(widget.roomId);
    if (room == null) return;
    await unblockStoreMember(room: room, userId: block.mxid);
    try {
      await room.unban(block.mxid);
    } on MatrixException catch (_) {
      // Не был забанен в Matrix (например invite_revoked через kick) — норм.
    }
    try {
      await room.invite(block.mxid);
    } on MatrixException catch (_) {
      // Уже приглашён/в комнате — идемпотентно, игнорируем.
    }
    await refresh();
  }

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlockedMembersView(this);
}
