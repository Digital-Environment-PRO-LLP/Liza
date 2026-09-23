import 'package:flutter_test/flutter_test.dart';
import 'package:liza/pages/chat_permissions_settings/permission_list_tile.dart';

void main() {
  group('PowerLevelPreset.fromMatrixLevel', () {
    test('нормализует произвольный Matrix-уровень до одной из трёх ролей', () {
      expect(PowerLevelPreset.fromMatrixLevel(0), PowerLevelPreset.user);
      expect(PowerLevelPreset.fromMatrixLevel(49), PowerLevelPreset.user);
      expect(PowerLevelPreset.fromMatrixLevel(50), PowerLevelPreset.moderator);
      expect(PowerLevelPreset.fromMatrixLevel(99), PowerLevelPreset.moderator);
      expect(PowerLevelPreset.fromMatrixLevel(100), PowerLevelPreset.admin);
    });
  });
}
