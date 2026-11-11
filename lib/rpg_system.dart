import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme.dart';

typedef JsonMap = Map<String, dynamic>;
typedef JsonList = List<JsonMap>;
typedef SlotRange = Map<String, int>;

class SystemRanks {
  static const JsonList rankLadder = [
    {'index': 0, 'name': 'E-Rank', 'short': 'E', 'minRr': 0, 'desc': 'Unawakened entry tier. Low survival potential.'},
    {'index': 1, 'name': 'D-Rank', 'short': 'D', 'minRr': 500, 'desc': 'Basic combat readiness. Foundation established.'},
    {'index': 2, 'name': 'C-Rank', 'short': 'C', 'minRr': 1400, 'desc': 'Competent operative. Routine dungeon clearance.'},
    {'index': 3, 'name': 'B-Rank', 'short': 'B', 'minRr': 2800, 'desc': 'Elite team leader. Advanced tactical mastery.'},
    {'index': 4, 'name': 'A-Rank', 'short': 'A', 'minRr': 5000, 'desc': 'High-tier hunter. Raid leader capable of gate soloing.'},
    {'index': 5, 'name': 'S-Rank', 'short': 'S', 'minRr': 8500, 'desc': 'Top-echelon anomaly. Strategic human deterrence.'},
    {'index': 6, 'name': 'SS-Rank', 'short': 'SS', 'minRr': 13500, 'desc': 'Transcendental power exceeding global rating caps.'},
    {'index': 7, 'name': 'SSS-Rank', 'short': 'SSS', 'minRr': 20500, 'desc': 'Continental apex. Catastrophic red gate defense.'},
    {'index': 8, 'name': 'National', 'short': 'NAT', 'minRr': 30000, 'desc': 'Nation-level authority. Equivalent to sovereign armies.'},
    {'index': 9, 'name': 'Monarch', 'short': 'MONARCH', 'minRr': 45000, 'desc': 'Absolute sovereign of the shadow realm.'},
  ];

  static int getRankIndex(int rr) {
    int idx = 0;
    for (int i = 0; i < rankLadder.length; i++) {
      if (rr >= (rankLadder[i]['minRr'] as int)) {
        idx = i;
      }
    }
    return idx;
  }

  static String getRankName(int rr) => rankLadder[getRankIndex(rr)]['name'] as String;

  static int getSkillRankNumeric(int xp) {
    if (xp >= 3000) return 6;
    if (xp >= 1500) return 5;
    if (xp >= 700) return 4;
    if (xp >= 300) return 3;
    if (xp >= 100) return 2;
    return 1;
  }

  static String numericToLetter(int numRank) {
    switch (numRank.clamp(1, 6)) {
      case 6:
        return 'S';
      case 5:
        return 'A';
      case 4:
        return 'B';
      case 3:
        return 'C';
      case 2:
        return 'D';
      default:
        return 'E';
    }
  }

  static String getSkillRankLetter(int xp) => numericToLetter(getSkillRankNumeric(xp));

  static int getNextSkillThreshold(int xp) {
    if (xp < 100) return 100;
    if (xp < 300) return 300;
    if (xp < 700) return 700;
    if (xp < 1500) return 1500;
    if (xp < 3000) return 3000;
    return 5000;
  }

  static int getPrevSkillThreshold(int xp) {
    if (xp < 100) return 0;
    if (xp < 300) return 100;
    if (xp < 700) return 300;
    if (xp < 1500) return 700;
    if (xp < 3000) return 1500;
    return 3000;
  }

  static double getSkillRrBonusMultiplier(int xp) {
    switch (getSkillRankNumeric(xp)) {
      case 6:
        return 0.20;
      case 5:
        return 0.15;
      case 4:
        return 0.10;
      case 3:
        return 0.06;
      case 2:
        return 0.03;
      default:
        return 0.0;
    }
  }

  static Color getLetterColor(String letter, Color fallback) {
    switch (letter) {
      case 'S':
        return SystemTheme.monarchGold;
      case 'A':
        return SystemTheme.shadowViolet;
      case 'B':
        return SystemTheme.electricBlue;
      case 'C':
        return SystemTheme.cyan;
      case 'D':
        return SystemTheme.clearGreen;
      default:
        return fallback;
    }
  }
}

class AutoStatClassifier {
  static JsonMap classify(String title) {
    final q = title.toLowerCase();
    if (q.contains('kickbox') || q.contains('muay thai') || q.contains('striking') || q.contains('pads') || q.contains('sparring') || q.contains('boxing')) {
      return {'category': 'Fitness', 'primary': 'AGI', 'secondary': 'PER', 'isBoss': q.contains('tournament') || q.contains('fight')};
    }
    if (q.contains('bjj') || q.contains('jiu-jitsu') || q.contains('jiu jitsu') || q.contains('grappling') || q.contains('no-gi') || q.contains('rolling') || q.contains('wrestling')) {
      return {'category': 'Fitness', 'primary': 'INT', 'secondary': 'STR', 'isBoss': q.contains('tournament') || q.contains('belt')};
    }
    if (q.contains('mma') || q.contains('cage') || q.contains('mixed martial')) {
      return {'category': 'Fitness', 'primary': 'VIT', 'secondary': 'AGI', 'isBoss': q.contains('fight') || q.contains('tournament')};
    }
    if (q.contains('push') || q.contains('pull') || q.contains('bench') || q.contains('squat') || q.contains('gym') || q.contains('lift') || q.contains('hypertrophy') || q.contains('weights')) {
      return {'category': 'Fitness', 'primary': 'STR', 'secondary': 'VIT', 'isBoss': q.contains('pr ') || q.contains('max')};
    }
    if (q.contains('run') || q.contains('sprint') || q.contains('cardio') || q.contains('swim') || q.contains('cycling') || q.contains('hiit')) {
      return {'category': 'Fitness', 'primary': 'AGI', 'secondary': 'VIT', 'isBoss': q.contains('race') || q.contains('marathon')};
    }
    if (q.contains('exam') || q.contains('midterm') || q.contains('final') || q.contains('thesis') || q.contains('dissertation') || q.contains('accounting') || q.contains('audit') || q.contains('study') || q.contains('seminar') || q.contains('lecture') || q.contains('code')) {
      return {'category': 'Academic', 'primary': 'INT', 'secondary': 'PER', 'isBoss': q.contains('exam') || q.contains('midterm') || q.contains('defense')};
    }
    if (q.contains('debate') || q.contains('judge') || q.contains('read') || q.contains('research') || q.contains('review') || q.contains('chess')) {
      return {'category': 'Academic', 'primary': 'PER', 'secondary': 'INT', 'isBoss': q.contains('tournament')};
    }
    if (q.contains('mobility') || q.contains('stretch') || q.contains('hydrate') || q.contains('recovery') || q.contains('walk') || q.contains('posture')) {
      return {'category': 'General', 'primary': 'VIT', 'secondary': 'PER', 'isBoss': false};
    }
    return {'category': 'General', 'primary': 'INT', 'secondary': 'PER', 'isBoss': false};
  }
}

class AttributeRadarPainter extends CustomPainter {
  final int strLv;
  final int vitLv;
  final int intLv;
  final int perLv;
  final int agiLv;
  final Color auraColor;

  AttributeRadarPainter({
    required this.strLv,
    required this.vitLv,
    required this.intLv,
    required this.perLv,
    required this.agiLv,
    required this.auraColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final double maxRadius = min(size.width, size.height) * 0.35;
    const labels = ['STR', 'VIT', 'INT', 'PER', 'AGI'];
    final values = [strLv, vitLv, intLv, perLv, agiLv];
    final int maxVal = max(15, values.reduce(max) + 2);

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int ring = 1; ring <= 3; ring++) {
      final r = maxRadius * (ring / 3);
      final path = ui.Path();
      for (int i = 0; i < 5; i++) {
        final angle = -pi / 2 + (i * 2 * pi / 5);
        final pt = Offset(center.dx + cos(angle) * r, center.dy + sin(angle) * r);
        if (i == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }

    final statPath = ui.Path();
    for (int i = 0; i < 5; i++) {
      final angle = -pi / 2 + (i * 2 * pi / 5);
      final norm = (values[i] / maxVal).clamp(0.2, 1.0);
      final pt = Offset(center.dx + cos(angle) * maxRadius * norm, center.dy + sin(angle) * maxRadius * norm);
      if (i == 0) {
        statPath.moveTo(pt.dx, pt.dy);
      } else {
        statPath.lineTo(pt.dx, pt.dy);
      }

      final outerPt = Offset(center.dx + cos(angle) * maxRadius, center.dy + sin(angle) * maxRadius);
      canvas.drawLine(center, outerPt, gridPaint);

      // Point 8: Format as "STAT · N" without "Lv."
      final labelPt = Offset(center.dx + cos(angle) * (maxRadius + 22) - 18, center.dy + sin(angle) * (maxRadius + 14) - 8);
      final tp = TextPainter(
        text: TextSpan(
          text: "${labels[i]} ·${values[i]}",
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, labelPt);
    }
    statPath.close();

    canvas.drawPath(statPath, Paint()..color = auraColor.withValues(alpha: 0.22)..style = PaintingStyle.fill);
    canvas.drawPath(statPath, Paint()..color = auraColor..style = PaintingStyle.stroke..strokeWidth = 2.0);
  }

  @override
  bool shouldRepaint(covariant AttributeRadarPainter oldDelegate) => true;
}

class RankAscensionDialog extends StatelessWidget {
  final String newRankName;
  final VoidCallback onClaimed;

  const RankAscensionDialog({
    super.key,
    required this.newRankName,
    required this.onClaimed,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SystemCard(
            borderColor: SystemTheme.cyan,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bolt, color: SystemTheme.cyan, size: 20),
                    SizedBox(width: 8),
                    Text(
                      "[ SYSTEM NOTIFICATION ]",
                      style: TextStyle(color: SystemTheme.cyan, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  newRankName.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  "You have cleared the necessary rating threshold.\nSystem evaluation grade upgraded.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: SystemButton(
                    label: "CONFIRM PROMOTION",
                    color: SystemTheme.cyan,
                    onPressed: onClaimed,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}