/// Конфигурация локального e2e (см. tests/e2e.md и
/// plans/architecture/LOCAL-TESTING.md). Все значения переопределяются через
/// --dart-define при запуске `flutter test integration_test/...`.
abstract class E2eConfig {
  E2eConfig._();

  /// Homeserver локального стека. Для Android-эмулятора переопределять на
  /// http://localhost:8008 (+ adb reverse tcp:8008 tcp:8008) — Dart на
  /// Android не доверяет user-CA, https с mkcert там не взлетит.
  static final Uri homeserver = Uri.parse(
    const String.fromEnvironment(
      'E2E_HOMESERVER',
      defaultValue: 'https://synapse.liza.local',
    ),
  );

  /// Пользователь, под которым логинится UI (см. make local-seed).
  static const userA = E2eUser(
    String.fromEnvironment('E2E_USER1', defaultValue: 'testuser'),
    String.fromEnvironment('E2E_PASS1', defaultValue: 'testpass'),
  );

  /// «Собеседник» — headless-актор через Matrix CS API
  /// (см. make local-seed-e2e).
  static const userB = E2eUser(
    String.fromEnvironment('E2E_USER2', defaultValue: 'testuser2'),
    String.fromEnvironment('E2E_PASS2', defaultValue: 'testpass2'),
  );

  /// Третий участник — для групповых кейсов (несколько читателей в SeenByRow).
  static const userC = E2eUser(
    String.fromEnvironment('E2E_USER3', defaultValue: 'testuser3'),
    String.fromEnvironment('E2E_PASS3', defaultValue: 'testpass3'),
  );
}

class E2eUser {
  final String name;
  final String password;

  const E2eUser(this.name, this.password);
}
