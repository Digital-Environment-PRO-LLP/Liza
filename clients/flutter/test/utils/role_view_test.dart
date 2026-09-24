import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/role_view.dart';

void main() {
  group('RoleView.fromJson', () {
    test('parses full payload', () {
      final v = RoleView.fromJson({
        'code': 'ai',
        'label': 'ИИ',
        'color': '#4CAF50',
      });
      expect(v.code, 'ai');
      expect(v.label, 'ИИ');
      expect(v.color, isNotNull);
      // hex 0x4CAF50, alpha forced to 0xFF
      expect(v.color!.toARGB32(), 0xFF4CAF50);
    });

    test('parses with color=null', () {
      final v = RoleView.fromJson({
        'code': 'user',
        'label': 'Пользователь',
        'color': null,
      });
      expect(v.code, 'user');
      expect(v.label, 'Пользователь');
      expect(v.color, isNull);
    });

    test('parses without color key', () {
      final v = RoleView.fromJson({'code': 'x', 'label': 'X'});
      expect(v.color, isNull);
    });

    test('invalid hex (wrong length) returns null color', () {
      final v = RoleView.fromJson({'code': 'x', 'label': 'X', 'color': '#abc'});
      expect(v.color, isNull);
    });

    test('invalid hex (no leading #) returns null color', () {
      final v = RoleView.fromJson({'code': 'x', 'label': 'X', 'color': '4CAF50'});
      expect(v.color, isNull);
    });

    test('invalid hex (non-hex chars) returns null color', () {
      final v = RoleView.fromJson({'code': 'x', 'label': 'X', 'color': '#zzzzzz'});
      expect(v.color, isNull);
    });

    test('accepts uppercase hex', () {
      final v = RoleView.fromJson({'code': 'x', 'label': 'X', 'color': '#ABCDEF'});
      expect(v.color, isNotNull);
      expect(v.color!.toARGB32(), 0xFFABCDEF);
    });

    test('accepts lowercase hex', () {
      final v = RoleView.fromJson({'code': 'x', 'label': 'X', 'color': '#abcdef'});
      expect(v.color, isNotNull);
      expect(v.color!.toARGB32(), 0xFFABCDEF);
    });
  });

  group('RoleView equality', () {
    test('same payload == same payload', () {
      const a = RoleView(code: 'ai', label: 'ИИ', color: Color(0xFF4CAF50));
      const b = RoleView(code: 'ai', label: 'ИИ', color: Color(0xFF4CAF50));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('different code != ', () {
      const a = RoleView(code: 'ai', label: 'X');
      const b = RoleView(code: 'user', label: 'X');
      expect(a, isNot(b));
    });

    test('null color != some color', () {
      const a = RoleView(code: 'x', label: 'X');
      const b = RoleView(code: 'x', label: 'X', color: Color(0xFF000000));
      expect(a, isNot(b));
    });

    test('extra_roles парсятся, учитываются в hasRole и равенстве', () {
      final v = RoleView.fromJson({
        'code': 'admin',
        'label': 'Администратор',
        'extra_roles': ['developer', '', 3],
      });
      expect(v.extraRoles, ['developer']);
      expect(v.hasRole('admin'), isTrue);
      expect(v.hasRole('developer'), isTrue);
      expect(v.hasRole('moderator'), isFalse);
      expect(v, isNot(const RoleView(code: 'admin', label: 'Администратор')));
      final plain = RoleView.fromJson({'code': 'admin', 'label': 'A'});
      expect(plain.extraRoles, isEmpty);
      expect(plain.hasRole('developer'), isFalse);
    });
  });
}
