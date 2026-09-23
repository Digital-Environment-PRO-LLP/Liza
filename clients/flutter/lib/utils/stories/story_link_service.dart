import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:liza/config/app_config.dart';
import 'package:liza/utils/custom_http_client.dart';
import 'story_model.dart';

/// Короткие ссылки на сторисы через auth-proxy (`/invite/v1/story-links`).
/// По образцу [AuthProxyService] (тот же base host, Bearer accessToken).
class StoryLinkService {
  final http.Client _httpClient;

  static final Uri _baseUri = Uri.https(AppConfig.authProxyBaseUrl, '');

  StoryLinkService({http.Client? httpClient})
    : _httpClient = httpClient ?? CustomHttpClient.createHTTPClient();

  Map<String, String> _headers(String accessToken) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $accessToken',
  };

  /// POST /invite/v1/story-links — создать (идемпотентно) короткую ссылку.
  Future<String> createLink({
    required StoryRef ref,
    required String accessToken,
  }) async {
    final url = _baseUri.replace(path: '/invite/v1/story-links');
    final response = await _httpClient.post(
      url,
      headers: _headers(accessToken),
      body: jsonEncode({
        'room_id': ref.roomId,
        'event_id': ref.eventId,
        'author_mxid': ref.authorId,
        'expires_ts': ref.expiresTs,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'story link create failed: HTTP ${response.statusCode}',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['url'] as String;
  }

  /// GET /invite/v1/story-links/<code> — резолв кода. Null: не найден (404)
  /// или протух (410).
  Future<StoryRef?> resolveLink({
    required String code,
    required String accessToken,
  }) async {
    final url = _baseUri.replace(path: '/invite/v1/story-links/$code');
    final response = await _httpClient.get(url, headers: _headers(accessToken));
    if (response.statusCode == 404 || response.statusCode == 410) return null;
    if (response.statusCode != 200) {
      throw Exception(
        'story link resolve failed: HTTP ${response.statusCode}',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return StoryRef(
      roomId: json['room_id'] as String,
      eventId: json['event_id'] as String,
      authorId: json['author_mxid'] as String,
      expiresTs: json['expires_ts'] as int? ?? 0,
    );
  }
}
