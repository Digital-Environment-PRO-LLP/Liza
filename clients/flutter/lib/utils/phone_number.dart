/// Гейт полноты телефонного номера на границе ввода.
///
/// Возвращает `trimmed`-строку, если в ней ≥10 цифр (похоже на полный номер),
/// иначе `null`. НЕ нормализует к E.164 — серверный матчинг (auth-proxy
/// `POST /contacts/v1/lookup`) сам приводит номер и матчит по любой форме;
/// клиенту нужно лишь решить «это вообще полный номер?», чтобы не слать lookup
/// на частичный ввод и не жечь суточную квоту (howItWoks/addContacts.md §5).
String? completePhoneOrNull(String raw) {
  final trimmed = raw.trim();
  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length < 10) return null;
  return trimmed;
}
