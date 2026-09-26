import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:liza/config/app_config.dart';

/// Клиент входа по телефону и email (`/api/auth/*`).
///
/// Ходит ТОЛЬКО в auth-proxy: Admin API Keycloak отклоняет браузерные
/// запросы (`Invalid origin`), а сервис OTP не отдаёт CORS. Секреты
/// остаются на сервере.
class DemoAuthService {
  DemoAuthService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri _uri(String path, {bool absolutePath = false}) => Uri.https(
        AppConfig.authProxyBaseUrl,
        absolutePath ? '/api$path' : '/api/auth$path',
      );

  /// Шаг 1: заказ кода на телефон.
  ///
  /// [ticket] — повтор отправки на том же тикете (кнопка «СМС не пришло»):
  /// без него сервер каждый раз заводит новый тикет, и лимит повторов
  /// (`resend_limit_reached`) не срабатывает.
  ///
  /// [channel] — явный выбор канала доставки («Другой способ»). Сервер
  /// решает сам, когда параметр не задан.
  Future<DemoAuthStartResult> startPhone(
    String phone, {
    String? ticket,
    String? channel,
  }) async {
    final body = await _post('/phone/start', {
      'phone': phone,
      if (ticket != null) 'ticket': ticket,
      if (channel != null) 'channel': channel,
    });
    return DemoAuthStartResult(
      ticket: body['ticket'] as String,
      maskedDestination: body['masked_destination'] as String? ?? '',
      deliveryFailed: body['delivery_failed'] as bool? ?? false,
      channel: body['channel'] as String? ?? 'phone',
      deliveryError: body['delivery_error'] as String? ?? '',
      deliveryDetail: body['delivery_detail'] as String? ?? '',
      deliveryDetailCode: body['delivery_detail_code'] as String? ?? '',
      resendAvailableIn: body['resend_available_in'] as int?,
      expiresIn: body['expires_in'] as int?,
    );
  }

  /// Шаг 2: проверка кода из СМС.
  ///
  /// Возвращает, известен ли номер: `login` — аккаунт есть, `register` —
  /// новый пользователь.
  Future<DemoAuthPhoneResult> verifyPhone({
    required String ticket,
    required String code,
  }) async {
    final body = await _post('/phone/verify', {
      'ticket': ticket,
      'code': code,
    });
    return DemoAuthPhoneResult(
      isExistingUser: body['status'] == 'login',
      maskedEmail: body['email_masked'] as String?,
      hasEmail: body['has_email'] as bool? ?? false,
      // Опциональные поля: сервер их пока не отдаёт (см. отчёт по
      // недостающему контракту) — тогда альтернативный канал выводим по
      // косвенным признакам.
      emailVerified: body['email_verified'] as bool?,
      phoneVerified: body['phone_verified'] as bool?,
    );
  }

  /// Шаг 3: заказ кода на указанную почту.
  Future<DemoAuthStartResult> sendEmailCode({
    required String ticket,
    required String email,
  }) async {
    final body = await _post('/email/send', {
      'ticket': ticket,
      'email': email,
    });
    return DemoAuthStartResult(
      ticket: ticket,
      maskedDestination: body['masked_destination'] as String? ?? email,
      channel: 'email',
      resendAvailableIn: body['resend_available_in'] as int?,
      expiresIn: body['expires_in'] as int?,
    );
  }

  /// Шаг 4: проверка кода из письма.
  Future<void> verifyEmail({
    required String ticket,
    required String code,
  }) async {
    await _post('/email/verify', {'ticket': ticket, 'code': code});
  }

  /// Финал: вход или создание Matrix-аккаунта.
  ///
  /// Если у человека аккаунты на нескольких инстансах, сервер вернёт
  /// список — тогда [DemoAuthCompleteResult.accounts] не пуст и нужно
  /// повторить вызов с выбранным [serverName].
  Future<DemoAuthCompleteResult> complete({
    required String ticket,
    String? serverName,
  }) async {
    final body = await _post('/complete', {
      'ticket': ticket,
      if (serverName != null && serverName.isNotEmpty)
        'server_name': serverName,
    });

    if (body['status'] == 'select_server') {
      final raw = (body['accounts'] as List?) ?? const [];
      return DemoAuthCompleteResult(
        accounts: raw
            .cast<Map<String, dynamic>>()
            .map(DemoAuthAccount.fromJson)
            .toList(),
      );
    }

    return DemoAuthCompleteResult(
      tokens: DemoAuthTokens(
        loginToken: body['login_token'] as String,
        serverName: body['server_name'] as String,
        userId: body['user_id'] as String,
      ),
    );
  }

  /// Обращение в поддержку. Эндпоинт публичный: человек пишет из тупика,
  /// когда войти не удалось.
  Future<void> sendSupportRequest({
    required String email,
    required String text,
    String? ticket,
    String? step,
    String? errorCode,
  }) async {
    await _post('/support/request', {
      'email': email,
      'text': text,
      if (ticket != null) 'ticket': ticket,
      if (step != null) 'step': step,
      if (errorCode != null) 'error_code': errorCode,
    }, absolutePath: true);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload, {
    bool absolutePath = false,
  }) async {
    final http.Response response;
    try {
      response = await _client.post(
        _uri(path, absolutePath: absolutePath),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
    } catch (_) {
      throw const DemoAuthException('network_error');
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      body = const {};
    }

    if (response.statusCode == 200) return body;

    // Код ошибки читаем ОДИНАКОВО для всех статусов, включая 429: серверные
    // лимиты отвечают Too Many Requests, а не 4xx/502, и без этой ветки
    // `otp_rate_limited` дошёл бы до UI как `internal_error`.
    throw DemoAuthException(
      body['error'] as String? ?? 'internal_error',
      attemptsRemain: body['attempts_remain'] as int?,
      resendAvailableIn: body['resend_available_in'] as int?,
    );
  }
}

class DemoAuthStartResult {
  const DemoAuthStartResult({
    required this.ticket,
    required this.maskedDestination,
    this.deliveryFailed = false,
    this.channel = 'phone',
    this.deliveryError = '',
    this.deliveryDetail = '',
    this.deliveryDetailCode = '',
    this.resendAvailableIn,
    this.expiresIn,
  });

  final String ticket;
  final String maskedDestination;

  /// Куда ушёл код: `phone` (СМС), `email` (письмо) или `password` (кода
  /// нет, см. [isPasswordChannel]). Сервер выбирает
  /// письмо, когда у номера есть аккаунт с настоящей почтой — оно дешевле
  /// СМС. От канала зависит текст экрана и маска адресата.
  final String channel;

  bool get isEmailChannel => channel == 'email';

  /// Номер из списка App Store review на сервере: кода не будет, вход по
  /// заранее выданному паролю через тот же `/phone/verify`. Ни номера, ни
  /// пароля клиент не знает — канал сообщает только сервер.
  bool get isPasswordChannel => channel == 'password';

  /// Причина несостоявшейся доставки: `otp_rate_limited` (лимит частоты,
  /// надо подождать) либо `otp_send_failed` (сбой провайдера).
  final String deliveryError;

  bool get isRateLimited => deliveryError == 'otp_rate_limited';

  /// Ответ otpverification как есть (без персональных данных). Английский —
  /// показываем мелким шрифтом под основным сообщением: он конкретнее
  /// нашей формулировки и помогает при разборе.
  final String deliveryDetail;

  /// Код известной ошибки otpverification. Сам `deliveryDetail` приходит
  /// на английском и во внутренних терминах сервиса — показываем не его,
  /// а свой текст по этому коду. Пусто = текста для человека нет.
  final String deliveryDetailCode;

  /// Провайдер не принял заявку (лимит, сбой). Код не придёт — в демо
  /// вход возможен по коду из нулей.
  final bool deliveryFailed;

  /// Сколько секунд до следующей разрешённой отправки — считает СЕРВЕР.
  /// Локальные 60 секунд в UI были догадкой и расходились с лимитом.
  final int? resendAvailableIn;

  /// Сколько секунд живёт выданный код.
  final int? expiresIn;
}

class DemoAuthPhoneResult {
  const DemoAuthPhoneResult({
    required this.isExistingUser,
    required this.hasEmail,
    this.maskedEmail,
    this.emailVerified,
    this.phoneVerified,
  });

  final bool isExistingUser;
  final bool hasEmail;
  final String? maskedEmail;

  /// Подтверждены ли оба канала. `null` — сервер поля не прислал.
  final bool? emailVerified;
  final bool? phoneVerified;
}

/// Аккаунт пользователя на конкретном инстансе.
class DemoAuthAccount {
  const DemoAuthAccount({
    required this.serverName,
    required this.userId,
    required this.isDefault,
  });

  factory DemoAuthAccount.fromJson(Map<String, dynamic> json) =>
      DemoAuthAccount(
        serverName: json['server_name'] as String,
        userId: json['user_id'] as String,
        isDefault: json['is_default'] as bool? ?? false,
      );

  final String serverName;
  final String userId;
  final bool isDefault;

  /// `@ivan:server` -> `ivan`, как в штатном экране выбора.
  String get localpart {
    final withoutSigil = userId.startsWith('@') ? userId.substring(1) : userId;
    final colon = withoutSigil.indexOf(':');
    return colon == -1 ? withoutSigil : withoutSigil.substring(0, colon);
  }
}

/// Либо готовые токены, либо список аккаунтов на выбор.
class DemoAuthCompleteResult {
  const DemoAuthCompleteResult({
    this.tokens,
    this.accounts = const [],
  });

  final DemoAuthTokens? tokens;
  final List<DemoAuthAccount> accounts;

  bool get needsServerChoice => tokens == null && accounts.isNotEmpty;
}

class DemoAuthTokens {
  const DemoAuthTokens({
    required this.loginToken,
    required this.serverName,
    required this.userId,
  });

  final String loginToken;
  final String serverName;
  final String userId;
}

/// Ошибка демо-флоу с кодом от сервера — по нему выбирается текст в UI.
class DemoAuthException implements Exception {
  const DemoAuthException(
    this.code, {
    this.attemptsRemain,
    this.resendAvailableIn,
  });

  final String code;
  final int? attemptsRemain;

  /// Через сколько секунд сервер разрешит повтор (приходит с `429`).
  final int? resendAvailableIn;

  @override
  String toString() => 'DemoAuthException($code)';
}
