import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:matrix/matrix.dart';

import 'package:liza/config/themes.dart';
import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat_list/search_carousel_item.dart';
import 'package:liza/widgets/adaptive_dialogs/user_dialog.dart';
import 'package:liza/widgets/horizontal_mouse_wheel.dart';
import 'package:liza/widgets/matrix.dart';
import 'package:liza/widgets/user_identifier.dart';

/// Карусель людей в поиске главного экрана.
///
/// Вынесена из `chat_list_body.dart` в отдельный публичный виджет по тому же
/// прецеденту, что и `InvitePeopleListTile`: приватный класс внутри тяжёлого
/// `ChatListBody` нельзя отрисовать в страже на реальном виджете
/// (RL-search-handle-profile-hydration).
///
/// Рисует ровно то, что лежит в `userSearchResult.results` — контроллер
/// публикует результат мутацией этого списка (стадия 1: находки с
/// `@ник`-фоллбэком, стадия 2: те же индексы с именем и аватаром из
/// профиля). Сети из `build()` нет: заголовок и буква аватара считаются
/// синхронно через [searchResultLabel].
class SearchUsersHorizontalList extends StatefulWidget {
  const SearchUsersHorizontalList({
    required this.userSearchResult,
    required this.onItemTap,
    super.key,
  });

  final SearchUserDirectoryResponse? userSearchResult;
  final void Function(String userId) onItemTap;

  @override
  State<SearchUsersHorizontalList> createState() =>
      _SearchUsersHorizontalListState();
}

class _SearchUsersHorizontalListState extends State<SearchUsersHorizontalList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userSearchResult = widget.userSearchResult;
    final handles = Matrix.of(context).userHandleService;
    final unknown = L10n.of(context).user;
    return AnimatedContainer(
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      height: userSearchResult == null || userSearchResult.results.isEmpty
          ? 0
          : 106,
      duration: LizaThemes.animationDuration,
      curve: LizaThemes.animationCurve,
      child: userSearchResult == null
          ? null
          : HorizontalMouseWheel(
              controller: _scrollController,
              child: PrimaryScrollController.none(
                child: ListView.builder(
                  primary: false,
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  itemCount: userSearchResult.results.length,
                  itemBuilder: (context, i) {
                    final profile = userSearchResult.results[i];
                    final label = searchResultLabel(
                      profile,
                      handles: handles,
                      unknown: unknown,
                    );
                    return SearchCarouselItem(
                      title: label.title,
                      avatarName: label.avatarName,
                      avatar: profile.avatarUrl,
                      userId: profile.userId,
                      onPressed: () => widget.onItemTap(profile.userId),
                      onLongPress: () {
                        HapticFeedback.heavyImpact();
                        UserDialog.show(context: context, profile: profile);
                      },
                    );
                  },
                ),
              ),
            ),
    );
  }
}
