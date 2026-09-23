// Ник канала для ссылки `me.liza.ru/c/<ник>`.
//
// Правила ОБЯЗАНЫ совпадать с серверным валидатором
// `servers/auth-proxy/app/invites/handle_validator.py` — клиент проверяет
// заранее, чтобы не гонять заведомо неверный ник по сети, но последнее слово
// всегда за сервером (только он знает про занятость).

const int channelHandleMinLength = 5;
const int channelHandleMaxLength = 32;

/// Служебные слова: чтобы никто не выдавал себя за официальный канал Liza.
const Set<String> reservedChannelHandles = {
  'admin',
  'api',
  'support',
  'help',
  'liza',
};

final RegExp _handleRe = RegExp(r'^[a-z][a-z0-9_]{4,31}$');

enum ChannelHandleError { tooShort, tooLong, badFormat, reserved }

String normalizeChannelHandle(String raw) => raw.trim().toLowerCase();

/// Возвращает `null` если ник валиден, иначе — причину отказа.
ChannelHandleError? validateChannelHandle(String raw) {
  final handle = normalizeChannelHandle(raw);
  // Проверяем резервные слова в первую очередь: даже если они короче
  // минимума, это всё равно ошибка «зарезервировано», а не «слишком коротко».
  if (reservedChannelHandles.contains(handle)) {
    return ChannelHandleError.reserved;
  }
  if (!_handleRe.hasMatch(handle)) {
    if (handle.length < channelHandleMinLength) {
      return ChannelHandleError.tooShort;
    }
    if (handle.length > channelHandleMaxLength) {
      return ChannelHandleError.tooLong;
    }
    return ChannelHandleError.badFormat;
  }
  return null;
}

/// Декоративный префикс для поля ввода ника в настройках канала.
///
/// Реальный URL ссылки приходит С СЕРВЕРА (поле `url` в ответе auth-proxy):
/// домен лендинга знает только он, клиент ходит на другой хост (`auth.*`).
/// Эта константа нужна лишь для подписи поля, пока ник ещё не сохранён.
const String channelLinkDisplayPrefix = 'me.liza.ru/c/';

String channelHandleUrl(String handle, {required String landingBase}) {
  final base = landingBase.endsWith('/')
      ? landingBase.substring(0, landingBase.length - 1)
      : landingBase;
  return '$base/c/$handle';
}

/// Таблица ICAO Doc 9303 — та же, что в серверной transliteration.py.
const Map<String, String> _icao = {
  'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd',
  'е': 'e', 'ё': 'e', 'ж': 'zh', 'з': 'z', 'и': 'i',
  'й': 'i', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n',
  'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't',
  'у': 'u', 'ф': 'f', 'х': 'kh', 'ц': 'ts', 'ч': 'ch',
  'ш': 'sh', 'щ': 'shch', 'ъ': '', 'ы': 'y', 'ь': '',
  'э': 'e', 'ю': 'iu', 'я': 'ia',
};

/// Подсказка ника по имени канала. Результат может быть невалидным
/// (слишком коротким) — это подсказка, а не готовый ник.
String suggestHandleFrom(String channelName) {
  final lower = channelName.trim().toLowerCase();
  final buf = StringBuffer();
  for (final ch in lower.split('')) {
    buf.write(_icao[ch] ?? ch);
  }
  var out = buf
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (out.length > channelHandleMaxLength) {
    out = out.substring(0, channelHandleMaxLength).replaceAll(
          RegExp(r'_+$'),
          '',
        );
  }
  return out;
}
