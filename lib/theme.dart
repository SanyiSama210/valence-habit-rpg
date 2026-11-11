import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SystemTheme {
  // Deep Void Canvas & Modern Elevated Surfaces
  static const Color background = Color(0xFF070A0F);
  static const Color surface = Color(0xFF0F151F);
  static const Color surfaceElevated = Color(0xFF16202E);
  static const Color border = Color(0xFF1F2D40);
  static const Color borderSubtle = Color(0xFF141E2C);

  // System Mana & Awakening Palette
  static const Color cyan = Color(0xFF00E5FF);
  static const Color electricBlue = Color(0xFF2979FF);
  static const Color monarchGold = Color(0xFFFFB300);
  static const Color shadowViolet = Color(0xFFA855F7);
  static const Color dangerRed = Color(0xFFFF3366);
  static const Color clearGreen = Color(0xFF00E676);

  static TextStyle get titleStyle => const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
      );

  static TextStyle get captionStyle => const TextStyle(
        color: Color(0xFF7E92A8),
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.4,
      );

  static TextStyle get monoHeader => const TextStyle(
        color: cyan,
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.4,
        fontFamily: 'monospace',
      );
}

class SystemCard extends StatelessWidget {
  final Widget child;
  final Color borderColor;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;

  const SystemCard({
    super.key,
    required this.child,
    this.borderColor = SystemTheme.border,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final container = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: SystemTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            offset: const Offset(0, 4),
            blurRadius: 12,
          ),
          if (borderColor != SystemTheme.border)
            BoxShadow(
              color: borderColor.withValues(alpha: 0.12),
              offset: const Offset(0, 0),
              blurRadius: 10,
            ),
        ],
      ),
      child: child,
    );

    if (onTap == null) return container;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: container,
    );
  }
}

// Alias for add_task_screen compatibility
typedef SystemWindow = SystemCard;

class SystemButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry padding;
  final double fontSize;

  const SystemButton({
    super.key,
    required this.label,
    this.icon,
    this.color = SystemTheme.cyan,
    required this.onPressed,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    final bool active = onPressed != null;
    final Color c = active ? color : Colors.white24;

    return GestureDetector(
      onTap: active
          ? () {
              HapticFeedback.lightImpact();
              onPressed!();
            }
          : null,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: active ? c.withValues(alpha: 0.12) : const Color(0xFF0A0F16),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? c.withValues(alpha: 0.75) : SystemTheme.border,
            width: 1.0,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: c.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 0),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: c, size: fontSize + 3),
              const SizedBox(width: 6),
            ],
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: c,
                fontWeight: FontWeight.w900,
                fontSize: fontSize,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SystemGauge extends StatelessWidget {
  final double value;
  final Color color;
  final double height;

  const SystemGauge({
    super.key,
    required this.value,
    required this.color,
    this.height = 6,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: SystemTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(height),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Align(
            alignment: Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              width: constraints.maxWidth * clamped,
              height: height,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(height),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.6),
                    blurRadius: 6,
                    offset: const Offset(0, 0),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}