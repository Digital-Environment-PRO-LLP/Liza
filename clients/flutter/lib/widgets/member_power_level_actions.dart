/// SDK намеренно разрешает менять power level СЕБЕ (matrix-dart-sdk
/// `User.canChangeUserPowerLevel`, `user.dart:196-198`:
/// `powerLevel < room.ownPowerLevel || id == room.client.userID`) — без
/// этого гейта админ/модератор мог разжаловать сам себя и остаться без прав
/// на управление комнатой. `MemberActionsPopupMenuButton` целиком
/// смонтировать в тесте нечем (нужен настоящий `User`/`Room`/`Client` из
/// matrix-dart-sdk), поэтому сама проверка вынесена в чистую функцию и
/// покрыта напрямую — так регресс вида «кто-то убрал self-check из enabled»
/// ловится юнит-тестом, а не пропадает вместе с невозможностью смонтировать
/// виджет (см. `participant_row_actions.dart` — тот же приём).
library;

/// Может ли [callerId] менять power level [targetId] в комнате.
///
/// [sdkAllows] — результат `user.room.canChangePowerLevel &&
/// user.canChangeUserPowerLevel` (SDK-проверка прав + верхней границы
/// уровня). Эта функция дополнительно запрещает менять СВОЙ собственный
/// уровень, даже если SDK его разрешает.
bool canChangeMemberPowerLevel({
  required String callerId,
  required String targetId,
  required bool sdkAllows,
}) => sdkAllows && callerId != targetId;
