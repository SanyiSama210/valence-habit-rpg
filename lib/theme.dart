import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ValencePalette {
  static const Color bgCanvas = Color(0xFF131F24);
  static const Color bgCard = Color(0xFF1B2B32);
  static const Color bgRecessed = Color(0xFF101A1E);
  static const Color borderLip = Color(0xFF2B3F48);

  static const Color green = Color(0xFF58CC02);
  static const Color greenLip = Color(0xFF46A302);

  static const Color blue = Color(0xFF1CB0F6);
  static const Color blueLip = Color(0xFF1185BC);

  static const Color gold = Color(0xFFFFC800);
  static const Color goldLip = Color(0xFFD6A400);

  static const Color orange = Color(0xFFFF9600);
  static const Color orangeLip = Color(0xFFCC7800);

  static const Color red = Color(0xFFFF4B4B);
  static const Color redLip = Color(0xFFCC3232);

  static const Color purple = Color(0xFFCE82FF);
  static const Color purpleLip = Color(0xFFA559D9);

  static Color darkenLip(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness - 0.14).clamp(0.0, 1.0)).toColor();
  }
}

class TactileCard extends StatelessWidget {
  final Widget child;
  final Color bgColor;
  final Color borderColor;
  final Color? lipColor;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final VoidCallback? onTap;

  const TactileCard({
    super.key,
    required this.child,
    this.bgColor = ValencePalette.bgCard,
    this.borderColor = ValencePalette.borderLip,
    this.lipColor,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = 20,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveLip = lipColor ?? borderColor;
    final card = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: effectiveLip,
            offset: const Offset(0, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: child,
    );

    if (onTap == null) return card;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: card,
    );
  }
}

class TactileButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final Color? textColor;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry padding;
  final double fontSize;
  final double borderRadius;

  const TactileButton({
    super.key,
    required this.label,
    this.icon,
    this.color = ValencePalette.green,
    this.textColor,
    required this.onPressed,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
    this.fontSize = 13,
    this.borderRadius = 14,
  });

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    final Color bg = enabled ? color : const Color(0xFF22343C);
    final Color lip = enabled ? ValencePalette.darkenLip(color) : const Color(0xFF17242A);
    final Color fg = enabled ? (textColor ?? const Color(0xFF0F191E)) : Colors.white30;

    return GestureDetector(
      onTap: enabled
          ? () {
              HapticFeedback.lightImpact();
              onPressed!();
            }
          : null,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: [
            BoxShadow(
              color: lip,
              offset: Offset(0, enabled ? 4 : 2),
              blurRadius: 0,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: fg, size: fontSize + 3),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w900,
                fontSize: fontSize,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ShineProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  final double height;
  final Color bgColor;

  const ShineProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 14,
    this.bgColor = ValencePalette.bgRecessed,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(height),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fillWidth = max(clamped > 0 ? height : 0.0, constraints.maxWidth * clamped);
          return Align(
            alignment: Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              width: fillWidth,
              height: height,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(height),
              ),
              child: fillWidth > 16
                  ? Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        margin: EdgeInsets.only(top: height * 0.18, left: 6, right: 6),
                        height: height * 0.26,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(height),
                        ),
                      ),
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }
}