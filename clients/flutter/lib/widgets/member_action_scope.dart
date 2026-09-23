/// Формулировки прав/kick/ban/unban в меню участника зависят от типа
/// комнаты: канал/чат остаются как раньше, а для пространств заказчик
/// потребовал различать корневую компанию («в компании») и суб-пространство
/// («в пространстве»), чтобы не путать пользователей формулировкой «в чате».
/// `MemberActionsPopupMenuButton` целиком смонтировать в тесте нечем (нужен
/// настоящий `User`/`Room`/`Client` из matrix-dart-sdk), поэтому само
/// ветвление вынесено в чистую функцию и покрыто напрямую — так регресс вида
/// «компания получила формулировку суб-пространства» ловится юнит-тестом, а
/// не пропадает вместе с невозможностью смонтировать виджет (см.
/// `participant_row_actions.dart` / `member_power_level_actions.dart` — тот
/// же приём).
library;

/// Выбирает формулировку [T] по типу комнаты. Порядок проверки: канал
/// приоритетнее пространства (канал технически не space), затем обычный
/// чат, затем пространство — компания или суб-пространство по [isCompany]
/// (см. `isCompanySpace` в `utils/chat_topology.dart`).
T scopedMemberActionLabel<T>({
  required bool isChannel,
  required bool isSpace,
  required bool isCompany,
  required T chat,
  required T channel,
  required T company,
  required T space,
}) {
  if (isChannel) return channel;
  if (!isSpace) return chat;
  return isCompany ? company : space;
}
