import 'dart:ui';

import 'package:phone_numbers_parser/metadata.dart' show countryCodeToIsoCode;

/// Телефонный код страны и разумная длина национального номера.
///
/// Список нужен, чтобы подставить префикс и выбрать страну для маски ввода —
/// человек всегда может стереть подставленный код и вписать свой.
///
/// Раскладку национальной части (какими группами идут цифры) считает не этот
/// список, а `phone_numbers_parser` в [PhoneInputFormatter]: он чистый Dart и
/// потому работает в том числе на web, в отличие от libphonenumber с его
/// нативными биндингами на шесть платформ.
class PhoneCountry {
  const PhoneCountry({
    required this.isoCode,
    required this.dialCode,
    required this.example,
  });

  /// ISO 3166-1 alpha-2, как в `Locale.countryCode`.
  final String isoCode;

  /// Телефонный код без `+` (`7`, `1`, `380`).
  final String dialCode;

  /// Образец национальной части — идёт в плейсхолдер поля.
  final String example;

  String get prefix => '+$dialCode';
}

/// Страна по умолчанию, когда регион устройства неизвестен или не в списке.
const kDefaultPhoneCountry = PhoneCountry(
  isoCode: 'RU',
  dialCode: '7',
  example: '999 123-45-67',
);

/// Страны, откуда реально приходят пользователи Liza, плюс крупные соседи.
/// Список намеренно короткий: он влияет только на автоподстановку префикса.
const kPhoneCountries = <PhoneCountry>[
  kDefaultPhoneCountry,
  PhoneCountry(isoCode: 'KZ', dialCode: '7', example: '701 123-45-67'),
  PhoneCountry(isoCode: 'BY', dialCode: '375', example: '29 123-45-67'),
  PhoneCountry(isoCode: 'UA', dialCode: '380', example: '50 123-45-67'),
  PhoneCountry(isoCode: 'UZ', dialCode: '998', example: '90 123-45-67'),
  PhoneCountry(isoCode: 'KG', dialCode: '996', example: '700 123-456'),
  PhoneCountry(isoCode: 'AM', dialCode: '374', example: '77 123-456'),
  PhoneCountry(isoCode: 'GE', dialCode: '995', example: '555 12-34-56'),
  PhoneCountry(isoCode: 'AZ', dialCode: '994', example: '40 123-45-67'),
  PhoneCountry(isoCode: 'MD', dialCode: '373', example: '60 123-456'),
  PhoneCountry(isoCode: 'TJ', dialCode: '992', example: '90 123-4567'),
  PhoneCountry(isoCode: 'TM', dialCode: '993', example: '65 12-34-56'),
  PhoneCountry(isoCode: 'TR', dialCode: '90', example: '532 123 45 67'),
  PhoneCountry(isoCode: 'AE', dialCode: '971', example: '50 123 4567'),
  PhoneCountry(isoCode: 'IL', dialCode: '972', example: '50 123 4567'),
  PhoneCountry(isoCode: 'RS', dialCode: '381', example: '60 123 4567'),
  PhoneCountry(isoCode: 'ME', dialCode: '382', example: '67 123 456'),
  PhoneCountry(isoCode: 'CY', dialCode: '357', example: '96 123456'),
  PhoneCountry(isoCode: 'DE', dialCode: '49', example: '151 12345678'),
  PhoneCountry(isoCode: 'FR', dialCode: '33', example: '6 12 34 56 78'),
  PhoneCountry(isoCode: 'ES', dialCode: '34', example: '612 34 56 78'),
  PhoneCountry(isoCode: 'IT', dialCode: '39', example: '312 345 6789'),
  PhoneCountry(isoCode: 'PL', dialCode: '48', example: '512 345 678'),
  PhoneCountry(isoCode: 'CZ', dialCode: '420', example: '601 123 456'),
  PhoneCountry(isoCode: 'NL', dialCode: '31', example: '6 12345678'),
  PhoneCountry(isoCode: 'PT', dialCode: '351', example: '912 345 678'),
  PhoneCountry(isoCode: 'GB', dialCode: '44', example: '7400 123456'),
  PhoneCountry(isoCode: 'US', dialCode: '1', example: '201 555-0123'),
  PhoneCountry(isoCode: 'CA', dialCode: '1', example: '204 555-0123'),
  PhoneCountry(isoCode: 'TH', dialCode: '66', example: '81 234 5678'),
  PhoneCountry(isoCode: 'VN', dialCode: '84', example: '91 234 56 78'),
  PhoneCountry(isoCode: 'IN', dialCode: '91', example: '81234 56789'),
  PhoneCountry(isoCode: 'CN', dialCode: '86', example: '131 2345 6789'),
];

/// Страна по НАБРАННОМУ человеком номеру: самый длинный подошедший код.
///
/// Длинные коды проверяются раньше коротких — иначе `+375` (Беларусь)
/// определялся бы по первой цифре как `+3`, которого в справочнике нет, а
/// `+1` перебивал бы всё, что с него начинается. Коды-двойники (`+7` у России
/// и Казахстана, `+1` у США и Канады) разрешаются первым в списке: маска у них
/// всё равно одна.
PhoneCountry? phoneCountryByDialPrefix(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  PhoneCountry? best;
  for (final country in kPhoneCountries) {
    if (!digits.startsWith(country.dialCode)) continue;
    if (best == null || country.dialCode.length > best.dialCode.length) {
      best = country;
    }
  }
  return best;
}

/// Поиск по ISO-коду региона (регистр не важен).
PhoneCountry? phoneCountryByIso(String? isoCode) {
  if (isoCode == null || isoCode.isEmpty) return null;
  final upper = isoCode.toUpperCase();
  for (final country in kPhoneCountries) {
    if (country.isoCode == upper) return country;
  }
  return null;
}

/// Страна из системной локали устройства — мгновенно и без сети.
///
/// `PlatformDispatcher.locale` даёт регион, выбранный в системе
/// (`ru_RU`, `en_US`); на вебе он приходит из `navigator.language`.
PhoneCountry phoneCountryFromLocale([Locale? locale]) {
  final resolved = locale ?? PlatformDispatcher.instance.locale;
  return phoneCountryByIso(resolved.countryCode) ?? kDefaultPhoneCountry;
}

/// Код страны в начале номера, либо `null` — зеркало серверного
/// `country_code()` (`servers/auth-proxy/app/phone_e164.py`).
///
/// Жадно: сначала трёхзначный код, потом двузначный, потом однозначный —
/// иначе `380` (Украина) распался бы на `3`, которого не существует.
///
/// Источник данных — таблица `countryCodeToIsoCode` уже подключённого
/// `phone_numbers_parser` (он и так тянется ради маски ввода, см.
/// [PhoneInputFormatter]), а НЕ рукописная копия серверного списка: копию
/// пришлось бы синхронизировать руками при каждой правке сервера.
String? _dialCodeOf(String digits) {
  for (final length in const [3, 2, 1]) {
    if (digits.length <= length) continue;
    final candidate = digits.substring(0, length);
    if (countryCodeToIsoCode.containsKey(candidate)) return candidate;
  }
  return null;
}

/// Приведение введённого номера к E.164 (`+` и только цифры).
///
/// Зеркало серверного `normalize_phone_e164` (контракт —
/// `servers/auth-proxy/DEMO_AUTH.md` § «Формат номера телефона»):
/// [kPhoneMinDigits]–[kPhoneMaxDigits] цифр вместе с кодом страны И код
/// страны обязан существовать. Возвращает `null`, если номер этому не
/// отвечает. Нижняя граница 10 — не E.164, а валидатор Keycloak (LABA-2527).
///
/// ## Почему проверка кода страны, а не «валиден ли номер»
///
/// У `phone_numbers_parser` есть `isValid()`/`isValidLength()`, но обе
/// проверяют НАЗНАЧЕННОСТЬ номерного блока по метаданным, замороженным в
/// версии пакета, — то есть отвергают больше, чем сервер. Замерено: `isValid`
/// считает невалидными живые `+375 25…` (life:), `+972 50…`/`+972 58…`.
/// Цена такой ошибки несимметрична: ложный отказ = человек не войдёт вовсе и
/// обойти это ему нечем, тогда как лишний пропуск сервер отклонит сам, и
/// клиент покажет отказ корректно.
///
/// Множество кодов пакета — надмножество серверного (сверено: сервер 205,
/// пакет 206, в сервере и не в пакете — пусто), поэтому «код не найден»
/// здесь гарантированно означает «сервер тоже откажет».
///
/// ## Почему национальные формы разбираются ДО проверки
///
/// Сервер понимает `8XXXXXXXXXX`, `9XXXXXXXXX` и ведущее `00`, но применяет
/// эти правила ТОЛЬКО когда плюса не было. Прежняя версия приклеивала `+`
/// всегда — и серверная совместимость на этом пути была мертва: привычный
/// ввод «8 915 123-45-67» уходил как `+789151234567`, сервер принимал его
/// (код 7, длина в диапазоне) и слал СМС в никуда, а «9151234567» уезжал в
/// Индию (`+91`). Разбор здесь возвращает этим правилам силу (LABA-2531).
String? normalizeToE164(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  var hasPlus = text.startsWith('+');
  var digits = text.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;

  // `00` — международный префикс набора (европейский аналог `+`). Снимаем
  // только при ЯВНОМ признаке международного набора, иначе съели бы ведущие
  // нули национального номера.
  if (!hasPlus && digits.startsWith('00')) {
    digits = digits.substring(2);
    hasPlus = true;
  }
  if (!hasPlus) {
    if (digits.length == 11 && digits[0] == '8') {
      digits = '7${digits.substring(1)}';
    } else if (digits.length == 10 && digits[0] == '9') {
      digits = '7$digits';
    }
  }
  // Подставленный интерфейсом «+7 » — аффорданс поля, а не намерение
  // человека: набирая поверх него «8 915…», он вводит НАЦИОНАЛЬНУЮ форму.
  // Национальная часть у `+7` ровно 10 цифр, поэтому `8` сразу за кодом —
  // это транковый префикс, а не часть номера (кодов стран `78`/`789` не
  // существует, так что легитимный номер под правило не попадёт).
  if (digits.length == 12 && digits.startsWith('78')) {
    digits = '7${digits.substring(2)}';
  }

  if (digits.length < kPhoneMinDigits || digits.length > kPhoneMaxDigits) {
    return null;
  }
  if (_dialCodeOf(digits) == null) return null;
  return '+$digits';
}

/// Нижняя граница длины номера (цифры вместе с кодом страны).
///
/// Зеркало серверного `_MIN_DIGITS` (`servers/auth-proxy/app/phone_e164.py`)
/// и, через него, валидатора атрибута `phone` realm'а Keycloak `payform2`
/// (`length min 10 / max 16`, одинаково на dev и prod). Номер короче
/// аккаунтом не станет: при прежней границе 8 он доходил до `/complete`,
/// оставлял сироту в Synapse и получал «Сервис авторизации недоступен»
/// (LABA-2527). Граница ЧУЖАЯ — при смене валидатора realm'а двигать
/// синхронно с сервером; страж `RL-auth-phone-min-length-keycloak` читает
/// обе константы и краснеет при расхождении.
const kPhoneMinDigits = 10;

/// Верхняя граница — сама E.164.
const kPhoneMaxDigits = 15;
