import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../l10n/l10n.dart';
import '../../../utils/stories/open_user_stories.dart';
import '../../../utils/stories/story_model.dart';
import '../../../widgets/mxc_image.dart';

/// Карточка-цитата сторис в чате (reply автору / поделиться).
/// body события - fallback-текст, карточка рендерится поверх него.
class StoryRefCard extends StatelessWidget {
  const StoryRefCard({required this.event, required this.textColor, super.key});

  final Event event;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final ref = StoryRef.fromContent(event.content);
    if (ref == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    // Текст пользователя - последняя часть body после fallback-префикса.
    final body = event.content.tryGet<String>('body') ?? '';
    final newline = body.indexOf('\n');
    final userText = newline >= 0 ? body.substring(newline + 1) : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => openStoryByRef(context, ref),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: theme.colorScheme.primary, width: 3),
              ),
              color: theme.colorScheme.primary.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (ref.thumbnailMxc != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 36,
                      height: 64,
                      child: MxcImage(
                        uri: Uri.parse(ref.thumbnailMxc!),
                        width: 36,
                        height: 64,
                        fit: BoxFit.cover,
                        client: event.room.client,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      L10n.of(context).storyCardTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    Text(
                      event.room
                          .unsafeGetUserFromMemoryOrFallback(ref.authorId)
                          .calcDisplayname(),
                      style: TextStyle(color: textColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (userText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(userText, style: TextStyle(color: textColor)),
          ),
      ],
    );
  }
}
