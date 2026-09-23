/// State-событие комнаты, которым клиент сообщает боту поддержки, ЗАЧЕМ открыт
/// чат. Новый DM получает его в `initial_state`, существующий — `PUT /state` с
/// новым `ts` (Synapse не создаёт событие при идентичном контенте). Бот читает
/// state после join и ловит его в sync, отвечает карточкой вместо «Добрый день».
/// В ленте не виден: неизвестные типы скрыты (`isKnownHiddenStates`), в превью
/// списка чатов попадают только `roomPreviewLastEvents`.
const supportIntentStateType = 'com.liza.support.intent';

/// Намерение, с которым пользователь пришёл в поддержку.
enum SupportIntent {
  /// «Создать компанию» (rail-«+», плашка на чипе «Компании»).
  createCompany('create_company');

  const SupportIntent(this.wireValue);

  /// Значение `content.intent` — контракт с `servers/liza-bot-api/support`.
  final String wireValue;

  Map<String, Object?> get content => {
    'intent': wireValue,
    'ts': DateTime.now().millisecondsSinceEpoch,
  };
}
