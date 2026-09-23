import 'package:matrix/matrix.dart';

class AccountBundles {
  String? prefix;
  List<AccountBundle>? bundles;

  AccountBundles({this.prefix, this.bundles});

  AccountBundles.fromJson(Map<String, dynamic> json)
    : prefix = json.tryGet<String>('prefix'),
      bundles = json['bundles'] is List
          ? json['bundles']
                .map((b) {
                  try {
                    return AccountBundle.fromJson(b);
                  } catch (_) {
                    return null;
                  }
                })
                .whereType<AccountBundle>()
                .toList()
          : null;

  Map<String, dynamic> toJson() => {
    if (prefix != null) 'prefix': prefix,
    if (bundles != null) 'bundles': bundles!.map((v) => v.toJson()).toList(),
  };
}

class AccountBundle {
  String? name;
  int? priority;

  AccountBundle({this.name, this.priority});

  AccountBundle.fromJson(Map<String, dynamic> json)
    : name = json.tryGet<String>('name'),
      priority = json.tryGet<int>('priority');

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (name != null) 'name': name,
    if (priority != null) 'priority': priority,
  };
}

const accountBundlesType = 'im.fluffychat.account_bundles';

extension AccountBundlesExtension on Client {
  List<AccountBundle> get accountBundles {
    List<AccountBundle>? ret;
    if (accountData.containsKey(accountBundlesType)) {
      ret = AccountBundles.fromJson(
        accountData[accountBundlesType]!.content,
      ).bundles;
    }
    ret ??= [];
    if (ret.isEmpty) {
      ret.add(AccountBundle(name: userID, priority: 0));
    }
    return ret;
  }

  /// Локальное эхо только что записанных пакетов (LABA-2542).
  ///
  /// `setAccountData` в matrix-4.1.0 — голый PUT
  /// (`matrix_api_lite/generated/api.dart`): он не трогает ни [accountData],
  /// ни базу, их заполняет ТОЛЬКО разбор `/sync` (`src/client.dart`, ветка
  /// `for (final newAccountData in sync.accountData ...)`). Пакеты же читаются
  /// синхронными геттерами ([accountBundles] здесь и `MatrixState.accountBundles`),
  /// поэтому до прихода следующего `/sync` интерфейс показывал старое состояние —
  /// пользователю приходилось перезагружать страницу.
  ///
  /// Зеркалим ровно ОБА шага SDK — сначала база, потом карта. Без записи в базу
  /// холодный старт до прихода `/sync` поднял бы из неё старое значение, и на
  /// web (перезагрузка вкладки) баг стал бы недетерминированным вместо
  /// воспроизводимого. `onAccountData.add` намеренно не зовём — он deprecated.
  Future<void> _echoAccountBundles(Map<String, Object?> content) async {
    await database.storeAccountData(accountBundlesType, content);
    accountData[accountBundlesType] = BasicEvent(
      type: accountBundlesType,
      content: content,
    );
  }

  Future<void> setAccountBundle(String name, [int? priority]) async {
    final data = AccountBundles.fromJson(
      accountData[accountBundlesType]?.content ?? {},
    );
    var foundBundle = false;
    final bundles = data.bundles ??= [];
    for (final bundle in bundles) {
      if (bundle.name == name) {
        bundle.priority = priority;
        foundBundle = true;
        break;
      }
    }
    if (!foundBundle) {
      bundles.add(AccountBundle(name: name, priority: priority));
    }
    // Один и тот же объект уходит и на сервер, и в эхо: перечитывать
    // accountData после PUT нельзя — при двух быстрых правках подряд эхо
    // перетёрло бы эхо устаревшим снимком.
    final content = data.toJson();
    await setAccountData(userID!, accountBundlesType, content);
    await _echoAccountBundles(content);
  }

  Future<void> removeFromAccountBundle(String name) async {
    if (!accountData.containsKey(accountBundlesType)) {
      return; // nothing to do
    }
    final data = AccountBundles.fromJson(
      accountData[accountBundlesType]!.content,
    );
    if (data.bundles == null) return;
    data.bundles!.removeWhere((b) => b.name == name);
    final content = data.toJson();
    await setAccountData(userID!, accountBundlesType, content);
    await _echoAccountBundles(content);
  }

  String get sendPrefix {
    final data = AccountBundles.fromJson(
      accountData[accountBundlesType]?.content ?? {},
    );
    return data.prefix!;
  }
}
