import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:liza/config/app_config.dart';
import 'package:liza/utils/custom_http_client.dart';

/// Response from GET /api/auth/login
class AuthLoginResponse {
  final String authorizationUrl;
  final String sessionState;

  const AuthLoginResponse({
    required this.authorizationUrl,
    required this.sessionState,
  });

  factory AuthLoginResponse.fromJson(Map<String, dynamic> json) =>
      AuthLoginResponse(
        authorizationUrl: json['authorization_url'] as String,
        sessionState: json['session_state'] as String,
      );
}

/// Response from POST /api/auth/select
class AuthTokenResponse {
  final String loginToken;
  final String serverName;
  final String userId;
  /// Возвращается backend'ом при polling invite-сессии (inviteCode),
  /// чтобы клиент мог вызвать redeemInvite после логина.
  final String? inviteCode;

  const AuthTokenResponse({
    required this.loginToken,
    required this.serverName,
    required this.userId,
    this.inviteCode,
  });

  factory AuthTokenResponse.fromJson(Map<String, dynamic> json) =>
      AuthTokenResponse(
        loginToken: json['login_token'] as String,
        serverName: json['server_name'] as String,
        userId: json['user_id'] as String,
        inviteCode: json['inviteCode'] as String?,
      );
}

/// A single account entry from the select response
class AuthAccount {
  final String serverName;
  final String localpart;
  final bool isDefault;

  const AuthAccount({
    required this.serverName,
    required this.localpart,
    required this.isDefault,
  });

  factory AuthAccount.fromJson(Map<String, dynamic> json) => AuthAccount(
        serverName: json['server_name'] as String,
        localpart: json['localpart'] as String,
        isDefault: json['is_default'] as bool? ?? false,
      );
}

/// Response from GET /api/auth/select
class AuthSelectListResponse {
  final List<AuthAccount> accounts;

  const AuthSelectListResponse({
    required this.accounts,
  });

  factory AuthSelectListResponse.fromJson(Map<String, dynamic> json) =>
      AuthSelectListResponse(
        accounts: (json['accounts'] as List)
            .map((e) => AuthAccount.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Response from POST /invite/v1/links
class InviteLinkInfo {
  final String code;
  final String url;
  final DateTime createdAt;
  final String createdByMxid;

  const InviteLinkInfo({
    required this.code,
    required this.url,
    required this.createdAt,
    required this.createdByMxid,
  });

  factory InviteLinkInfo.fromJson(Map<String, dynamic> j) => InviteLinkInfo(
        code: j['code'] as String,
        url: j['url'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
        createdByMxid: j['created_by_mxid'] as String,
      );
}

/// Ответ PUT /invite/v1/channels/handle
class ChannelHandleInfo {
  final String handle;
  final String url;

  const ChannelHandleInfo({required this.handle, required this.url});

  factory ChannelHandleInfo.fromJson(Map<String, dynamic> json) =>
      ChannelHandleInfo(
        handle: json['handle'] as String,
        url: json['url'] as String,
      );
}

/// Ответ GET /invite/v1/channels/\<handle\>
class ChannelHandleResolved {
  final String handle;
  final String roomId;
  final String serverName;
  final String? name;
  final String? avatarUrl;
  final int? membersCount;

  const ChannelHandleResolved({
    required this.handle,
    required this.roomId,
    required this.serverName,
    this.name,
    this.avatarUrl,
    this.membersCount,
  });

  factory ChannelHandleResolved.fromJson(Map<String, dynamic> json) =>
      ChannelHandleResolved(
        handle: json['handle'] as String,
        roomId: json['room_id'] as String,
        serverName: json['server_name'] as String,
        name: json['name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        membersCount: json['members_count'] as int?,
      );
}

/// Ник уже занят другим каналом (HTTP 409).
class ChannelHandleTakenException implements Exception {
  const ChannelHandleTakenException();

  @override
  String toString() => 'ChannelHandleTakenException';
}

/// Запись о заблокированном/удалённом участнике магазина.
/// GET `/invite/v1/rooms/<room_id>/blocks`
class MemberBlockInfo {
  final String mxid;

  /// 'banned' | 'removed' | 'invite_revoked'.
  final String status;
  final String? reason;
  final String? displayName;
  final String? blockedByMxid;
  final DateTime? createdAt;

  const MemberBlockInfo({
    required this.mxid,
    required this.status,
    this.reason,
    this.displayName,
    this.blockedByMxid,
    this.createdAt,
  });

  factory MemberBlockInfo.fromJson(Map<String, dynamic> j) => MemberBlockInfo(
        mxid: j['mxid'] as String,
        status: j['status'] as String? ?? 'removed',
        reason: j['reason'] as String?,
        displayName: j['display_name'] as String?,
        blockedByMxid: j['blocked_by_mxid'] as String?,
        createdAt: j['created_at'] != null
            ? DateTime.tryParse(j['created_at'] as String)
            : null,
      );
}

/// Response from POST /invite/v1/links/<code>/redeem
class InviteRedeemResult {
  final String status;
  final String? roomId;
  final String? serverName;
  final String? inviteCode;
  final String? targetUserId;

  /// Семантический тип таргета: 'contact' | 'space' | 'group' | 'dm'.
  /// Может быть null для старых ссылок — тогда тип определяется локально.
  final String? targetKind;

  /// Поля mini-app-инвайта (status == 'miniapp_invite'). Ссылка ведёт не в
  /// общую комнату, а на ПРИЛОЖЕНИЕ: клиент сигналит боту, тот заводит
  /// персональный чат приложения для текущего пользователя.
  final String? appId;
  final String? appUrl;
  final String? appName;
  final String? appType;

  /// Deep-link на конкретную страницу mini App из самой ссылки (например
  /// `#!/tproduct/123`). null — ссылка на главную приложения.
  final String? appStartPath;

  /// Комната-лаунчер ВЛАДЕЛЬЦА (серверный якорь резолва мерчанта в боте).
  /// Клиент лишь ретранслирует его боту в сигнале miniapp_created — нужен для
  /// релея «Входящие» (переписка клиента доходит владельцу). НЕ выбор клиента.
  final String? ownerRoomId;

  const InviteRedeemResult({
    required this.status,
    this.roomId,
    this.serverName,
    this.inviteCode,
    this.targetUserId,
    this.targetKind,
    this.appId,
    this.appUrl,
    this.appName,
    this.appType,
    this.appStartPath,
    this.ownerRoomId,
  });

  factory InviteRedeemResult.fromJson(Map<String, dynamic> j) =>
      InviteRedeemResult(
        status: j['status'] as String,
        roomId: j['room_id'] as String?,
        serverName: j['server_name'] as String?,
        inviteCode: j['invite_code'] as String?,
        targetUserId: j['target_user_id'] as String?,
        targetKind: j['target_kind'] as String?,
        appId: j['app_id'] as String?,
        appUrl: j['app_url'] as String?,
        appName: j['app_name'] as String?,
        appType: j['app_type'] as String?,
        appStartPath: j['app_start_path'] as String?,
        ownerRoomId: j['owner_room_id'] as String?,
      );
}

/// Parsed callback data from the auth proxy redirect URI
class AuthCallbackData {
  final String action;
  final String? loginToken;
  final String? serverName;
  final String? userId;
  final String? sessionState;
  final String? error;
  /// room_id из invite_action — приходит только для invite-сессий
  /// через deep-link (camelCase inviteRoomId или snake_case invite_room_id).
  final String? inviteRoomId;

  const AuthCallbackData({
    required this.action,
    this.loginToken,
    this.serverName,
    this.userId,
    this.sessionState,
    this.error,
    this.inviteRoomId,
  });

  factory AuthCallbackData.fromUri(Uri uri) {
    final params = uri.queryParameters;
    return AuthCallbackData(
      action: params['action'] ?? 'error',
      // Support both camelCase and snake_case from the backend redirect URL
      loginToken: params['loginToken'] ?? params['login_token'],
      serverName: params['serverName'] ?? params['server_name'],
      userId: params['userId'] ?? params['user_id'],
      sessionState: params['session_state'],
      error: params['error'],
      inviteRoomId: params['inviteRoomId'] ?? params['invite_room_id'],
    );
  }
}

/// Exception from auth proxy API calls
class AuthProxyException implements Exception {
  final String message;
  final int? statusCode;
  final String? body;

  AuthProxyException(this.message, {this.statusCode, this.body});

  String? get serverError {
    if (body == null) return null;
    try {
      final json = jsonDecode(body!) as Map<String, dynamic>;
      return json['error'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Whether this error indicates a persistent server-side problem
  /// that will not resolve by retrying (e.g. invalid admin token).
  bool get isNonTransient {
    final code = statusCode;
    if (code == null) return false;
    if (code == 401 || code == 403) return true;
    if (code == 502 || code == 500) {
      final err = (serverError ?? body ?? '').toLowerCase();
      if (err.contains('unknown_token') ||
          err.contains('m_unknown_token') ||
          (err.contains('invalid') && err.contains('token')) ||
          err.contains('puppet')) {
        return true;
      }
    }
    return false;
  }

  @override
  String toString() =>
      serverError ?? 'AuthProxyException: $message (status: $statusCode)';
}

/// A non-transient server-side error from the auth proxy that the client
/// cannot resolve by retrying (e.g. invalid Synapse admin token).
class AuthProxyServerException implements Exception {
  final String serverError;
  final int? statusCode;

  const AuthProxyServerException({
    required this.serverError,
    this.statusCode,
  });

  @override
  String toString() =>
      'AuthProxyServerException: $serverError (HTTP $statusCode)';
}

/// Service for interacting with the auth proxy JSON API.
class AuthProxyService {
  final http.Client _httpClient;

  static final Uri _baseUri = Uri.https(AppConfig.authProxyBaseUrl, '');

  AuthProxyService({http.Client? httpClient})
      : _httpClient = httpClient ?? CustomHttpClient.createHTTPClient();

  Map<String, dynamic> _decodeResponse(http.Response response) {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      if (response.statusCode != 200) {
        throw AuthProxyException(
          'Server error (HTTP ${response.statusCode})',
          statusCode: response.statusCode,
          body: response.body,
        );
      }
      rethrow;
    }
    if (response.statusCode != 200) {
      throw AuthProxyException(
        body['error'] as String? ?? 'Request failed',
        statusCode: response.statusCode,
        body: response.body,
      );
    }
    return body;
  }

  /// Step 1: Initiate OIDC session, get authorization URL.
  /// GET /api/auth/login?return_url=...&invite_code=... (invite_code опционально)
  Future<AuthLoginResponse> initiateLogin(
    String redirectUrl, {
    String? inviteCode,
  }) async {
    final queryParameters = {'return_url': redirectUrl};
    if (inviteCode != null) {
      queryParameters['invite_code'] = inviteCode;
    }
    final url = _baseUri.replace(
      path: '/api/auth/login',
      queryParameters: queryParameters,
    );
    Logs().i('[AuthProxy] Initiating login: $url');
    final sw = Stopwatch()..start();
    final response = await _httpClient.get(url);
    Logs().i(
      '[AuthProxy] initiateLogin: ${response.statusCode} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    final body = _decodeResponse(response);
    return AuthLoginResponse.fromJson(body);
  }

  /// Step 1 of registration: get ProdamusID registration URL.
  /// GET /api/auth/registration?return_url=...
  ///
  /// Симметричен [initiateLogin] — после регистрации ProdamusID редиректит
  /// на тот же `liza://auth/callback`, поэтому остальной флоу (callback,
  /// polling) переиспользует логиновскую инфраструктуру. Если сервер не
  /// настроен на регистрацию (нет registration_endpoint в конфиге) —
  /// вернёт 501, и клиент должен откатиться на legacy-флоу.
  Future<AuthLoginResponse> initiateRegistration(
    String redirectUrl, {
    String? inviteCode,
  }) async {
    final queryParameters = {'return_url': redirectUrl};
    if (inviteCode != null) {
      queryParameters['invite_code'] = inviteCode;
    }
    final url = _baseUri.replace(
      path: '/api/auth/registration',
      queryParameters: queryParameters,
    );
    Logs().i('[AuthProxy] Initiating registration: $url');
    final sw = Stopwatch()..start();
    final response = await _httpClient.get(url);
    Logs().i(
      '[AuthProxy] initiateRegistration: ${response.statusCode} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    final body = _decodeResponse(response);
    return AuthLoginResponse.fromJson(body);
  }

  /// Get list of accounts for server selection.
  /// GET /api/auth/select?session_state=...
  Future<AuthSelectListResponse> getAccounts({
    required String sessionState,
  }) async {
    final url = _baseUri.replace(
      path: '/api/auth/select',
      queryParameters: {'session_state': sessionState},
    );
    Logs().i('[AuthProxy] Fetching accounts');
    final sw = Stopwatch()..start();
    final response = await _httpClient.get(url);
    Logs().i(
      '[AuthProxy] getAccounts: ${response.statusCode} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    final body = _decodeResponse(response);
    return AuthSelectListResponse.fromJson(body);
  }

  /// Poll session status. Returns raw JSON map.
  /// GET /api/auth/status?session_state=...
  Future<Map<String, dynamic>> getStatus({
    required String sessionState,
  }) async {
    final url = _baseUri.replace(
      path: '/api/auth/status',
      queryParameters: {'session_state': sessionState},
    );
    final sw = Stopwatch()..start();
    final response = await _httpClient.get(url);
    Logs().v(
      '[AuthProxy] getStatus: ${response.statusCode} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    return _decodeResponse(response);
  }

  /// Request a fresh login token for an already-completed session.
  /// POST /api/auth/refresh_token
  Future<AuthTokenResponse> refreshToken({
    required String sessionState,
  }) async {
    final url = _baseUri.replace(path: '/api/auth/refresh_token');
    Logs().i('[AuthProxy] Refreshing token for session');
    final sw = Stopwatch()..start();
    final response = await _httpClient.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'session_state': sessionState}),
    );
    Logs().i(
      '[AuthProxy] refreshToken: ${response.statusCode} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    final body = _decodeResponse(response);
    return AuthTokenResponse.fromJson(body);
  }

  /// Select an account/server to log in.
  /// POST /api/auth/select
  Future<AuthTokenResponse> selectAccount({
    required String sessionState,
    required String serverName,
  }) async {
    final url = _baseUri.replace(path: '/api/auth/select');
    Logs().i('[AuthProxy] Selecting server: $serverName');
    final sw = Stopwatch()..start();
    final response = await _httpClient.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'session_state': sessionState,
        'server_name': serverName,
      }),
    );
    Logs().i(
      '[AuthProxy] selectAccount: ${response.statusCode} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    final body = _decodeResponse(response);
    return AuthTokenResponse.fromJson(body);
  }

  /// POST /invite/v1/links — create or get invite link for room.
  ///
  /// [appStartPath] — опциональный deep-link на конкретную страницу mini App
  /// (`#!/tproduct/123`): ссылка ведёт redeemer'а сразу на неё. Ссылки на разные
  /// страницы одной комнаты-лаунчера не переиспользуются (отдельный code).
  Future<InviteLinkInfo> createInvite({
    required String serverName,
    required String roomId,
    required String accessToken,
    String? appStartPath,
  }) async {
    final url = _baseUri.replace(path: '/invite/v1/links');
    Logs().i('[AuthProxy] createInvite: room=$roomId server=$serverName');
    final sw = Stopwatch()..start();
    final response = await _httpClient.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        'server_name': serverName,
        'room_id': roomId,
        if (appStartPath != null && appStartPath.isNotEmpty)
          'app_start_path': appStartPath,
      }),
    );
    Logs().i(
      '[AuthProxy] createInvite: ${response.statusCode} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    final body = _decodeResponse(response);
    return InviteLinkInfo.fromJson(body);
  }

  /// POST /invite/v1/links — create or get user-invite (DM target).
  Future<InviteLinkInfo> createUserInvite({
    required String targetUserId,
    required String accessToken,
  }) async {
    final separator = targetUserId.indexOf(':');
    if (!targetUserId.startsWith('@') ||
        separator <= 1 ||
        separator == targetUserId.length - 1) {
      throw ArgumentError.value(
        targetUserId,
        'targetUserId',
        'Expected a Matrix user ID such as @user:homeserver',
      );
    }
    final targetServerName = targetUserId.substring(separator + 1);
    final url = _baseUri.replace(path: '/invite/v1/links');
    Logs().i('[AuthProxy] createUserInvite: target=$targetUserId');
    final sw = Stopwatch()..start();
    final response = await _httpClient.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        // Источник истины — homeserver цели, а не текущего аккаунта. Иначе
        // cross-HS контакт сохранялся с несовместимой парой server/user MXID.
        'server_name': targetServerName,
        'target_type': 'user',
        'target_user_id': targetUserId,
      }),
    );
    Logs().i(
      '[AuthProxy] createUserInvite: ${response.statusCode} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    final body = _decodeResponse(response);
    return InviteLinkInfo.fromJson(body);
  }

  /// POST /contacts/v1/lookup — какие из номеров книги уже есть в Liza.
  ///
  /// Отдаёт map: отправленный номер (в том же виде, как передан) -> mxid, ТОЛЬКО
  /// для совпадений. Несовпавшие номера в ответе отсутствуют (сервер их не
  /// подтверждает). См. howItWoks/addContacts.md.
  Future<Map<String, String>> lookupContacts({
    required List<String> phones,
    required String accessToken,
  }) async {
    final url = _baseUri.replace(path: '/contacts/v1/lookup');
    Logs().i('[AuthProxy] lookupContacts: ${phones.length} phones');
    final response = await _httpClient.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({'phones': phones}),
    );
    final body = _decodeResponse(response);
    final matches = (body['matches'] as List?) ?? const [];
    final result = <String, String>{};
    for (final m in matches) {
      if (m is Map<String, dynamic>) {
        final phone = m['phone'] as String?;
        final mxid = m['mxid'] as String?;
        if (phone != null && mxid != null) result[phone] = mxid;
      }
    }
    return result;
  }

  /// POST /invite/v1/links/<code>/redeem — apply invite for current user.
  Future<InviteRedeemResult> redeemInvite({
    required String code,
    required String accessToken,
  }) async {
    final url = _baseUri.replace(path: '/invite/v1/links/$code/redeem');
    Logs().i('[AuthProxy] redeemInvite: code=${_codePreview(code)}');
    final sw = Stopwatch()..start();
    final response = await _httpClient.post(
      url,
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    Logs().i(
      '[AuthProxy] redeemInvite: ${response.statusCode} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    final body = _decodeResponse(response);
    return InviteRedeemResult.fromJson(body);
  }

  /// POST /invite/v1/links/<code>/revoke — revoke invite link.
  Future<void> revokeInvite({
    required String code,
    required String accessToken,
  }) async {
    final url = _baseUri.replace(path: '/invite/v1/links/$code/revoke');
    Logs().i('[AuthProxy] revokeInvite: code=${_codePreview(code)}');
    final sw = Stopwatch()..start();
    final response = await _httpClient.post(
      url,
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    Logs().i(
      '[AuthProxy] revokeInvite: ${response.statusCode} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    _decodeResponse(response); // throws on non-200
  }

  /// PUT /invite/v1/channels/handle — занять или сменить ник канала.
  ///
  /// Бросает [ChannelHandleTakenException] если ник занят другим каналом.
  Future<ChannelHandleInfo> setChannelHandle({
    required String serverName,
    required String roomId,
    required String handle,
    required String accessToken,
  }) async {
    final url = _baseUri.replace(path: '/invite/v1/channels/handle');
    Logs().i('[AuthProxy] setChannelHandle: room=$roomId handle=$handle');
    final sw = Stopwatch()..start();
    final response = await _httpClient.put(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        'server_name': serverName,
        'room_id': roomId,
        'handle': handle,
      }),
    );
    Logs().i(
      '[AuthProxy] setChannelHandle: ${response.statusCode} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    if (response.statusCode == 409) {
      throw const ChannelHandleTakenException();
    }
    final body = _decodeResponse(response);
    return ChannelHandleInfo.fromJson(body);
  }

  /// DELETE /invite/v1/channels/handle — освободить ник канала.
  Future<void> deleteChannelHandle({
    required String serverName,
    required String roomId,
    required String accessToken,
  }) async {
    final url = _baseUri.replace(path: '/invite/v1/channels/handle');
    Logs().i('[AuthProxy] deleteChannelHandle: room=$roomId');
    final response = await _httpClient.delete(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({'server_name': serverName, 'room_id': roomId}),
    );
    _decodeResponse(response);
  }

  /// GET /invite/v1/channels/\<handle\> — публичный резолв ника.
  ///
  /// Возвращает `null` если ник свободен ИЛИ канал непубличный (сервер в обоих
  /// случаях отвечает 404 — приватный канал наружу не раскрывается).
  Future<ChannelHandleResolved?> resolveChannelHandle(String handle) async {
    final url = _baseUri.replace(path: '/invite/v1/channels/$handle');
    final sw = Stopwatch()..start();
    final response = await _httpClient.get(url);
    Logs().v(
      '[AuthProxy] resolveChannelHandle: ${response.statusCode} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    if (response.statusCode == 404) return null;
    final body = _decodeResponse(response);
    return ChannelHandleResolved.fromJson(body);
  }

  /// GET /invite/v1/channels/by-room — ник канала по room_id.
  ///
  /// Нужен экрану настроек: он знает комнату, но не ник. Отдаёт ник и для
  /// частного канала (владелец обязан видеть свой занятый адрес).
  Future<ChannelHandleInfo?> resolveChannelHandleForRoom({
    required String serverName,
    required String roomId,
    required String accessToken,
  }) async {
    final url = _baseUri.replace(
      path: '/invite/v1/channels/by-room',
      queryParameters: {'server_name': serverName, 'room_id': roomId},
    );
    Logs().i('[AuthProxy] resolveChannelHandleForRoom: room=$roomId');
    final sw = Stopwatch()..start();
    final response = await _httpClient.get(
      url,
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    Logs().v(
      '[AuthProxy] resolveChannelHandleForRoom: ${response.statusCode} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    if (response.statusCode == 404) return null;
    final body = _decodeResponse(response);
    return ChannelHandleInfo.fromJson(body);
  }

  /// `GET /invite/v1/rooms/<room_id>/blocks` — список заблокированных/удалённых
  /// участников магазина (источник истины статуса + гейт повторного redeem).
  Future<List<MemberBlockInfo>> listMemberBlocks({
    required String serverName,
    required String roomId,
    required String accessToken,
  }) async {
    final url = _baseUri.replace(
      path: '/invite/v1/rooms/${Uri.encodeComponent(roomId)}/blocks',
      queryParameters: {'server_name': serverName},
    );
    final response = await _httpClient.get(
      url,
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    final body = _decodeResponse(response);
    final blocks = (body['blocks'] as List? ?? [])
        .map((e) => MemberBlockInfo.fromJson(e as Map<String, dynamic>))
        .toList();
    return blocks;
  }

  /// `POST /invite/v1/rooms/<room_id>/blocks` — занести участника в blocklist.
  /// [status] — 'banned' | 'removed' | 'invite_revoked'.
  Future<void> blockMember({
    required String serverName,
    required String roomId,
    required String mxid,
    required String status,
    required String accessToken,
    String? reason,
    String? displayName,
  }) async {
    final url = _baseUri.replace(
      path: '/invite/v1/rooms/${Uri.encodeComponent(roomId)}/blocks',
    );
    final response = await _httpClient.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        'server_name': serverName,
        'mxid': mxid,
        'status': status,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
        if (displayName != null && displayName.isNotEmpty)
          'display_name': displayName,
      }),
    );
    _decodeResponse(response); // throws on non-200
  }

  /// `POST /invite/v1/rooms/<room_id>/blocks/unblock` — снять блокировку.
  Future<void> unblockMember({
    required String serverName,
    required String roomId,
    required String mxid,
    required String accessToken,
  }) async {
    final url = _baseUri.replace(
      path: '/invite/v1/rooms/${Uri.encodeComponent(roomId)}/blocks/unblock',
    );
    final response = await _httpClient.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({'server_name': serverName, 'mxid': mxid}),
    );
    _decodeResponse(response); // throws on non-200
  }

  String _codePreview(String code) {
    // Не светим полный код в логах: только первые 4 символа.
    return code.length <= 6 ? code : '${code.substring(0, 4)}...';
  }
}
