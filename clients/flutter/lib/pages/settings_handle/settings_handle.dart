import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:liza/config/app_config.dart';
import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/settings_handle/settings_handle_view.dart';
import 'package:liza/utils/channel_handle.dart';
import 'package:liza/utils/handle_profile_field.dart';
import 'package:liza/utils/user_handle_service.dart';
import 'package:liza/widgets/matrix.dart';

/// Кандидат в ник по localpart вида `имя.фамилия` — заменяет точку на
/// подчёркивание (точка в формате ников запрещена). `null`, если в
/// localpart нет точки или кандидат всё равно не проходит валидацию
/// (например, слишком короткий).
/// Приводит к нику то, что попало в поле: срезает сигил, отбрасывает
/// `:server` и всё, чего в формате ника быть не может.
///
/// Нужна потому, что значение приходит не только с клавиатуры: автозаполнение
/// браузера подставляет в поле «Имя пользователя» сохранённый MXID
/// (`@test_furman_8282:bots.liza.ru`), минуя inputFormatters.
String sanitizeHandleInput(String raw) {
  var value = raw.trim();
  if (value.startsWith('@')) value = value.substring(1);
  final colon = value.indexOf(':');
  if (colon >= 0) value = value.substring(0, colon);
  return value.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');
}

String? suggestHandleFromLocalpart(String localpart) {
  final bare = localpart.startsWith('@') ? localpart.substring(1) : localpart;
  if (!bare.contains('.')) return null;
  final candidate = normalizeChannelHandle(bare.replaceAll('.', '_'));
  return validateChannelHandle(candidate) == null ? candidate : null;
}

/// Экран настроек публичного @-ника пользователя.
///
/// [service] можно подменить в тестах — по умолчанию контроллер создаёт свой
/// поверх `AppConfig.authProxyBaseUrl` и текущего Matrix-клиента.
class SettingsHandlePage extends StatefulWidget {
  const SettingsHandlePage({super.key, this.service});

  final UserHandleService? service;

  @override
  State<SettingsHandlePage> createState() => SettingsHandleController();
}

class SettingsHandleController extends State<SettingsHandlePage> {
  UserHandleService? _ownService;

  UserHandleService get service =>
      widget.service ??
      (_ownService ??= UserHandleService(
        baseUrl: AppConfig.authProxyBaseUrl,
        accessTokenProvider: () => Matrix.of(context).client.accessToken,
        serverNameProvider: () =>
            Matrix.of(context).client.userID?.split(':').last ?? '',
      ));

  bool isLoading = true;
  bool isSaving = false;
  String? handle;
  String? suggestion;

  /// Готовый ЛОКАЛИЗОВАННЫЙ текст причины отказа, а не код вроде `'network'`.
  ///
  /// Раньше здесь жил `String? error` со строковыми кодами, которые вид
  /// разбирал `switch`-ем с веткой `_ => handleInvalid`. Любой код, о котором
  /// вид не знал (`'network'` из save(), `'network_error'` из load()), молча
  /// превращался в текст про формат — человек чинил несуществующую проблему
  /// (LABA-2547). С готовым текстом кода-сироты не существует.
  String? errorText;

  /// Гейт `handles.allowed_servers` на auth-proxy: на этом хоумсервере ник
  /// вообще можно завести? Пока не загрузились — считаем, что можно, иначе
  /// кнопка мигала бы выключенной на каждом открытии экрана.
  bool available = true;
  bool saved = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  @override
  void dispose() {
    // Закрываем только сервис, созданный самим контроллером — переданный
    // извне (в тестах) остаётся под управлением вызывающей стороны.
    _ownService?.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => isLoading = true);
    // ВЕСЬ метод под защитой: он зовётся из initState, и любое неперехваченное
    // исключение (сеть, профиль, неожиданный ответ) сняло бы экран целиком —
    // человека выбрасывало в список чатов вместо показа ошибки.
    try {
      final state = await service.fetchOwn();
      if (!mounted) return;

      final current = state.handle;
      if (current != null) {
        // auth-proxy — источник истины. Поле профиля синхронизируем молча,
        // сбой публикации не должен мешать открытию экрана.
        final client = Matrix.of(context).client;
        final userId = client.userID;
        if (userId != null) {
          try {
            final profile = await client.getUserProfile(userId);
            if (handleFromProfile(profile) != current) {
              await publishHandle(client, current);
            }
          } catch (e, st) {
            // Профиль не источник истины: не смогли прочитать или записать —
            // показываем ник из auth-proxy как есть.
            Logs().w('[SettingsHandle] сверка профиля не удалась', e, st);
          }
        }
      }
      if (!mounted) return;

      // substring(1) для ясности намерения: userID это `@localpart:server`.
      // suggestHandleFromLocalpart сигил отсекает и сама, так что это не
      // фикс, а явное выражение того, что передаём именно localpart.
      final userId = Matrix.of(context).client.userID;
      final localpart = userId?.substring(1).split(':').first;
      setState(() {
        handle = current;
        available = state.available;
        suggestion = current == null && localpart != null
            ? suggestHandleFromLocalpart(localpart)
            : null;
        isLoading = false;
        // Фича выключена на этом сервере — объясняем ЗДЕСЬ, а не доводим
        // человека до 403 после нажатия «Изменить».
        errorText = state.available ? null : L10n.of(context).handleUnavailable;
      });
    } catch (e, st) {
      Logs().w('[SettingsHandle] load failed', e, st);
      if (!mounted) return;
      setState(() {
        isLoading = false;
        errorText = L10n.of(context).handleNetworkError;
      });
    }
  }

  /// Сбрасывает показанную причину отказа. Зовётся при вводе: старый текст
  /// («имя занято») не должен висеть, пока человек набирает другое имя.
  void clearError() {
    errorText = null;
    saved = false;
  }

  String _formatErrorText(ChannelHandleError error) => switch (error) {
        ChannelHandleError.tooShort => L10n.of(context).handleTooShort,
        ChannelHandleError.tooLong => L10n.of(context).handleTooLong,
        ChannelHandleError.badFormat => L10n.of(context).handleBadFormat,
        ChannelHandleError.reserved => L10n.of(context).handleReserved,
      };

  Future<void> save(String value) async {
    // sanitizeHandleInput, а не просто normalize: значение могло прийти
    // ИЗВНЕ поля (автозаполнение браузера подставляет MXID
    // `@localpart:server`), минуя inputFormatters. Чистим на границе —
    // отключение autofill само по себе не гарантия, браузеры его игнорируют.
    final normalized = normalizeChannelHandle(sanitizeHandleInput(value));

    // Валидируем ИМЕННО нормализованную строку — ту, что уйдёт на сервер.
    // Проверка сырого поля отвергала бы автозаполненный MXID, который после
    // санитайза совершенно валиден (см. коммит 5a1f4322).
    //
    // Локальная проверка нужна не ради экономии запроса: сервер на
    // зарезервированное слово и на кривой формат отвечает ОДНИМ И ТЕМ ЖЕ
    // `400 invalid_handle` (handle_validator.py), и различить их можно только
    // здесь — правила у клиента и сервера намеренно одинаковы.
    final formatError = validateChannelHandle(normalized);
    if (formatError != null) {
      setState(() {
        isSaving = false;
        saved = false;
        errorText = _formatErrorText(formatError);
      });
      return;
    }

    setState(() {
      isSaving = true;
      errorText = null;
      saved = false;
    });
    final client = Matrix.of(context).client;
    final result = await service.setHandle(normalized, client: client);
    if (!mounted) return;
    switch (result) {
      case HandleSetResult.ok:
        // Публикацию в поле профиля и кэш собственного ника делает сам
        // UserHandleService.setHandle — дублировать здесь не нужно.
        setState(() {
          handle = normalized;
          suggestion = null;
          isSaving = false;
          saved = true;
        });
      case HandleSetResult.taken:
        setState(() {
          isSaving = false;
          errorText = L10n.of(context).handleTaken;
        });
      case HandleSetResult.invalid:
        // Локальная валидация выше уже отсеяла всё, что знает клиент. Сюда
        // попадаем, только если правила сервера разошлись с клиентскими —
        // тогда честнее показать общее правило формата, чем врать деталью.
        setState(() {
          isSaving = false;
          errorText = L10n.of(context).handleInvalid;
        });
      case HandleSetResult.disabled:
        // Отдельно от сети: «попробуйте позже» здесь бессмысленно — пока
        // сервер не откроет гейт, повтор не поможет.
        setState(() {
          isSaving = false;
          available = false;
          errorText = L10n.of(context).handleUnavailable;
        });
      case HandleSetResult.networkError:
        setState(() {
          isSaving = false;
          errorText = L10n.of(context).handleNetworkError;
        });
    }
  }

  @override
  Widget build(BuildContext context) => SettingsHandleView(this);
}
