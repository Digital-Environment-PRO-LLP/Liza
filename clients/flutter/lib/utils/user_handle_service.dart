import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'handle_profile_field.dart';

/// Собственное состояние @-ника: значение (если задан) и доступность фичи
/// на текущем homeserver (гейт auth-proxy).
class HandleState {
  const HandleState({required this.handle, required this.available});

  final String? handle;
  final bool available;

  static const disabled = HandleState(handle: null, available: false);
}

/// Найденный по префиксу человек: его @-ник и MXID.
class UserHandleMatch {
  const UserHandleMatch({required this.handle, required this.mxid});

  final String handle;
  final String mxid;
}

/// Итог попытки установить свой ник — различает причину отказа по коду
/// ответа auth-proxy, чтобы UI показал точный текст.
enum HandleSetResult { ok, invalid, taken, disabled, networkError }

/// Клиентский сервис публичного @-ника пользователя.
///
/// Резолв ника в MXID идёт ТОЛЬКО через auth-proxy (`GET /api/handles/<ник>`),
/// никогда через кастомное поле профиля `ru.liza.handle` — то поле пишет сам
/// владелец аккаунта и потому не является источником истины для действий
/// (упоминания, приглашения, переход в чат, игнор-лист).
///
/// [cachedHandleFor] — синхронный геттер без сети: списки участников на
/// сотни строк зовут его из `build()`, и повторение прецедента
/// `stories_extension.dart:314-317` (142 сетевых провала за сессию из
/// build()) здесь недопустимо.
class UserHandleService {
  UserHandleService({
    required this.baseUrl,
    required String? Function() accessTokenProvider,
    required String Function() serverNameProvider,
    http.Client? httpClient,
  })  : _accessTokenProvider = accessTokenProvider,
        _serverNameProvider = serverNameProvider,
        _httpClient = httpClient ?? http.Client();

  /// ХОСТ auth-proxy без схемы (`AppConfig.authProxyBaseUrl` — именно хост,
  /// а не URL). URL собираем через [Uri.https], как остальные сервисы
  /// проекта: `Uri.parse` от голого хоста дал бы ОТНОСИТЕЛЬНЫЙ адрес, и на
  /// вебе запрос ушёл бы на origin страницы (dev.web.liza.ru) вместо
  /// auth-proxy — фича молча не работала бы.
  final String baseUrl;

  Uri _url(String path, [Map<String, String>? query]) =>
      Uri.https(baseUrl, path, query);
  final String? Function() _accessTokenProvider;
  final String Function() _serverNameProvider;
  final http.Client _httpClient;

  static const _cachePrefsKey = 'user_handle_cache_v1';
  static const _cacheTtl = Duration(hours: 1);
  static const _requestTimeout = Duration(seconds: 10);
  static const _persistDebounce = Duration(seconds: 1);

  /// Минимальная длина префикса для [searchHandles]. Совпадает с
  /// `_MIN_SEARCH_PREFIX` в `servers/auth-proxy/app/account/handle_api.py`:
  /// под один символ подпадает почти вся таблица ников.
  static const minSearchPrefix = 2;

  // handle -> (mxid, fetchedAt). Заполняется из resolve() и rememberHandle();
  // персистится в SharedPreferences, чтобы пережить перезапуск приложения.
  final Map<String, _HandleCacheEntry> _cache = {};

  // Обратный индекс mxid -> handle, синхронизируется с [_cache] в тех же
  // трёх местах, где меняется прямой кэш (загрузка с диска, resolve,
  // rememberHandle). Существует ради [cachedHandleFor]: линейный проход по
  // _cache там недопустим — её зовут из build() списков на сотни строк на
  // каждый кадр перерисовки.
  final Map<String, String> _byMxid = {};

  SharedPreferences? _prefs;
  Future<void>? _cacheLoad;
  Timer? _persistDebounceTimer;

  void _putCacheEntry(String handle, _HandleCacheEntry entry) {
    final previousMxid = _cache[handle]?.mxid;
    if (previousMxid != null && previousMxid != entry.mxid) {
      _byMxid.remove(previousMxid);
    }
    // Тот же mxid мог быть закэширован под ДРУГИМ (устаревшим) ником —
    // без этой чистки cachedHandleFor мог бы вернуть старый ник, если он
    // случайно оказался бы первым в Map при линейном переборе.
    final staleHandle = _byMxid[entry.mxid];
    if (staleHandle != null && staleHandle != handle) {
      _cache.remove(staleHandle);
    }
    _cache[handle] = entry;
    _byMxid[entry.mxid] = handle;
  }

  Future<void> _ensureCacheLoaded() {
    return _cacheLoad ??= () async {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      final raw = prefs.getString(_cachePrefsKey);
      if (raw == null) return;
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        for (final e in decoded.entries) {
          _putCacheEntry(
            e.key,
            _HandleCacheEntry.fromJson(e.value as Map<String, dynamic>),
          );
        }
      } catch (e, s) {
        Logs().w('[UserHandleService] Failed to load cache', e, s);
      }
    }();
  }

  Future<void> _persistCache() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _cache.map((handle, entry) => MapEntry(handle, entry.toJson())),
    );
    await prefs.setString(_cachePrefsKey, encoded);
  }

  /// Планирует сброс кэша на диск через [_persistDebounce] после ПОСЛЕДНЕГО
  /// вызова — не после каждого. [rememberHandle] зовут в цикле по списку
  /// участников (десятки-сотни за раз); синхронная сериализация всего кэша
  /// в JSON на КАЖДЫЙ элемент воспроизвела бы ровно ту тяжёлую работу в
  /// отрисовке, от которой [cachedHandleFor] специально уходит.
  void _schedulePersist() {
    _persistDebounceTimer?.cancel();
    _persistDebounceTimer = Timer(_persistDebounce, () {
      unawaited(_persistCache());
    });
  }

  Map<String, String> get _authHeaders {
    final token = _accessTokenProvider();
    return {
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Свой ник и признак того, включена ли фича (гейт server_name на
  /// auth-proxy). Недоступность auth-proxy — фича молча выключается
  /// (`available: false`), настройки не падают.
  Future<HandleState> fetchOwn() async {
    try {
      final uri = _url(
        '/api/account/handle',
        {'server_name': _serverNameProvider()},
      );
      final response = await _httpClient
          .get(uri, headers: _authHeaders)
          .timeout(_requestTimeout);
      if (response.statusCode != 200) {
        Logs().w('[UserHandleService] fetchOwn status ${response.statusCode}');
        return HandleState.disabled;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return HandleState(
        handle: body['handle'] as String?,
        available: body['available'] as bool? ?? false,
      );
    } catch (e, s) {
      Logs().w('[UserHandleService] fetchOwn failed', e, s);
      return HandleState.disabled;
    }
  }

  /// Установить собственный ник. Различает причину отказа по коду ответа —
  /// см. [HandleSetResult].
  ///
  /// [client] используется, чтобы после успешной регистрации на auth-proxy
  /// продублировать ник в кастомное поле профиля `ru.liza.handle` (см.
  /// `handle_profile_field.dart`) — источником истины при этом остаётся
  /// auth-proxy, профиль лишь ускоряет показ. Сбой публикации в профиль НЕ
  /// роняет операцию: ник уже зарегистрирован. Обязательный, а не
  /// опциональный параметр — иначе вызывающая сторона может забыть его
  /// передать, и тогда молча не сработают ни публикация в профиль, ни
  /// немедленное кэширование собственного ника ниже (было реальной багой:
  /// экран настроек звал publishHandle отдельно и дублировал публикацию, а
  /// rememberHandle не срабатывал вовсе).
  ///
  /// Собственный ник сразу кладём в кэш [rememberHandle] — иначе свой же
  /// только что установленный ник не отобразится, пока не подоспеет resolve.
  Future<HandleSetResult> setHandle(
    String handle, {
    required Client client,
  }) async {
    try {
      final uri = _url('/api/account/handle');
      final response = await _httpClient
          .put(
            uri,
            headers: {
              ..._authHeaders,
              'Content-Type': 'application/json',
            },
            // server_name ОБЯЗАТЕЛЕН: по нему сервер находит хоумсервер и
            // проверяет токен. Без него _authenticate отвечает 400
            // unknown_server — тем же кодом, что и «неверный формат ника»,
            // из-за чего человек видел «должен начинаться с буквы» на
            // совершенно правильном нике.
            body: jsonEncode({
              'handle': handle,
              'server_name': _serverNameProvider(),
            }),
          )
          .timeout(_requestTimeout);
      switch (response.statusCode) {
        case 200:
          final userId = client.userID;
          if (userId != null) {
            rememberHandle(userId, handle);
          }
          try {
            await publishHandle(client, handle);
          } catch (e, s) {
            Logs().w('[UserHandleService] publishHandle failed', e, s);
          }
          return HandleSetResult.ok;
        case 400:
          // 400 отдаётся ДВУМЯ разными причинами: `invalid_handle` (формат)
          // и `unknown_server` (сервер не знает хоумсервер). Без разбора
          // тела вторая маскировалась под первую, и человек видел «должен
          // начинаться с буквы» на совершенно правильном нике.
          return _errorCode(response) == 'unknown_server'
              ? HandleSetResult.networkError
              : HandleSetResult.invalid;
        case 403:
          return HandleSetResult.disabled;
        case 409:
          return HandleSetResult.taken;
        default:
          Logs().w(
              '[UserHandleService] setHandle status ${response.statusCode}');
          return HandleSetResult.networkError;
      }
    } catch (e, s) {
      Logs().w('[UserHandleService] setHandle failed', e, s);
      return HandleSetResult.networkError;
    }
  }

  /// Резолвит ник в MXID через auth-proxy, с кэшем в SharedPreferences
  /// (TTL 1 час). Единственный легитимный источник для действий над
  /// вставленным/введённым ником — поле профиля `ru.liza.handle` для этого
  /// не используется (его может подделать сам владелец аккаунта).
  ///
  /// null при неизвестном нике или любой ошибке сети — резолв не должен
  /// ронять вызывающий экран.
  Future<String?> resolve(String handle) async {
    await _ensureCacheLoaded();

    final cached = _cache[handle];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < _cacheTtl) {
      return cached.mxid;
    }

    try {
      final uri = _url('/api/handles/$handle');
      final response =
          await _httpClient.get(uri).timeout(_requestTimeout);
      if (response.statusCode != 200) {
        return null;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final mxid = body['mxid'] as String?;
      if (mxid == null) return null;

      _putCacheEntry(handle, _HandleCacheEntry(mxid: mxid, fetchedAt: DateTime.now()));
      await _persistCache();
      return mxid;
    } catch (e, s) {
      Logs().w('[UserHandleService] resolve failed', e, s);
      return null;
    }
  }

  /// Поиск людей по ПРЕФИКСУ @-ника через auth-proxy
  /// (`GET /api/handles/search`). Дополняет [resolve]: тот находит только
  /// точное совпадение, а человек в поиске набирает ник по буквам.
  ///
  /// Найденные пары кладём в кэш через [rememberHandle] — иначе список
  /// результатов показал бы MXID у людей, ник которых мы только что узнали
  /// (`cachedHandleFor` синхронна и в сеть не ходит, см. класс).
  ///
  /// Пустой список при любой ошибке и при слишком коротком запросе —
  /// поиск не должен ронять экран (тот же контракт, что у
  /// `FederatedUserSearchService.searchUsers`).
  Future<List<UserHandleMatch>> searchHandles(String query) async {
    final normalized = query.trim().toLowerCase().replaceFirst('@', '');
    // Тот же порог, что и на сервере (`_MIN_SEARCH_PREFIX`): не тратим
    // запрос на префикс, который сервер всё равно отклонит.
    if (normalized.length < minSearchPrefix) return const [];
    try {
      final uri = _url('/api/handles/search', {
        'q': normalized,
        'server_name': _serverNameProvider(),
      });
      final response = await _httpClient
          .get(uri, headers: _authHeaders)
          .timeout(_requestTimeout);
      if (response.statusCode != 200) {
        Logs().w(
          '[UserHandleService] searchHandles status ${response.statusCode}',
        );
        return const [];
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final list = (body['results'] as List?) ?? const [];
      final matches = <UserHandleMatch>[];
      for (final raw in list) {
        if (raw is! Map<String, dynamic>) continue;
        final handle = raw['handle'] as String?;
        final mxid = raw['mxid'] as String?;
        if (handle == null || mxid == null) continue;
        rememberHandle(mxid, handle);
        matches.add(UserHandleMatch(handle: handle, mxid: mxid));
      }
      return matches;
    } catch (e, s) {
      Logs().w('[UserHandleService] searchHandles failed', e, s);
      return const [];
    }
  }

  /// Код ошибки из тела ответа, либо пустая строка.
  String _errorCode(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      return body is Map<String, dynamic>
          ? (body['error'] as String? ?? '')
          : '';
    } catch (_) {
      return '';
    }
  }

  /// Ник для [mxid] из уже наполненного кэша, БЕЗ сети. Синхронная,
  /// константное время (обратный индекс [_byMxid]) — вызывается из `build()`
  /// списков участников на сотни строк на каждый кадр перерисовки.
  String? cachedHandleFor(String mxid) => _byMxid[mxid];

  /// Наполнить кэш `mxid -> handle` из уже известных данных (например,
  /// кастомного поля профиля), БЕЗ похода в сеть. Последнее известное
  /// значение побеждает — сменившийся ник в свежем профиле обязан вытеснить
  /// устаревшую запись, иначе [cachedHandleFor] может годами отдавать ник,
  /// от которого владелец уже отказался.
  ///
  /// Синхронная и не пишет на диск немедленно: вызывающая сторона (списки
  /// участников) зовёт её в цикле по пачке профилей, а сериализация всего
  /// кэша на каждый элемент — та же тяжёлая работа в отрисовке, которой
  /// избегает [cachedHandleFor]. Сброс на диск идёт отложенно
  /// ([_schedulePersist]) — без него чужие ники, восстановить которые
  /// резолвом в списках нельзя (см. класс), исчезали бы при каждом
  /// перезапуске приложения.
  void rememberHandle(String mxid, String handle) {
    _putCacheEntry(handle, _HandleCacheEntry(mxid: mxid, fetchedAt: DateTime.now()));
    _schedulePersist();
  }

  void dispose() {
    // Таймер активен => есть несброшенные изменения из rememberHandle.
    // Простая отмена потеряла бы их (сценарий: сохранил ник и сразу закрыл
    // экран настроек) — досбрасываем синхронно-насколько-можно.
    // unawaited: закрытие экрана блокировать не хотим, SharedPreferences
    // успеет записать и без ожидания здесь.
    if (_persistDebounceTimer?.isActive ?? false) {
      _persistDebounceTimer!.cancel();
      unawaited(_persistCache());
    }
    _httpClient.close();
  }
}

class _HandleCacheEntry {
  const _HandleCacheEntry({required this.mxid, required this.fetchedAt});

  final String mxid;
  final DateTime fetchedAt;

  factory _HandleCacheEntry.fromJson(Map<String, dynamic> json) =>
      _HandleCacheEntry(
        mxid: json['mxid'] as String,
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(
          json['fetchedAt'] as int,
        ),
      );

  Map<String, dynamic> toJson() => {
        'mxid': mxid,
        'fetchedAt': fetchedAt.millisecondsSinceEpoch,
      };
}
