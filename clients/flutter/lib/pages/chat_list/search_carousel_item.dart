import 'package:flutter/material.dart';

import 'package:liza/utils/user_role_service.dart';
import 'package:liza/widgets/avatar.dart';
import 'package:liza/widgets/matrix.dart';
import 'package:liza/widgets/user_role_badge.dart';

/// Плитка горизонтальной карусели поиска главного экрана (люди, публичные
/// чаты/каналы, компании). Общая для трёх каруселей; вынесена из
/// `chat_list_body.dart` вместе с каруселью людей
/// (`search_users_horizontal_list.dart`), чтобы её можно было отрисовать в
/// страже на реальном виджете.
///
/// [avatarName] — строка для буквы-фоллбэка аватара, когда она должна
/// отличаться от заголовка (у людей заголовок может быть `@ник`, а буква —
/// первая буква ника без сигила). По умолчанию совпадает с [title].
/// [userId] задан только у людей: включает шестиугольный аватар ИИ и плашку
/// роли.
class SearchCarouselItem extends StatelessWidget {
  final String title;
  final String? avatarName;
  final Uri? avatar;
  final String? userId;
  final void Function() onPressed;
  final void Function()? onLongPress;

  const SearchCarouselItem({
    required this.title,
    required this.onPressed,
    this.avatarName,
    this.avatar,
    this.userId,
    this.onLongPress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final uid = userId;
    return GestureDetector(
      onTap: onPressed,
      onLongPress: onLongPress,
      onSecondaryTap: onLongPress,
      child: SizedBox(
        width: 84,
        child: Column(
          mainAxisSize: .min,
          children: [
            const SizedBox(height: 8),
            Avatar(
              mxContent: avatar,
              name: avatarName ?? title,
              isHexagonal: uid != null && Matrix.of(context).isAiUser(uid),
            ),
            if (uid != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: UserRoleBadge(
                  userId: uid,
                  fontSize: 9,
                  hideRoleCodes: const {
                    UserRoleService.adminRole,
                    UserRoleService.moderatorRole,
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                title,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
