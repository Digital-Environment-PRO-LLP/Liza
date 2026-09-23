import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/config/themes.dart';
import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/chat.dart';
import 'package:liza/utils/date_time_extension.dart';
import 'package:liza/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:liza/utils/miniapp_room.dart';
import 'package:liza/utils/sync_status_localization.dart';
import 'package:liza/widgets/avatar.dart';
import 'package:liza/widgets/matrix.dart';
import 'package:liza/widgets/presence_builder.dart';
import 'package:liza/widgets/user_role_badge.dart';

class ChatAppBarTitle extends StatelessWidget {
  final ChatController controller;
  const ChatAppBarTitle(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final room = controller.room;
    if (controller.selectedEvents.isNotEmpty) {
      return Text(
        controller.selectedEvents.length.toString(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onTertiaryContainer,
        ),
      );
    }
    // LABA-2242: удалённый бот → «Удалённый аккаунт» + серый призрак (паритет с
    // Liza «Deleted Account»), вместо штатного «Пустой чат (был …)».
    final isDeletedBot = isDeletedBotDm(room);
    final displayname = isDeletedBot
        ? L10n.of(context).deletedAccount
        : room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    return InkWell(
      hoverColor: Colors.transparent,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      onTap: controller.isArchived
          ? null
          : () => LizaThemes.isThreeColumnMode(context)
                ? controller.toggleDisplayChatDetailsColumn()
                : context.go('/rooms/${room.id}/details'),
      child: Row(
        children: [
          Hero(
            tag: 'content_banner',
            child: Avatar(
              mxContent: room.avatar,
              name: displayname,
              size: 32,
              isDeleted: isDeletedBot,
              isHexagonal:
                  !isDeletedBot &&
                  room.directChatMatrixID != null &&
                  Matrix.of(context).isAiUser(room.directChatMatrixID!),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Text(
                  displayname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16),
                ),
                StreamBuilder(
                  stream: room.client.onSyncStatus.stream,
                  builder: (context, snapshot) {
                    final status =
                        room.client.onSyncStatus.value ??
                        const SyncStatusUpdate(SyncStatus.waitingForResponse);
                    final hide =
                        LizaThemes.isColumnMode(context) ||
                        (room.client.onSync.value != null &&
                            status.status != SyncStatus.error &&
                            room.client.prevBatch != null);
                    final badge =
                        room.directChatMatrixID == null || isDeletedBot
                        ? null
                        : UserRoleBadge(
                            userId: room.directChatMatrixID!,
                            fontSize: 9,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                          );
                    return AnimatedSize(
                      duration: LizaThemes.animationDuration,
                      child: hide
                          ? PresenceBuilder(
                              userId: room.directChatMatrixID,
                              builder: (context, presence) {
                                final lastActiveTimestamp =
                                    presence?.lastActiveTimestamp;
                                final style = TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.outline,
                                );
                                final presenceWidget =
                                    presence?.currentlyActive == true
                                    ? Text(
                                        L10n.of(context).currentlyActive,
                                        style: style,
                                      )
                                    : lastActiveTimestamp != null
                                    ? Text(
                                        L10n.of(context).lastActiveAgo(
                                          lastActiveTimestamp
                                              .localizedTimeShort(context),
                                        ),
                                        style: style,
                                      )
                                    : null;
                                if (badge == null && presenceWidget == null) {
                                  return const SizedBox.shrink();
                                }
                                return Row(
                                  children: [
                                    if (badge != null) badge,
                                    if (badge != null && presenceWidget != null)
                                      const SizedBox(width: 6),
                                    if (presenceWidget != null)
                                      Flexible(child: presenceWidget),
                                  ],
                                );
                              },
                            )
                          : Row(
                              children: [
                                SizedBox.square(
                                  dimension: 10,
                                  child: CircularProgressIndicator.adaptive(
                                    strokeWidth: 1,
                                    value: status.progress,
                                    valueColor: status.error != null
                                        ? AlwaysStoppedAnimation<Color>(
                                            Theme.of(context).colorScheme.error,
                                          )
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    status.calcLocalizedString(context),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: status.error != null
                                          ? Theme.of(context).colorScheme.error
                                          : null,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
