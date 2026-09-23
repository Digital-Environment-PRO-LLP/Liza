import 'package:flutter/material.dart';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:punycode/punycode.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:liza/config/app_config.dart';
import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/invite_link_parser.dart';
import 'package:liza/utils/message_link.dart';
import 'package:liza/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:liza/widgets/adaptive_dialogs/user_dialog.dart';
import 'package:liza/widgets/future_loading_dialog.dart';
import 'package:liza/widgets/matrix.dart';
import '../widgets/adaptive_dialogs/public_room_dialog.dart';
import 'platform_infos.dart';

class UrlLauncher {
  /// The url to open.
  final String? url;

  /// The visible name in the GUI. For example the name of a markdown link
  /// which may differ from the actual url to open.
  final String? name;

  final BuildContext context;

  const UrlLauncher(this.context, this.url, [this.name]);

  void launchUrl() async {
    if (url!.toLowerCase().startsWith(AppConfig.deepLinkPrefix) ||
        url!.toLowerCase().startsWith(AppConfig.inviteLinkPrefix) ||
        {'#', '@', '!', '+', '\$'}.contains(url![0]) ||
        url!.toLowerCase().startsWith(AppConfig.schemePrefix)) {
      return openMatrixToUrl();
    }
    final uri = Uri.tryParse(url!);
    if (uri == null) {
      // we can't open this thing
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).cantOpenUri(url!))),
      );
      return;
    }

    // Ссылка на канал/сторис/инвайт Liza (`me.liza.ru/c|s|i/…`) — открываем
    // ВНУТРИ приложения, а не во внешнем браузере. Без этого тап по ссылке в
    // сообщении уходил в `launchUrlString(externalApplication)`, и ОС
    // показывала «Поделиться» вместо канала ([[RL-channel-link-open-internal]]).
    // Проверка ДО consent-диалога ниже: для собственной ссылки диалог «открыть
    // в браузере» не нужен. Хост ограничен `_isShortLinkHost` — чужие https не
    // перехватываем.
    final internalRoute = resolveInternalRoute(uri);
    if (internalRoute != null) {
      if (!context.mounted) return;
      context.go(internalRoute);
      return;
    }

    if (name != null && url != name) {
      // If there is a name which differs from the url, we need to make sure
      // that the user can see the actual url before opening the browser.
      final consent = await showOkCancelAlertDialog(
        context: context,
        title: L10n.of(context).openLinkInBrowser,
        message: url,
        okLabel: L10n.of(context).open,
        cancelLabel: L10n.of(context).cancel,
      );
      if (consent != OkCancelResult.ok) return;
    }

    if (!{'https', 'http'}.contains(uri.scheme)) {
      // just launch non-https / non-http uris directly

      // we need to transmute geo URIs on desktop and on iOS
      if ((!PlatformInfos.isMobile || PlatformInfos.isIOS) &&
          uri.scheme == 'geo') {
        final latlong = uri.path
            .split(';')
            .first
            .split(',')
            .map((s) => double.tryParse(s))
            .toList();
        if (latlong.length == 2 &&
            latlong.first != null &&
            latlong.last != null) {
          if (PlatformInfos.isIOS) {
            // iOS is great at not following standards, so we need to transmute the geo URI
            // to an apple maps thingy
            // https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/MapLinks/MapLinks.html
            final ll = '${latlong.first},${latlong.last}';
            launchUrlString('https://maps.apple.com/?q=$ll&sll=$ll');
          } else {
            // transmute geo URIs on desktop to openstreetmap links, as those usually can't handle
            // geo URIs
            launchUrlString(
              'https://www.openstreetmap.org/?mlat=${latlong.first}&mlon=${latlong.last}#map=16/${latlong.first}/${latlong.last}',
            );
          }
          return;
        }
      }
      launchUrlString(url!);
      return;
    }
    if (uri.host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).cantOpenUri(url!))),
      );
      return;
    }
    // okay, we have either an http or an https URI.
    // As some platforms have issues with opening unicode URLs, we are going to help
    // them out by punycode-encoding them for them ourself.
    final newHost = uri.host
        .split('.')
        .map((hostPartEncoded) {
          final hostPart = Uri.decodeComponent(hostPartEncoded);
          final hostPartPunycode = punycodeEncode(hostPart);
          return hostPartPunycode != '$hostPart-'
              ? 'xn--$hostPartPunycode'
              : hostPart;
        })
        .join('.');
    // Force LaunchMode.externalApplication, otherwise url_launcher will default
    // to opening links in a webview on mobile platforms.
    launchUrlString(
      uri.replace(host: newHost).toString(),
      mode: LaunchMode.externalApplication,
    );
  }

  void openMatrixToUrl() async {
    final matrix = Matrix.of(context);
    final url = this.url!.replaceFirst(
      AppConfig.deepLinkPrefix,
      AppConfig.inviteLinkPrefix,
    );

    // The identifier might be a matrix.to url and needs escaping. Or, it might have multiple
    // identifiers (room id & event id), or it might also have a query part.
    // All this needs parsing.
    final identityParts =
        url.parseIdentifierIntoParts() ??
        Uri.tryParse(url)?.host.parseIdentifierIntoParts() ??
        Uri.tryParse(url)?.pathSegments
            .lastWhereOrNull((_) => true)
            ?.parseIdentifierIntoParts();
    if (identityParts == null) {
      return; // no match, nothing to do
    }
    if (identityParts.primaryIdentifier.sigil == '#' ||
        identityParts.primaryIdentifier.sigil == '!') {
      // we got a room! Let's open that one
      final roomIdOrAlias = identityParts.primaryIdentifier;
      final event = identityParts.secondaryIdentifier;
      var room =
          matrix.client.getRoomByAlias(roomIdOrAlias) ??
          matrix.client.getRoomById(roomIdOrAlias);
      var roomId = room?.id;
      // we make the servers a set and later on convert to a list, so that we can easily
      // deduplicate servers added via alias lookup and query parameter
      final servers = <String>{};
      if (room == null && roomIdOrAlias.sigil == '#') {
        // we were unable to find the room locally...so resolve it
        final response = await showFutureLoadingDialog(
          context: context,
          future: () => matrix.client.getRoomIdByAlias(roomIdOrAlias),
        );
        if (response.error != null) {
          return; // nothing to do, the alias doesn't exist
        }
        roomId = response.result!.roomId;
        servers.addAll(response.result!.servers!);
        room = matrix.client.getRoomById(roomId!);
      }
      servers.addAll(identityParts.via);
      switch (matrixToOpenAction(
        roomKnownLocally: room != null,
        sigil: roomIdOrAlias.sigil,
      )) {
        case MatrixToOpenAction.openRoom:
          if (room!.isSpace) {
            // TODO: Implement navigate to space
            context.go('/rooms/${room.id}');
            return;
          }
          // Комната у нас есть (участник или приглашённый) — открываем; для
          // ссылки на сообщение скроллим к событию.
          context.go(roomEventPath(room.id, event));
          return;
        case MatrixToOpenAction.publicPreview:
          // `#alias`, которого нет локально: превью публичной/knock-комнаты из
          // directory. eventId прокидываем, чтобы после входа открыть само
          // сообщение (иначе терялся — попадали в начало чата).
          if (!context.mounted) return;
          await showAdaptiveDialog(
            context: context,
            builder: (c) => PublicRoomDialog(
              roomAlias: roomIdOrAlias,
              via: servers.isNotEmpty ? servers.toList() : null,
              navigateEventId: event,
            ),
          );
          return;
        case MatrixToOpenAction.notMemberInfo:
          // `!roomId` у не-участника. Наши ЧАТЫ invite-only (joinRoom
          // постороннего = M_FORBIDDEN) → комнату не показать. Peek сюда не
          // относится: он только для открытых КАНАЛОВ (world_readable), и они
          // открываются своей веткой через ChannelPeekPage.
          // Ссылка на сообщение — не приглашение: не предлагаем вступить, а
          // честно сообщаем, что доступа нет (LABA-2217).
          if (!context.mounted) return;
          await showOkAlertDialog(
            context: context,
            title: L10n.of(context).youAreNotInThisChat,
            message: L10n.of(context).youAreNotInThisChatMessage,
            okLabel: L10n.of(context).ok,
          );
          return;
      }
    } else if (identityParts.primaryIdentifier.sigil == '@') {
      final userId = identityParts.primaryIdentifier;
      var noProfileWarning = false;
      final profileResult = await showFutureLoadingDialog(
        context: context,
        future: () =>
            matrix.client.getProfileFromUserId(userId).catchError((_) {
              noProfileWarning = true;
              return Profile(userId: userId);
            }),
      );
      await UserDialog.show(
        context: context,
        profile: profileResult.result!,
        noProfileWarning: noProfileWarning,
      );
    }
  }
}
