import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/config/themes.dart';
import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/date_time_extension.dart';
import 'package:liza/utils/direct_chat_draft.dart';
import 'package:liza/utils/stories/active_stories_provider.dart';
import 'package:liza/utils/stories/open_user_stories.dart';
import 'package:liza/utils/stories/stories_seen_store.dart';
import 'package:liza/widgets/adaptive_dialogs/adaptive_dialog_action.dart';
import 'package:liza/widgets/avatar.dart';
import 'package:liza/widgets/presence_builder.dart';
import 'package:liza/widgets/user_identifier.dart';
import 'package:liza/widgets/user_role_badge.dart';
import '../../utils/url_launcher.dart';
import '../hover_builder.dart';
import '../matrix.dart';
import '../mxc_image_viewer.dart';

class UserDialog extends StatelessWidget {
  static Future<void> show({
    required BuildContext context,
    required Profile profile,
    bool noProfileWarning = false,
  }) => showAdaptiveDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) =>
        UserDialog(profile, noProfileWarning: noProfileWarning),
  );

  final Profile profile;
  final bool noProfileWarning;

  const UserDialog(this.profile, {this.noProfileWarning = false, super.key});

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    final handles = Matrix.of(context).userHandleService;
    final dmRoomId = client.getDirectChatFromUserId(profile.userId);
    // Имя → @ник → localpart: диалог по long-press на находке в поиске
    // открывается до/без подтянувшегося профиля — тогда заголовок ник, а не
    // технический user_<hex8> (LABA-2552).
    final label = searchResultLabel(
      profile,
      handles: handles,
      unknown: L10n.of(context).user,
    );
    final displayname = label.title;
    // Копирование отдаёт ник, если он есть в кэше (решение владельца) —
    // иначе прежнее поведение: технический MXID.
    final identifier = userIdentifier(profile.userId, handles: handles);
    var copied = false;
    final theme = Theme.of(context);
    final avatar = profile.avatarUrl;
    return AlertDialog.adaptive(
      title: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 256),
        child: Column(
          mainAxisSize: .min,
          children: [
            Text(displayname, textAlign: TextAlign.center),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: UserRoleBadge(userId: profile.userId, fontSize: 11),
            ),
          ],
        ),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 256, maxHeight: 256),
        child: PresenceBuilder(
          userId: profile.userId,
          client: Matrix.of(context).client,
          builder: (context, presence) {
            if (presence == null) return const SizedBox.shrink();
            final statusMsg = presence.statusMsg;
            final lastActiveTimestamp = presence.lastActiveTimestamp;
            final presenceText = presence.currentlyActive == true
                ? L10n.of(context).currentlyActive
                : lastActiveTimestamp != null
                ? L10n.of(context).lastActiveAgo(
                    lastActiveTimestamp.localizedTimeShort(context),
                  )
                : null;
            return SingleChildScrollView(
              child: Column(
                spacing: 8,
                mainAxisSize: .min,
                crossAxisAlignment: .stretch,
                children: [
                  Center(
                    child: Avatar(
                      mxContent: avatar,
                      name: label.avatarName,
                      size: Avatar.defaultSize * 2,
                      onTap: avatar != null
                          ? () => showDialog(
                              context: context,
                              builder: (_) => MxcImageViewer(avatar),
                            )
                          : null,
                      isHexagonal: Matrix.of(context).isAiUser(profile.userId),
                      storyRing: Matrix.of(context).isAiUser(profile.userId)
                          ? null
                          : ActiveStoriesProvider.instance.ringForUser(
                              profile.userId,
                              Matrix.of(context).client,
                              StoriesSeenStore(
                                Matrix.of(context).store,
                                scope: Matrix.of(context).client.userID,
                              ),
                            ),
                      onStoryTap: () =>
                          openUserStories(context, profile.userId),
                    ),
                  ),
                  HoverBuilder(
                    builder: (context, hovered) => StatefulBuilder(
                      builder: (context, setState) => MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: identifier));
                            setState(() {
                              copied = true;
                            });
                          },
                          child: RichText(
                            text: TextSpan(
                              children: [
                                WidgetSpan(
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 4.0),
                                    child: AnimatedScale(
                                      duration: LizaThemes.animationDuration,
                                      curve: LizaThemes.animationCurve,
                                      scale: hovered
                                          ? 1.33
                                          : copied
                                          ? 1.25
                                          : 1.0,
                                      child: Icon(
                                        copied
                                            ? Icons.check_circle
                                            : Icons.copy,
                                        size: 12,
                                        color: copied ? Colors.green : null,
                                      ),
                                    ),
                                  ),
                                ),
                                TextSpan(text: identifier),
                              ],
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 10,
                              ),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (presenceText != null)
                    Text(
                      presenceText,
                      style: const TextStyle(fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  if (statusMsg != null)
                    SelectableLinkify(
                      text: statusMsg,
                      textScaleFactor: MediaQuery.textScalerOf(
                        context,
                      ).scale(1),
                      textAlign: TextAlign.center,
                      options: const LinkifyOptions(humanize: false),
                      linkStyle: TextStyle(
                        color: theme.colorScheme.primary,
                        decoration: TextDecoration.underline,
                        decorationColor: theme.colorScheme.primary,
                      ),
                      onOpen: (url) =>
                          UrlLauncher(context, url.url).launchUrl(),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        if (client.userID != profile.userId) ...[
          AdaptiveDialogAction(
            borderRadius: AdaptiveDialogAction.topRadius,
            bigButtons: true,
            onPressed: () {
              // Чат/приглашение — только с первым сообщением: существующий DM
              // открываем сразу, иначе ведём в черновик (комната родится при
              // отправке). Роутер/клиент захватываем ДО pop диалога.
              final router = GoRouter.of(context);
              Navigator.of(context).pop();
              openDirectChatOrDraft(
                router,
                client,
                profile.userId,
                profile: profile,
              );
            },
            child: Text(
              dmRoomId == null
                  ? L10n.of(context).startConversation
                  : L10n.of(context).sendAMessage,
            ),
          ),
          AdaptiveDialogAction(
            bigButtons: true,
            borderRadius: AdaptiveDialogAction.centerRadius,
            onPressed: () {
              final router = GoRouter.of(context);
              Navigator.of(context).pop();
              router.go(
                '/rooms/settings/security/ignorelist',
                extra: profile.userId,
              );
            },
            child: Text(
              L10n.of(context).ignoreUser,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ],
        AdaptiveDialogAction(
          bigButtons: true,
          borderRadius: AdaptiveDialogAction.bottomRadius,
          onPressed: Navigator.of(context).pop,
          child: Text(L10n.of(context).close),
        ),
      ],
    );
  }
}
