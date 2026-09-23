import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:liza/utils/custom_http_client.dart';

enum AccessLevel { admin, moderator, user }

AccessLevel accessLevelFromCode(String? code) => switch (code) {
      'admin' => AccessLevel.admin,
      'moderator' => AccessLevel.moderator,
      _ => AccessLevel.user,
    };

class DossierEntry {
  final String roomId;
  final String? name;
  final String? avatar;
  final AccessLevel level;

  const DossierEntry({
    required this.roomId,
    this.name,
    this.avatar,
    required this.level,
  });

  factory DossierEntry.fromJson(Map<String, dynamic> json) => DossierEntry(
        roomId: json['room_id'] as String,
        name: json['name'] as String?,
        avatar: json['avatar'] as String?,
        level: accessLevelFromCode(json['level'] as String?),
      );
}

class ElevatedRoom {
  final String roomId;
  final String? name;
  final int powerLevel;
  final String group;

  const ElevatedRoom({
    required this.roomId,
    this.name,
    required this.powerLevel,
    required this.group,
  });

  factory ElevatedRoom.fromJson(Map<String, dynamic> json) => ElevatedRoom(
        roomId: json['room_id'] as String,
        name: json['name'] as String?,
        powerLevel: json['power_level'] as int? ?? 0,
        group: json['group'] as String? ?? 'chat',
      );
}

class SpaceMember {
  final String userId;
  final String? membershipInSpace;
  final int maxPowerLevel;
  final List<ElevatedRoom> elevatedRooms;

  const SpaceMember({
    required this.userId,
    this.membershipInSpace,
    required this.maxPowerLevel,
    required this.elevatedRooms,
  });

  factory SpaceMember.fromJson(Map<String, dynamic> json) {
    final raw = json['elevated_rooms'];
    return SpaceMember(
      userId: json['user_id'] as String,
      membershipInSpace: json['membership_in_space'] as String?,
      maxPowerLevel: json['max_power_level'] as int? ?? 0,
      elevatedRooms: raw is List
          ? raw
              .whereType<Map<String, dynamic>>()
              .map(ElevatedRoom.fromJson)
              .toList()
          : const [],
    );
  }
}

class AccessDossier {
  final String? displayName;
  final bool deactivated;
  final bool isLocal;
  final String serverName;
  final String? roleLabel;
  final List<DossierEntry> spaces;
  final List<DossierEntry> channels;
  final List<DossierEntry> chats;
  final List<DossierEntry> bots;

  const AccessDossier({
    this.displayName,
    required this.deactivated,
    required this.isLocal,
    required this.serverName,
    this.roleLabel,
    required this.spaces,
    required this.channels,
    required this.chats,
    required this.bots,
  });

  static List<DossierEntry> _entries(dynamic raw) => raw is List
      ? raw
          .whereType<Map<String, dynamic>>()
          .map(DossierEntry.fromJson)
          .toList()
      : const [];

  factory AccessDossier.fromJson(Map<String, dynamic> json) {
    final server = json['server'];
    final serverMap = server is Map<String, dynamic> ? server : const {};
    final role = serverMap['role'];
    return AccessDossier(
      displayName: json['display_name'] as String?,
      deactivated: json['deactivated'] as bool? ?? false,
      isLocal: json['is_local'] as bool? ?? false,
      serverName: serverMap['name'] as String? ?? '',
      roleLabel: role is Map<String, dynamic> ? role['label'] as String? : null,
      spaces: _entries(json['spaces']),
      channels: _entries(json['channels']),
      chats: _entries(json['chats']),
      bots: _entries(json['bots']),
    );
  }
}

/// Клиент привилегированных операций управления доступами.
///
/// В отличие от UserRoleService ошибки НЕ глотаются: вызовы-мутации должны
/// падать, иначе showFutureLoadingDialog покажет успех при неудаче.
class AccessAdminService {
  final Client Function() activeClient;
  final http.Client _httpClient;

  static const String _base = '/_synapse/client/access/v1';
  static const Duration _timeout = Duration(seconds: 15);

  AccessAdminService(this.activeClient)
      : _httpClient = CustomHttpClient.createHTTPClient();

  Uri _uri(String path) {
    final client = activeClient();
    final homeserver = client.homeserver;
    if (homeserver == null) {
      throw StateError('Нет активного homeserver');
    }
    return homeserver.replace(path: '$_base$path');
  }

  Map<String, String> _headers() {
    final token = activeClient().accessToken;
    if (token == null) {
      throw StateError('Нет access token');
    }
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Never _throwFor(http.Response response) {
    var message = response.body;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['message'] is String) {
        message = decoded['message'] as String;
      }
    } catch (_) {
      // тело не JSON — отдаём как есть
    }
    throw Exception(message);
  }

  Future<AccessDossier> fetchDossier(String userId) async {
    final response = await _httpClient
        .get(_uri('/dossier/$userId'), headers: _headers())
        .timeout(_timeout);
    if (response.statusCode != 200) {
      _throwFor(response);
    }
    return AccessDossier.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<List<SpaceMember>> fetchSpaceMembers(String spaceId) async {
    final response = await _httpClient
        .get(
          _uri('/space_members/${Uri.encodeComponent(spaceId)}'),
          headers: _headers(),
        )
        .timeout(_timeout);
    if (response.statusCode != 200) {
      _throwFor(response);
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final raw = data['members'];
    return raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map(SpaceMember.fromJson)
            .toList()
        : const [];
  }

  /// Возвращает актуальный флаг deactivated после операции.
  Future<bool> setActive(String userId, {required bool active}) async {
    final path = active ? '/reactivate/$userId' : '/deactivate/$userId';
    final response = await _httpClient
        .post(_uri(path), headers: _headers())
        .timeout(_timeout);
    if (response.statusCode != 200) {
      _throwFor(response);
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['deactivated'] as bool? ?? !active;
  }

  void dispose() {
    _httpClient.close();
  }
}
