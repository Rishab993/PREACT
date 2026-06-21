import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';

/// Animated arc severity gauge (0.0 to 1.0)
class SeverityGauge extends StatelessWidget {
  final double value; // 0.0 to 1.0
  final double size;
  final String? label;
  final bool showPercent;
  final double strokeWidth;

  const SeverityGauge({
    super.key,
    required this.value,
    this.size = 100,
    this.label,
    this.showPercent = true,
    this.strokeWidth = 10,
  });

  Color get _color => AppColors.fromSeverity(value.clamp(0, 1));

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (_, animVal, __) {
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(size, size),
                painter: _GaugePainter(
                  value: animVal,
                  color: _color,
                  strokeWidth: strokeWidth,
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (showPercent)
                    Text(
                      '${(animVal * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: _color,
                        fontSize: size * 0.18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                  if (label != null)
                    Text(
                      label!,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: size * 0.10,
                      ),
                      textAlign: TextAlign.center,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  final Color color;
  final double strokeWidth;

  _GaugePainter({required this.value, required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    const startAngle = math.pi * 0.75;  // 135°
    const sweepAngle = math.pi * 1.5;   // 270°

    // Background arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      Paint()
        ..color = AppColors.borderDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );

    // Colored progress arc
    if (value > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle * value,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );

      // Glow effect
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle * value,
        false,
        Paint()
          ..color = color.withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth + 4
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value || old.color != color;
}
