import 'dart:math';

import 'package:flutter/material.dart';

/// Flat-top hexagonal clipper for AI account avatars.
class HexagonClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => _hexagonPath(size);

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Hexagonal [OutlinedBorder] for use with [Material.shape].
class HexagonBorder extends OutlinedBorder {
  const HexagonBorder({super.side});

  @override
  OutlinedBorder copyWith({BorderSide? side}) =>
      HexagonBorder(side: side ?? this.side);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    final inset = side.width;
    return _hexagonPath(
      Size(rect.width - inset * 2, rect.height - inset * 2),
      offset: Offset(rect.left + inset, rect.top + inset),
    );
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _hexagonPath(rect.size, offset: rect.topLeft);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    final paint = side.toPaint();
    canvas.drawPath(getOuterPath(rect), paint);
  }

  @override
  ShapeBorder scale(double t) =>
      HexagonBorder(side: side.scale(t));

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);
}

/// Builds a flat-top hexagon path fitting within [size],
/// optionally offset by [offset].
Path _hexagonPath(Size size, {Offset offset = Offset.zero}) {
  final path = Path();
  final w = size.width;
  final h = size.height;
  final cx = w / 2 + offset.dx;
  final cy = h / 2 + offset.dy;
  final r = min(w, h) / 2;

  for (var i = 0; i < 6; i++) {
    // -30° offset for flat-top orientation
    final angle = (60 * i - 30) * pi / 180;
    final x = cx + r * cos(angle);
    final y = cy + r * sin(angle);
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  path.close();
  return path;
}
