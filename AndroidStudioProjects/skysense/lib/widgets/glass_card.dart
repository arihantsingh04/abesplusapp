import 'dart:ui'; // Import needed for ImageFilter
import 'package:flutter/material.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final double? width;
  final double? height;
  final bool lightened;
  final VoidCallback? onTap;
  final double borderWidth;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius,
    this.width,
    this.height,
    this.lightened = false,
    this.onTap,
    this.borderWidth = 1.7,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBorderRadius = borderRadius ?? BorderRadius.circular(20);

    return Container(
      width: width,
      height: height,
      margin: margin,
      child: ClipRRect(
        borderRadius: effectiveBorderRadius,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: effectiveBorderRadius,
            // keep splash subtle so content stays readable
            splashColor: Colors.white.withOpacity(0.04),
            highlightColor: Colors.white.withOpacity(0.02),
            child: CustomPaint(
              // draw the border on the foreground so the child & background remain untouched
              foregroundPainter: _GradientBorderPainter(
                radius: effectiveBorderRadius,
                strokeWidth: borderWidth,
                lightened: lightened,
              ),
              child: BackdropFilter(
                // Add blur filter
                filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                child: Container(
                  padding: padding,
                  // subtle glass gradient background (as in your original code)
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        // Darker, more opaque colors for "darkness"
                        Colors.black.withOpacity(lightened ? 0.4 : 0.4),
                        Colors.black.withOpacity(lightened ? 0.5 : 0.2),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: effectiveBorderRadius,
                    // no extra border or shadows here — border is painted by CustomPainter
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GradientBorderPainter extends CustomPainter {
  final BorderRadius radius;
  final double strokeWidth;
  final bool lightened;

  _GradientBorderPainter({
    required this.radius,
    required this.strokeWidth,
    this.lightened = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final half = strokeWidth / 2;

    final innerRect = Rect.fromLTWH(
      rect.left + half,
      rect.top + half,
      (rect.width - strokeWidth).clamp(0.0, rect.width),
      (rect.height - strokeWidth).clamp(0.0, rect.height),
    );

    final rrect = RRect.fromRectAndCorners(
      innerRect,
      topLeft: radius.topLeft,
      topRight: radius.topRight,
      bottomLeft: radius.bottomLeft,
      bottomRight: radius.bottomRight,
    );

    // Colors: bright at top-left & bottom-right; darker at top-right & bottom-left
    final bright = Colors.white.withOpacity(lightened ? 0.3 : 0.2);
    final dark = Colors.black.withOpacity(0.25);

    // gradient diagonal: bright -> dark -> bright
    final shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [bright, dark, bright],
      stops: const [0.0, 0.3, 1.0],
    ).createShader(innerRect);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true
      ..shader = shader;

    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _GradientBorderPainter old) {
    return old.strokeWidth != strokeWidth ||
        old.lightened != lightened ||
        old.radius != radius;
  }
}