import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class DetectionOverlay extends StatelessWidget {
  const DetectionOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        return Stack(
          children: [
            _DetectionBox(
              left: width * 0.49,
              top: height * 0.39,
              width: width * 0.25,
              height: height * 0.19,
              label: 'Player ID #7 Locked',
              color: AppColors.accent,
              solid: true,
            ),
            _DetectionBox(
              left: width * 0.23,
              top: height * 0.37,
              width: width * 0.16,
              height: height * 0.15,
              color: Colors.white70,
            ),
            _DetectionBox(
              left: width * 0.77,
              top: height * 0.36,
              width: width * 0.17,
              height: height * 0.13,
              color: Colors.white70,
            ),
            _DetectionBox(
              left: width * 0.20,
              top: height * 0.51,
              width: width * 0.18,
              height: height * 0.17,
              color: Colors.white70,
            ),
            Positioned(
              left: width * 0.50,
              top: height * 0.47,
              child: const _Crosshair(),
            ),
          ],
        );
      },
    );
  }
}

class _DetectionBox extends StatelessWidget {
  const _DetectionBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.color,
    this.label,
    this.solid = false,
  });

  final double left;
  final double top;
  final double width;
  final double height;
  final Color color;
  final String? label;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: solid
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: color, width: 2),
                    ),
                  )
                : CustomPaint(
                    painter: _DashedBorderPainter(color: color),
                  ),
          ),
          if (label != null)
            Positioned(
              left: 0,
              top: -27,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.track_changes_rounded,
                          size: 13, color: Colors.black),
                      const SizedBox(width: 5),
                      Text(
                        label!,
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: Colors.black,
                                  fontSize: 10,
                                ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Crosshair extends StatelessWidget {
  const _Crosshair();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: CustomPaint(
        painter: _CrosshairPainter(),
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.red
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(size.center(Offset.zero), 5, paint);
    canvas.drawLine(
        Offset(size.width / 2, 0), Offset(size.width / 2, 8), paint);
    canvas.drawLine(
      Offset(size.width / 2, size.height - 8),
      Offset(size.width / 2, size.height),
      paint,
    );
    canvas.drawLine(
        Offset(0, size.height / 2), Offset(8, size.height / 2), paint);
    canvas.drawLine(
      Offset(size.width - 8, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(4),
        ),
      );
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      const dash = 8.0;
      const gap = 6.0;
      while (distance < metric.length) {
        final next = distance + dash;
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
