import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

/// Описание одного listed-приложения из реестра miniApp.
class CatalogApp {
  final String appId;
  final String name;
  final String url;
  final String icon;

  /// 'first_party' (наш доверенный app) либо 'third_party' (стороннее).
  final String type;
  final String? shortDescription;

  CatalogApp({
    required this.appId,
    required this.name,
    required this.url,
    required this.icon,
    required this.type,
    this.shortDescription,
  });
}

/// Глобальный кэш реестра listed-приложений.
///
/// Тянет каталог из Synapse-модуля miniapp
/// (`GET /_synapse/client/miniapp/v1/apps`), кэширует в памяти на ~5 минут.
/// Singleton по образцу [MiniAppManager].
class MiniAppRegistry {
  MiniAppRegistry._();
  static final MiniAppRegistry instance = MiniAppRegistry._();

  static const Duration _ttl = Duration(minutes: 5);

  List<CatalogApp>? _cache;
  DateTime? _fetchedAt;

  /// Возвращает список listed-приложений.
  ///
  /// Использует кэш, если он свежий (TTL ~5 мин). `force=true` (pull-to-refresh)
  /// игнорирует кэш и всегда ходит в сеть.
  Future<List<CatalogApp>> fetch(Client client, {bool force = false}) async {
    if (!force && _cache != null && _fetchedAt != null) {
      if (DateTime.now().difference(_fetchedAt!) < _ttl) {
        return _cache!;
      }
    }

    final url = client.homeserver!.resolve(
      '/_synapse/client/miniapp/v1/apps',
    );
    final response = await http.get(
      url,
      headers: {
        // Bearer-токен для единообразия с остальными вызовами miniapp-модуля,
        // хотя список listed-приложений публичен.
        'Authorization': 'Bearer ${client.accessToken}',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('miniapp registry returned ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final apps = (data['apps'] as Map<String, dynamic>? ?? {});

    final result = <CatalogApp>[];
    apps.forEach((appId, raw) {
      if (raw is! Map) return;
      final name = raw['name'] as String?;
      final appUrl = raw['url'] as String?;
      if (name == null || appUrl == null) return;
      result.add(CatalogApp(
        appId: appId,
        name: name,
        url: appUrl,
        icon: raw['icon'] as String? ?? '',
        type: raw['type'] as String? ?? 'third_party',
        shortDescription: raw['short_description'] as String?,
      ));
    });

    _cache = result;
    _fetchedAt = DateTime.now();
    return result;
  }
}
