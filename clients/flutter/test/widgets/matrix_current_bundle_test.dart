// ledger:RL-current-bundle-not-nullable
// GlitchTip 1918 (`TypeError: Null check operator used on a null value`,
// `ChatController.currentRoomBundle`, сборки 3738 и 3746, Android): при построении
// контекстного меню сообщения `Matrix.of(context).currentBundle!` падал красным
// экраном. Геттер был объявлен `List<Client?>?`, и звали его через `!` в пяти
// местах — то есть падение было вопросом времени, а не экзотики.
//
// Страж стоит на РЕАЛЬНОМ геттере `MatrixState.currentBundle` (не на реплике):
// подменяется только ВХОД (`accountBundles` — карта бандлов) и `widget`, сама
// ветвящаяся логика исполняется настоящая.
//
// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/widgets/matrix.dart' as liza_matrix;

import '../utils/test_client.dart';

/// `MatrixState` с подменёнными входами: список клиентов (обычно приходит из
/// `widget`, которого без монтирования нет) и карта бандлов.
class _BundleMatrixState extends liza_matrix.MatrixState {
  _BundleMatrixState(this._widget, this._bundles);

  final liza_matrix.Matrix _widget;
  final List<Map<String?, List<Client?>>> _bundles;
  int _reads = 0;

  @override
  liza_matrix.Matrix get widget => _widget;

  /// Каждое обращение отдаёт СЛЕДУЮЩИЙ снимок (последний залипает). Так
  /// воспроизводится гонка: `hasComplexBundles` увидел одну карту, а
  /// `currentBundle` следом — уже другую (аккаунт добавили/убрали между вызовами).
  @override
  Map<String?, List<Client?>> get accountBundles {
    final i = _reads < _bundles.length - 1 ? _reads : _bundles.length - 1;
    _reads++;
    return _bundles[i];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late SharedPreferences store;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
    client = await prepareTestClient(loggedIn: true);
  });

  _BundleMatrixState state(List<Map<String?, List<Client?>>> bundles) =>
      _BundleMatrixState(
        liza_matrix.Matrix(clients: [client], store: store),
        bundles,
      );

  test('AC:RL-current-bundle-not-nullable/1 простой случай — список клиентов', () {
    // Один аккаунт, сложных бандлов нет: геттер обязан вернуть НЕПУСТОЙ список,
    // а не «может быть null» — ради `!` на вызывающей стороне и падал прод.
    final bundle = state([{}]).currentBundle;
    expect(bundle, isNotEmpty);
    expect(bundle.first, same(client));
  });

  test('AC:RL-current-bundle-not-nullable/2 активного бандла нет в карте', () {
    // `activeBundle` не выставлен (или указывает на исчезнувший бандл) —
    // возвращаем первый доступный, без null и без исключения.
    final complex = <String?, List<Client?>>{
      'work': [client, client],
    };
    final s = state([complex]);
    s.activeBundle = 'personal-которого-нет';
    expect(s.currentBundle, [client, client]);
  });

  test('AC:RL-current-bundle-not-nullable/3 карта опустела между вызовами', () {
    // RED-PROOF прежней реализации: `hasComplexBundles` читает карту ОДИН раз,
    // `currentBundle` — второй. Если между ними бандлы исчезли, старый
    // `bundles.values.first` бросал StateError на пустой карте. Падать здесь
    // нельзя: геттер зовут из build() контекстного меню.
    final s = state([
      <String?, List<Client?>>{
        'work': [client, client],
      },
      <String?, List<Client?>>{},
    ]);
    expect(s.currentBundle, isNotEmpty);
  });

  test('AC:RL-current-bundle-not-nullable/4 ни одного `!` на вызывающей стороне',
      () {
    // Тип геттера — единственная защита от рецидива: пока где-то стоит
    // `currentBundle!`, падение возвращается ровно в том же виде. Пять мест, где
    // `!` стоял до фикса: chat.dart, chat_input_row.dart ×2, chat_list.dart ×2.
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains('currentBundle!'))
        .map((f) => f.path)
        .toList();
    expect(offenders, isEmpty,
        reason: 'currentBundle больше не nullable — `!` снова уронит прод');
  });
}
