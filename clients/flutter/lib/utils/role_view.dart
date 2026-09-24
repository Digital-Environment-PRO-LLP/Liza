import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Immutable view of a user role as received from the Synapse user_roles
/// catalog: a technical [code], a localized [label], and an optional [color].
///
/// The catalog is the source of truth - the client does not store any local
/// hardcoded mapping from code to label/color. If [color] is null, callers
/// should use a project-wide default (currently green `#4CAF50`).
@immutable
class RoleView {
  final String code;
  final String label;
  final Color? color;

  /// Персональные доп. роли поверх [code] (поле есть только у тех, кому его
  /// выставили admin-PUT'ом: владельцу — admin + developer). Бейдж, подпись и
  /// серверные гейты — по [code]; admin доп. ролью сервер не принимает.
  final List<String> extraRoles;

  const RoleView({
    required this.code,
    required this.label,
    this.color,
    this.extraRoles = const [],
  });

  factory RoleView.fromJson(Map<String, dynamic> json) => RoleView(
        code: json['code'] as String,
        label: json['label'] as String,
        color: _parseHex(json['color'] as String?),
        extraRoles: parseExtraRoles(json['extra_roles']),
      );

  static List<String> parseExtraRoles(Object? raw) => raw is List
      ? List.unmodifiable(raw.whereType<String>().where((r) => r.isNotEmpty))
      : const [];

  bool hasRole(String role) => code == role || extraRoles.contains(role);

  static Color? _parseHex(String? hex) {
    if (hex == null) return null;
    if (hex.length != 7 || !hex.startsWith('#')) return null;
    final raw = int.tryParse(hex.substring(1), radix: 16);
    if (raw == null) return null;
    return Color(raw | 0xFF000000);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RoleView &&
          other.code == code &&
          other.label == label &&
          other.color == color &&
          listEquals(other.extraRoles, extraRoles));

  @override
  int get hashCode =>
      Object.hash(code, label, color, Object.hashAll(extraRoles));
}
