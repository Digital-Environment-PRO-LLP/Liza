import 'package:flutter/material.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/auth_proxy_service.dart';
import 'package:liza/utils/localized_exception_extension.dart';
import 'package:liza/utils/miniapp_member_block.dart';
import '../../widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import '../../widgets/avatar.dart';
import '../../widgets/future_loading_dialog.dart';
import '../../widgets/layouts/max_width_body.dart';
import '../../widgets/matrix.dart';
import '../../widgets/user_identifier.dart';
import 'blocked_members.dart';

class BlockedMembersView extends StatelessWidget {
  final BlockedMembersController controller;

  const BlockedMembersView(this.controller, {super.key});

  String _statusLabel(BuildContext context, String status) => switch (status) {
    MemberBlockStatus.banned => L10n.of(context).memberStatusBanned,
    MemberBlockStatus.removed => L10n.of(context).memberStatusRemoved,
    MemberBlockStatus.inviteRevoked => L10n.of(
      context,
    ).memberStatusInviteRevoked,
    _ => status,
  };

  Future<void> _restore(BuildContext context, MemberBlockInfo block) async {
    final confirmed = await showOkCancelAlertDialog(
      context: context,
      title: L10n.of(context).restoreMember,
      message: L10n.of(context).restoreMemberDescription,
      okLabel: L10n.of(context).yes,
      cancelLabel: L10n.of(context).no,
    );
    if (confirmed != OkCancelResult.ok) return;
    if (!context.mounted) return;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => controller.restore(block),
    );
    if (result.error != null) return;
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(L10n.of(context).memberRestored)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blocks = controller.filteredBlocks;
    final error = controller.error;

    // Статусы для фильтр-чипов: «Все» + те, что реально встречаются в списке.
    const statuses = [
      MemberBlockStatus.banned,
      MemberBlockStatus.removed,
      MemberBlockStatus.inviteRevoked,
    ];
    final presentStatuses = statuses
        .where((s) => controller.countForStatus(s) > 0)
        .toList();

    return Scaffold(
      appBar: AppBar(
        leading: const Center(child: BackButton()),
        title: Text(L10n.of(context).blockedAndRemovedMembers),
      ),
      body: MaxWidthBody(
        withScrolling: false,
        innerPadding: const EdgeInsets.symmetric(vertical: 8),
        child: error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline),
                      Text(error.toLocalizedString(context)),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: controller.refresh,
                        icon: const Icon(Icons.refresh_outlined),
                        label: Text(L10n.of(context).tryAgain),
                      ),
                    ],
                  ),
                ),
              )
            : blocks == null
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator.adaptive(),
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: blocks.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: TextField(
                            controller: controller.filterController,
                            onChanged: controller.setFilter,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: theme.colorScheme.secondaryContainer,
                              border: OutlineInputBorder(
                                borderSide: BorderSide.none,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              prefixIcon: const Icon(Icons.search_outlined),
                              hintText: L10n.of(context).searchByNameOrId,
                            ),
                          ),
                        ),
                        if (presentStatuses.length > 1)
                          SizedBox(
                            height: 64,
                            child: ListView(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12.0,
                                vertical: 12.0,
                              ),
                              scrollDirection: Axis.horizontal,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4.0,
                                  ),
                                  child: FilterChip(
                                    label: Text(L10n.of(context).filterAll),
                                    selected: controller.statusFilter == 'all',
                                    onSelected: (_) =>
                                        controller.setStatusFilter('all'),
                                  ),
                                ),
                                for (final s in presentStatuses)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4.0,
                                    ),
                                    child: FilterChip(
                                      label: Text(
                                        '${_statusLabel(context, s)}'
                                        ' (${controller.countForStatus(s)})',
                                      ),
                                      selected: controller.statusFilter == s,
                                      onSelected: (_) =>
                                          controller.setStatusFilter(s),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        if (blocks.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Text(
                              L10n.of(context).noBlockedMembers,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    );
                  }
                  final block = blocks[i - 1];
                  final name = block.displayName?.isNotEmpty == true
                      ? block.displayName!
                      : block.mxid.split(':').first.replaceFirst('@', '');
                  return ListTile(
                    leading: Avatar(name: name),
                    title: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${userIdentifier(block.mxid, handles: Matrix.of(context).userHandleService)}\n'
                      '${_statusLabel(context, block.status)}'
                      '${block.reason?.isNotEmpty == true ? ' · ${block.reason}' : ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: true,
                    trailing: TextButton.icon(
                      onPressed: () => _restore(context, block),
                      icon: const Icon(Icons.restore_outlined),
                      label: Text(L10n.of(context).restoreMember),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
