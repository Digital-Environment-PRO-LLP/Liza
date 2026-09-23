import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/date_time_extension.dart';

IconData _getIconFromName(String displayname) {
  final name = displayname.toLowerCase();
  if ({'android'}.any((s) => name.contains(s))) {
    return Icons.phone_android_outlined;
  }
  if ({'ios', 'ipad', 'iphone', 'ipod'}.any((s) => name.contains(s))) {
    return Icons.phone_iphone_outlined;
  }
  if ({
    'web',
    'http://',
    'https://',
    'firefox',
    'chrome',
    '/_matrix',
    'safari',
    'opera',
  }.any((s) => name.contains(s))) {
    return Icons.web_outlined;
  }
  if ({
    'desktop',
    'windows',
    'macos',
    'linux',
    'ubuntu',
  }.any((s) => name.contains(s))) {
    return Icons.desktop_mac_outlined;
  }
  return Icons.device_unknown_outlined;
}

extension DeviceExtension on Device {
  /// Имя сеанса для показа пользователю. Имя устройства задаёт клиент при
  /// логине, но сеанс может прийти и без него (например, создан регистрацией
  /// на сервере) — тогда показываем локализованную заглушку, не литерал.
  String localizedName(BuildContext context) =>
      (displayName?.isNotEmpty ?? false)
      ? displayName!
      : L10n.of(context).unknownDevice;

  /// Подпись сеанса: время последней активности либо, если сервер его не
  /// прислал, — идентификатор устройства.
  ///
  /// `last_seen_ts` в спеке Matrix необязателен, а Synapse заполняет его лишь
  /// отложенным батчем `client_ips` — поэтому у свежих и у ни разу не
  /// использованных сеансов он приходит `null`. Подставлять сюда epoch (0) и
  /// печатать «1 янв. 1970 г.» нельзя (LABA-2546): клиент не знает, когда
  /// сеанс был активен, и не должен это выдумывать. `deviceId` — единственное
  /// поле, которое есть всегда, и оно помогает отличить сеансы друг от друга.
  String lastSeenLabel(BuildContext context) {
    final ts = lastSeenTs;
    if (ts == null || ts <= 0) return deviceId;
    return L10n.of(
      context,
    ).lastActiveAgo(DateTime.fromMillisecondsSinceEpoch(ts).localizedTimeShort(context));
  }

  /// Иконка платформы считается по СЫРОМУ имени от клиента («Liza android»),
  /// а не по локализованному: иначе выбор иконки поехал бы за языком интерфейса.
  IconData get icon => _getIconFromName(displayName ?? '');
}
