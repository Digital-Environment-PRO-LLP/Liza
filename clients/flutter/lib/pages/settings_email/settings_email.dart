import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:liza/config/app_config.dart';
import 'package:liza/pages/settings_email/settings_email_view.dart';
import 'package:liza/widgets/matrix.dart';

/// Состояние привязки почты, как его отдаёт auth-proxy.
class AccountEmailState {
  const AccountEmailState({required this.maskedEmail, required this.verified});

  final String? maskedEmail;
  final bool verified;

  bool get hasEmail => maskedEmail != null && maskedEmail!.isNotEmpty;

  factory AccountEmailState.fromJson(Map<String, dynamic> json) =>
      AccountEmailState(
        maskedEmail: json['email_masked'] as String?,
        verified: json['verified'] as bool? ?? false,
      );
}

/// Шаги привязки: показ текущего адреса → ввод нового → код из письма.
enum SettingsEmailStep { overview, enterEmail, enterCode }

class SettingsEmailPage extends StatefulWidget {
  const SettingsEmailPage({super.key});

  @override
  State<SettingsEmailPage> createState() => SettingsEmailController();
}

class SettingsEmailController extends State<SettingsEmailPage> {
  final http.Client _http = http.Client();

  @override
  void dispose() {
    // Свой http.Client держит открытые сокеты — закрываем вместе с экраном.
    _http.close();
    super.dispose();
  }

  SettingsEmailStep step = SettingsEmailStep.overview;
  AccountEmailState? state;
  bool isLoading = false;
  String? error;
  String pendingEmail = '';
  int? resendAvailableIn;

  @override
  void initState() {
    super.initState();
    // addPostFrameCallback, а НЕ прямой вызов: loadState() читает
    // Matrix.of(context), а обращение к унаследованному виджету прямо в
    // initState бросает исключение — экран снимался ДО первого сетевого
    // запроса, и человека выбрасывало в список чатов. Тот же приём, что в
    // SettingsHandleController и SettingsController.
    WidgetsBinding.instance.addPostFrameCallback((_) => loadState());
  }

  Uri _uri(String path, [Map<String, String>? query]) => Uri.https(
        AppConfig.authProxyBaseUrl,
        '/api/account/email$path',
        query,
      );

  String? get _token => Matrix.of(context).client.accessToken;

  String get _serverName =>
      Matrix.of(context).client.userID?.split(':').last ?? '';

  Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_token ?? ''}',
      };

  Map<String, dynamic> _decode(http.Response response) =>
      response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;

  Map<String, dynamic> _checkStatus(
    http.Response response,
    Map<String, dynamic> decoded,
  ) {
    if (response.statusCode != 200) {
      throw AccountEmailException(
        decoded['error'] as String? ?? 'internal_error',
        resendAvailableIn: decoded['resend_available_in'] as int?,
      );
    }
    return decoded;
  }

  Future<void> loadState() async {
    setState(() => isLoading = true);
    try {
      final response = await _http.get(
        _uri('', {'server_name': _serverName}),
        headers: _headers(),
      );
      final decoded = _checkStatus(response, _decode(response));
      if (!mounted) return;
      setState(() {
        state = AccountEmailState.fromJson(decoded);
        isLoading = false;
      });
    } on AccountEmailException catch (err) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        error = err.code;
      });
    } catch (e, s) {
      // Сетевой сбой, не-JSON ответ, неожиданный тип поля — что угодно,
      // кроме нашего AccountEmailException. Без этой ветки исключение
      // улетало из initState и ВЫБРАСЫВАЛО с экрана настроек в список
      // чатов, вместо того чтобы показать ошибку на месте.
      Logs().w('[SettingsEmail] loadState failed', e, s);
      if (!mounted) return;
      setState(() {
        isLoading = false;
        error = 'network_error';
      });
    }
  }

  Future<void> sendCode(String email) async {
    setState(() {
      isLoading = true;
      error = null;
    });
    try {
      final response = await _http.post(
        _uri('/send'),
        headers: _headers(),
        body: jsonEncode({'server_name': _serverName, 'email': email}),
      );
      final decoded = _checkStatus(response, _decode(response));
      if (!mounted) return;
      setState(() {
        pendingEmail = email;
        step = SettingsEmailStep.enterCode;
        resendAvailableIn = decoded['resend_available_in'] as int?;
        isLoading = false;
      });
    } on AccountEmailException catch (err) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        error = err.code;
        resendAvailableIn = err.resendAvailableIn;
      });
    } catch (e, s) {
      Logs().w('[SettingsEmail] sendCode failed', e, s);
      if (!mounted) return;
      setState(() {
        isLoading = false;
        error = 'network_error';
      });
    }
  }

  Future<void> verify(String code) async {
    setState(() {
      isLoading = true;
      error = null;
    });
    try {
      final response = await _http.post(
        _uri('/verify'),
        headers: _headers(),
        body: jsonEncode({'server_name': _serverName, 'code': code}),
      );
      _checkStatus(response, _decode(response));
      if (!mounted) return;
      setState(() {
        step = SettingsEmailStep.overview;
        isLoading = false;
      });
      await loadState();
    } on AccountEmailException catch (err) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        error = err.code;
      });
    } catch (e, s) {
      Logs().w('[SettingsEmail] verify failed', e, s);
      if (!mounted) return;
      setState(() {
        isLoading = false;
        error = 'network_error';
      });
    }
  }

  void startChange() => setState(() {
        step = SettingsEmailStep.enterEmail;
        error = null;
      });

  @override
  Widget build(BuildContext context) => SettingsEmailView(this);
}

class AccountEmailException implements Exception {
  const AccountEmailException(this.code, {this.resendAvailableIn});

  final String code;
  final int? resendAvailableIn;
}
