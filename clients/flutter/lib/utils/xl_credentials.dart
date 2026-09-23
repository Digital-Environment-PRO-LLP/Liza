import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:matrix/matrix.dart';
// ignore: depend_on_referenced_packages
import 'package:vodozemac/vodozemac.dart';

import 'package:liza/utils/secure_storage.dart';

/// Подпись AES-CTR из vodozemac. Вынесена в typedef, чтобы тесты подменяли
/// реализацию: нативная библиотека в host-`flutter test` не грузится
/// (тот же приём, что в `e2ee_media_proxy.dart`).
typedef AesCtrFn =
    Uint8List Function({
      required Uint8List input,
      required Uint8List key,
      required Uint8List iv,
    });

/// Тип account_data, где лежит зашифрованный API-ключ XL.
const String xlCredentialsAccountDataType = 'com.liza.xl.credentials';

/// msgtype служебного события, которым ключ доезжает до бота.
const String xlCredentialsMsgtype = 'com.liza.xl.credentials';

/// MXID агента XL. Живёт на доме ботов, как остальные AI-ассистенты.
const String xlBotMxid = '@xl_bot:bots.liza.ru';

/// Ключ в `flutterSecureStorage`, под которым хранится локальный AES-ключ
/// шифрования account_data-записи с ключом XL.
const String _xlEncryptionKeyStorageKey = 'xl_credentials_encryption_key';

/// Работа с API-ключом XL: шифрование для account_data и упаковка в событие.
///
/// Ключ равносилен полному доступу к кабинету мерчанта, поэтому в
/// account_data кладётся только шифротекст, а до бота он едет служебным
/// событием внутри E2EE-комнаты.
abstract final class XlCredentials {
  /// Служебное событие с ключом для бота.
  static Map<String, Object?> buildEvent(String apiKey) => {
    'msgtype': xlCredentialsMsgtype,
    'body': 'Подключение интеграции XL',
    'xl_api_key': apiKey.trim(),
  };

  /// Шифрует ключ и кодирует в base64 для хранения в account_data.
  ///
  /// ⚠️ [iv] ОБЯЗАН быть свежим случайным значением на КАЖДЫЙ вызов с тем же
  /// [key]. AES-CTR — потоковый шифр: повторное использование пары (key, iv)
  /// для разных данных вскрывает исходный текст через XOR шифротекстов.
  /// Сохранённый в account_data iv годится ТОЛЬКО для расшифровки уже
  /// записанного значения — для нового шифрования генерируй новый.
  static String encryptKey(
    String plain,
    Uint8List key,
    Uint8List iv, {
    AesCtrFn? aesCtr,
  }) {
    final impl = aesCtr ?? _defaultAesCtr;
    final cipher = impl(
      input: Uint8List.fromList(utf8.encode(plain)),
      key: key,
      iv: iv,
    );
    return base64Encode(cipher);
  }

  /// Обратная операция к [encryptKey].
  ///
  /// [iv] здесь — тот, что сохранён рядом с шифротекстом. Для нового
  /// шифрования его переиспользовать нельзя (см. предупреждение в [encryptKey]).
  static String decryptKey(
    String encoded,
    Uint8List key,
    Uint8List iv, {
    AesCtrFn? aesCtr,
  }) {
    final impl = aesCtr ?? _defaultAesCtr;
    final plain = impl(input: base64Decode(encoded), key: key, iv: iv);
    return utf8.decode(plain);
  }

  static AesCtrFn get _defaultAesCtr => _vodozemacAesCtr;

  /// Локальный AES-ключ шифрования account_data-записи. Живёт в Keychain/
  /// secure storage устройства (НЕ в account_data — иначе шифрование теряет
  /// смысл), генерируется один раз и переиспользуется на все последующие
  /// `save()`. IV — в отличие от ключа — генерируется заново на каждый вызов
  /// [encryptKey], см. предупреждение там.
  static Future<Uint8List> getOrCreateEncryptionKey() async {
    final stored = await flutterSecureStorage.read(
      key: _xlEncryptionKeyStorageKey,
    );
    if (stored != null) return base64Decode(stored);

    final rng = Random.secure();
    final key = Uint8List(32);
    key.setAll(0, Iterable.generate(key.length, (_) => rng.nextInt(256)));
    await flutterSecureStorage.write(
      key: _xlEncryptionKeyStorageKey,
      value: base64Encode(key),
    );
    return key;
  }

  /// Свежий случайный IV для очередного [encryptKey] (не путать с ключом
  /// шифрования — см. [getOrCreateEncryptionKey]).
  static Uint8List generateIv() {
    final rng = Random.secure();
    final iv = Uint8List(16);
    iv.setAll(0, Iterable.generate(iv.length, (_) => rng.nextInt(256)));
    return iv;
  }

  /// Читает и расшифровывает сохранённый ключ XL из account_data клиента.
  ///
  /// `null`, если интеграция не подключена ИЛИ запись повреждена (ключ/IV не
  /// совпали с локальным AES-ключом — например, Keychain очистился после
  /// переустановки приложения). Во втором случае вызывающая сторона обязана
  /// трактовать это как «подключите заново», а не ронять экран/чат.
  static Future<String?> readStoredKey(Client client) async {
    final content = client.accountData[xlCredentialsAccountDataType]?.content;
    final encoded = content?.tryGet<String>('key');
    final ivBase64 = content?.tryGet<String>('iv');
    if (encoded == null || ivBase64 == null) return null;

    final encryptionKey = await getOrCreateEncryptionKey();
    try {
      return decryptKey(encoded, encryptionKey, base64Decode(ivBase64));
    } on FormatException {
      return null;
    }
  }
}

/// Нужно ли переотправить ключ боту при открытии комнаты.
///
/// Бот хранит ключ только в памяти процесса: после его рестарта ключ теряется,
/// и без переотправки мерчант увидит просьбу подключить интеграцию заново.
bool shouldResendXlKey({
  required String? directChatMxid,
  required bool hasStoredKey,
}) => directChatMxid == xlBotMxid && hasStoredKey;

/// Переотправляет ключ XL боту при открытии DM с ним, если ключ подключён.
///
/// Ошибки глотаются в лог (как `_ensureLizaDm` в `widgets/matrix.dart`) — сбой
/// переотправки не должен ломать открытие чата.
/// Комнаты, куда ключ уже отправлен в этом запуске приложения.
///
/// Бот держит ключ в памяти процесса, поэтому переотправка нужна — но ровно
/// один раз за запуск, а не на каждое открытие чата. Без этого счётчика вход
/// на вкладку слал ключ снова (а пересоздание виджета — по нескольку раз
/// подряд), и бот на каждое отвечал «Кабинет XL подключён», топя в спаме
/// собственные полезные ответы.
final Set<String> _xlKeySentRooms = <String>{};

/// Сбрасывает отметку об отправке — нужно, когда мерчант сменил ключ.
void resetXlKeyResendState() => _xlKeySentRooms.clear();

Future<void> maybeResendXlKey(Client client, Room room) async {
  try {
    if (_xlKeySentRooms.contains(room.id)) return;

    final hasStoredKey =
        client.accountData[xlCredentialsAccountDataType] != null;
    if (!shouldResendXlKey(
      directChatMxid: room.directChatMatrixID,
      hasStoredKey: hasStoredKey,
    )) {
      return;
    }

    final plainKey = await XlCredentials.readStoredKey(client);
    if (plainKey == null) return;

    // Метку ставим ДО отправки: параллельные вызовы (пересоздание виджета
    // чата) не должны успеть проскочить, пока await ещё не вернулся.
    _xlKeySentRooms.add(room.id);
    await room.sendEvent(XlCredentials.buildEvent(plainKey));
  } catch (e, s) {
    _xlKeySentRooms.remove(room.id); // не доехало — дать шанс следующему входу
    Logs().w('[XlCredentials] Не удалось переотправить ключ XL-боту', e, s);
  }
}

/// Боевая реализация: AES-256-CTR из vodozemac (тот же примитив, что у
/// зашифрованных вложений).
Uint8List _vodozemacAesCtr({
  required Uint8List input,
  required Uint8List key,
  required Uint8List iv,
}) => CryptoUtils.aesCtr(input: input, key: key, iv: iv);
