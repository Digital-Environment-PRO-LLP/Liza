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

  const RoleView({
    required this.code,
    required this.label,
    this.color,
  });

  factory RoleView.fromJson(Map<String, dynamic> json) => RoleView(
        code: json['code'] as String,
        label: json['label'] as String,
        color: _parseHex(json['color'] as String?),
      );

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
          other.color == color);

  @override
  int get hashCode => Object.hash(code, label, color);
}
