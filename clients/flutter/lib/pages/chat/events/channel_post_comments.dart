import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/channel_discussion.dart';
import 'package:liza/widgets/future_loading_dialog.dart';

/// Сама плашка: иконка + «N комментариев» либо «Оставить комментарий».
/// Отделена от [ChannelPostComments], чтобы рендер проверялся тестом без
/// поднятого клиента (собрать настоящие Room/Event в тесте нечем).
class ChannelPostCommentsBar extends StatelessWidget {
  const ChannelPostCommentsBar({
    required this.count,
    required this.onTap,
    super.key,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Row(
          children: [
            Icon(
              Icons.mode_comment_outlined,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                // Ветку «нет комментариев» держим отдельным ключом, а не
                // формой `zero` в plural (она бы сработала: Intl.pluralLogic
                // проверяет `howMany == 0 && zero != null` до правил CLDR).
                // Причина семантическая: «Прокомментировать» — не форма
                // числа, а другой призыв к действию, и внутри plural ему не
                // место.
                count == 0
                    ? L10n.of(context).channelAddComment
                    : L10n.of(context).channelCommentsCount(count),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Плашка комментариев под постом канала. Тап открывает тред этого поста,
/// при необходимости тихо вступив в привязанный чат: подписчик открытого
/// канала членом чата не становится, а Matrix не даёт ни писать, ни держать
/// таймлайн без `join`.
class ChannelPostComments extends StatelessWidget {
  const ChannelPostComments({
    required this.room,
    required this.post,
    required this.discussionEvents,
    required this.onMembershipGained,
    super.key,
  });

  final Room room;
  final Event post;
  final List<Map<String, dynamic>> discussionEvents;

  /// Перечитать состояние комментариев после тихого join. До join не-член
  /// читает чат разовым peek'ом — мёртвым снимком; после вступления его надо
  /// заменить живым таймлайном, иначе счётчик застынет на том, что было при
  /// открытии канала (в том числе на нуле для только что оставленного
  /// комментария).
  final VoidCallback onMembershipGained;

  /// Открывает тред комментариев к этому посту, вступив в чат по-тихому.
  ///
  /// Ведёт именно в тред поста, а не в привязанный чат целиком: в чате
  /// комментарии к посту перемешаны с остальным обсуждением. Тихий join
  /// выполняется до перехода — он даёт треду живой таймлайн вместо мёртвого
  /// снимка peek'а.
  ///
  /// Намеренно НЕ вызывает `revealChatForMe()` — в отличие от кнопки
  /// «Обсуждение» в деталях канала. Это разные режимы: здесь пользователь
  /// пришёл комментировать конкретный пост и чат остаётся скрытым из списка
  /// (режим «комментирую, не вступая»), а осознанный вход — только через
  /// детали канала. Добавить сюда раскрытие = сломать этот режим.
  Future<void> _openThread(BuildContext context) async {
    final router = GoRouter.of(context);
    final wasMember = room.discussionRoom?.membership == Membership.join;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = L10n.of(context);
    // Тихий join в чат ЧУЖОГО хоумсервера идёт по федерации и занимает
    // секунды — без индикатора пользователь смотрит на замерший экран и
    // тапает плашку повторно. showFutureLoadingDialog даёт и спиннер, и
    // блокировку повторного тапа.
    final result = await showFutureLoadingDialog(
      context: context,
      future: room.ensureDiscussionMembershipResult,
    );
    final joinResult = result.result;
    if (joinResult == null || !joinResult.isJoined) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            // «Не приехало в sync» — это НЕ «нет доступа»: join на сервере
            // прошёл, и повтор через секунду обычно срабатывает.
            joinResult?.outcome == DiscussionJoinOutcome.timedOut
                ? l10n.channelDiscussionOpenSlow
                : l10n.channelDiscussionOpenFailed,
          ),
        ),
      );
      return;
    }
    if (!wasMember) {
      onMembershipGained();
    }
    router.go(
      '/rooms/${Uri.encodeComponent(room.id)}'
      '/post/${Uri.encodeComponent(post.eventId)}/comments',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!room.hasComments) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Полупрозрачная линия отделяет пост с реакциями от кнопки
        // комментариев — так же, как в Liza.
        Divider(
          height: 1,
          thickness: 1,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.12),
        ),
        ChannelPostCommentsBar(
          // Именно countThreadComments, а не countReplies: плашка обязана
          // показывать столько же, сколько лежит в треде, иначе «1
          // комментарий» открывает экран с шестью.
          count: countThreadComments(discussionEvents, post.eventId),
          onTap: () => _openThread(context),
        ),
      ],
    );
  }
}
