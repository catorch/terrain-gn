import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Draws the plot from its corner markers with edge lengths, so a buyer can compare it with the
/// survey plan without downloading map tiles. `geographic` corners are [lon, lat]; otherwise metres (UTM).
class ParcelOutline extends StatelessWidget {
  const ParcelOutline({super.key, required this.corners, this.geographic = true, this.height = 220});

  final List<List<double>> corners;
  final bool geographic;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        decoration: BoxDecoration(color: Palette.sandDeep.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(Space.radius)),
        child: CustomPaint(painter: _OutlinePainter(_toMetres(corners, geographic)), size: Size.infinite),
      );

  static List<Offset> _toMetres(List<List<double>> corners, bool geographic) {
    var points = corners;
    if (points.length > 1 && points.first[0] == points.last[0] && points.first[1] == points.last[1]) points = points.sublist(0, points.length - 1);
    if (!geographic) return [for (final p in points) Offset(p[0], -p[1])];
    final lat0 = points.isEmpty ? 0.0 : points.map((p) => p[1]).reduce((a, b) => a + b) / points.length;
    final mx = 111320 * cos(lat0 * pi / 180);
    return [for (final p in points) Offset(p[0] * mx, -p[1] * 110610)];
  }
}

class _OutlinePainter extends CustomPainter {
  _OutlinePainter(this.points);

  final List<Offset> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const pad = 36.0;
    final left = points.map((p) => p.dx).reduce(min), right = points.map((p) => p.dx).reduce(max);
    final top = points.map((p) => p.dy).reduce(min), bottom = points.map((p) => p.dy).reduce(max);
    final span = max(max(right - left, bottom - top), 1.0);
    final scale = min(size.width - 2 * pad, size.height - 2 * pad) / span;
    final centre = Offset((left + right) / 2, (top + bottom) / 2);
    final screen = [for (final p in points) size.center(Offset.zero) + (p - centre) * scale];

    final path = Path()..addPolygon(screen, points.length > 2);
    if (points.length > 2) canvas.drawPath(path, Paint()..color = Palette.green.withValues(alpha: 0.16));
    canvas.drawPath(path, Paint()
      ..color = Palette.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round);

    final edges = points.length > 2 ? points.length : points.length - 1;
    for (var i = 0; i < edges; i++) {
      final j = (i + 1) % points.length;
      final metres = (points[j] - points[i]).distance;
      _label(canvas, (screen[i] + screen[j]) / 2, '${metres.toStringAsFixed(metres < 10 ? 1 : 0)} m', Palette.ink, Colors.white);
    }
    for (var i = 0; i < screen.length; i++) {
      canvas.drawCircle(screen[i], 9, Paint()..color = Palette.green);
      _label(canvas, screen[i], '${i + 1}', Colors.white, null);
    }
  }

  void _label(Canvas canvas, Offset at, String text, Color color, Color? background) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    final box = Rect.fromCenter(center: at, width: painter.width + 8, height: painter.height + 4);
    if (background != null) canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(6)), Paint()..color = background.withValues(alpha: 0.9));
    painter.paint(canvas, at - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(_OutlinePainter old) => old.points != points;
}
