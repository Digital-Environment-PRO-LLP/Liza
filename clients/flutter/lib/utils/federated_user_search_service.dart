import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

/// Запись поиска пользователя на произвольном инстансе федерации.
class FederatedUserEntry {
  final String userId;
  final String? displayName;
  final String? avatarUrl;
  final String? homeserver;

  const FederatedUserEntry({
    required this.userId,
    this.displayName,
    this.avatarUrl,
    this.homeserver,
  });

  factory FederatedUserEntry.fromJson(Map<String, dynamic> json) =>
      FederatedUserEntry(
        userId: json['user_id'] as String,
        displayName: json['display_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        homeserver: json['homeserver'] as String?,
      );

  Profile toProfile() => Profile(
        userId: userId,
        displayName: displayName,
        avatarUrl: avatarUrl == null ? null : Uri.tryParse(avatarUrl!),
      );
}

/// Поиск людей по всем инстансам федерации через кастомный эндпоинт Synapse.
class FederatedUserSearchService {
  final Client client;

  FederatedUserSearchService(this.client);

  /// Федеративный поиск пользователей. Пустой список при любой ошибке —
  /// не должен ронять экран поиска.
  Future<List<FederatedUserEntry>> searchUsers(String query) async {
    final homeserver = client.homeserver;
    final accessToken = client.accessToken;
    if (homeserver == null || accessToken == null) return const [];
    try {
      final uri = homeserver
          .resolve('/_synapse/client/user_search/v1/search')
          .replace(queryParameters: {'query': query});
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (response.statusCode != 200) {
        Logs().w('[UserSearch] status ${response.statusCode}');
        return const [];
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final list = (body['results'] as List?) ?? const [];
      return list
          .map((e) => FederatedUserEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, s) {
      Logs().w('[UserSearch] searchUsers failed', e, s);
      return const [];
    }
  }
}

/// Слить два источника, дедуплицируя по userId: локальные → федеративные.
/// Первое вхождение выигрывает — у локального профиля данные полнее.
List<Profile> mergeSearchResults({
  required List<Profile> local,
  required List<FederatedUserEntry> federated,
}) {
  final seen = <String>{};
  final result = <Profile>[];

  void add(Profile profile) {
    if (!seen.add(profile.userId)) return;
    result.add(profile);
  }

  for (final p in local) {
    add(p);
  }
  for (final e in federated) {
    add(e.toProfile());
  }
  return result;
}

/// Догружает имя и аватар профилям, у которых нет имени.
///
/// Находки по @-нику (auth-proxy отдаёт только `{handle, mxid}`), ввод полного
/// MXID и матч по телефону приходят голым `Profile(userId)`; без этого шага
/// экран показывал бы технический localpart `user_<hex8>` (LABA-2552).
/// Контракт «сервер отдаёт только mxid, имя клиент подтягивает сам» принят
/// комиссией 2026-08-19 (howItWoks/addContacts.md §4.1).
///
/// Правила:
/// - трогаем ТОЛЬКО элементы с `displayName == null`; профиль из directory
///   (полнее) не подменяется — иначе ломается приоритет [mergeSearchResults];
/// - подменяем ТОЛЬКО если пришло имя: пустой ответ (таймаут, федерация
///   запрещена, M_NOT_FOUND) оставляет исходный элемент. Урок
///   stories_extension.dart:313-317 — там null-Profile затирал известный аватар;
/// - длина, порядок и `userId` элементов сохраняются (пин ИИ/Лизы, телефон на
///   индексе 0, дедуп — всё уже выполнено выше по конвейеру);
/// - никогда не бросает и не мутирует вход — возвращает новый список.
///
/// [timeout] — per-элементный, через параметр SDK: внешний `.timeout` на
/// `Future.wait` не отменил бы уже ушедшие запросы. Дефолт SDK (30с) для
/// живого поиска неприемлем. [maxCacheAge] короче SDK-дефолта (сутки): флаг
/// `outdated` SDK ставит только по m.room.member в ОБЩИХ комнатах, а человек
/// из поиска общих комнат с нами, как правило, не имеет — иначе сменённое им
/// имя висело бы «неактуальным» до суток. Верхняя граница параллельных
/// запросов = cap источников (20 у auth-proxy), отдельно не ограничиваем.
Future<List<Profile>> hydrateProfilesWithoutDisplayName(
  Client client,
  List<Profile> profiles, {
  Duration timeout = const Duration(seconds: 5),
  Duration maxCacheAge = const Duration(minutes: 10),
}) async {
  final pending = <int, Future<Profile?>>{};
  for (var i = 0; i < profiles.length; i++) {
    if (_hasName(profiles[i])) continue;
    pending[i] = _fetchProfileOrNull(
      client,
      profiles[i].userId,
      timeout: timeout,
      maxCacheAge: maxCacheAge,
    );
  }
  final result = List<Profile>.of(profiles);
  if (pending.isEmpty) return result;
  final fetched = await Future.wait(pending.values);
  var j = 0;
  for (final i in pending.keys) {
    final profile = fetched[j++];
    if (profile == null || !_hasName(profile)) continue;
    if (profile.userId != profiles[i].userId) continue;
    result[i] = profile;
  }
  return result;
}

bool _hasName(Profile profile) {
  final name = profile.displayName;
  return name != null && name.isNotEmpty;
}

Future<Profile?> _fetchProfileOrNull(
  Client client,
  String userId, {
  required Duration timeout,
  required Duration maxCacheAge,
}) async {
  try {
    // SDK сам не бросает (отдаёт Profile с null-полями), catch — на случай
    // смены этого контракта: один сбой не должен ронять весь Future.wait.
    return await client.getProfileFromUserId(
      userId,
      timeout: timeout,
      maxCacheAge: maxCacheAge,
    );
  } catch (e, s) {
    Logs().v('[UserSearch] profile hydration failed for $userId', e, s);
    return null;
  }
}

/// Вторая стадия публикации на главном экране: подменяет в УЖЕ показанном
/// списке [target] элементы гидратированными из [hydrated] по индексу, не
/// меняя порядок и не пересоздавая список (карусель читает именно его; страж
/// RL-user-handles фиксирует публикацию мутацией). Элемент подменяется только
/// при совпадении `userId` на том же индексе — если список успели пересобрать
/// под другой запрос, ничего не портим. Возвращает, изменилось ли что-то
/// (нужен ли setState).
bool applyHydratedProfiles(List<Profile> target, List<Profile> hydrated) {
  var changed = false;
  final n = target.length < hydrated.length ? target.length : hydrated.length;
  for (var i = 0; i < n; i++) {
    if (identical(target[i], hydrated[i])) continue;
    if (target[i].userId != hydrated[i].userId) continue;
    target[i] = hydrated[i];
    changed = true;
  }
  return changed;
}

/// Поднять AI-профили в начало списка, не меняя относительный порядок
/// остальных. [isAi] — предикат распознавания AI-аккаунта.
///
/// Лиза идёт первой среди AI: она — основной ассистент, и во всех трёх
/// экранах поиска ожидается именно вверху. Правило живёт здесь, а не в
/// вызывающем коде, чтобы экраны не расходились в поведении.
List<Profile> pinAiProfilesFirst(
  List<Profile> profiles, {
  required bool Function(Profile) isAi,
  String? lizaMxid,
}) {
  final ai = <Profile>[];
  final rest = <Profile>[];
  for (final p in profiles) {
    (isAi(p) ? ai : rest).add(p);
  }
  if (lizaMxid != null) {
    final lizaIndex = ai.indexWhere((p) => p.userId == lizaMxid);
    if (lizaIndex > 0) {
      ai.insert(0, ai.removeAt(lizaIndex));
    }
  }
  return [...ai, ...rest];
}
