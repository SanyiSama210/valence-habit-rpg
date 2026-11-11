import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme.dart';

typedef JsonMap = Map<String, dynamic>;
typedef JsonList = List<JsonMap>;
typedef SlotRange = Map<String, int>;

class SystemRanks {
  static const JsonList hunterLadder = [
    {'index': 0, 'name': 'E-Rank', 'short': 'E', 'minRr': 0},
    {'index': 1, 'name': 'D-Rank', 'short': 'D', 'minRr': 500},
    {'index': 2, 'name': 'C-Rank', 'short': 'C', 'minRr': 1400},
    {'index': 3, 'name': 'B-Rank', 'short': 'B', 'minRr': 2800},
    {'index': 4, 'name': 'A-Rank', 'short': 'A', 'minRr': 5000},
    {'index': 5, 'name': 'S-Rank', 'short': 'S', 'minRr': 8500},
    {'index': 6, 'name': 'SS-Rank', 'short': 'SS', 'minRr': 13500},
    {'index': 7, 'name': 'SSS-Rank', 'short': 'SSS', 'minRr': 20500},
    {'index': 8, 'name': 'National-Level', 'short': 'NAT', 'minRr': 30000},
    {'index': 9, 'name': 'Monarch', 'short': 'MONARCH', 'minRr': 45000},
  ];

  static int getRankIndex(int rr) {
    int idx = 0;
    for (int i = 0; i < hunterLadder.length; i++) {
      if (rr >= (hunterLadder[i]['minRr'] as int)) {
        idx = i;
      }
    }
    return idx;
  }

  static String getRankName(int rr) => hunterLadder[getRankIndex(rr)]['name'] as String;

  static int getSkillRankNumeric(int xp) {
    if (xp >= 3000) return 6; // S
    if (xp >= 1500) return 5; // A
    if (xp >= 700) return 4;  // B
    if (xp >= 300) return 3;  // C
    if (xp >= 100) return 2;  // D
    return 1;                 // E
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

  static Color getLetterColor(String letter, Color defaultAccent) {
    switch (letter) {
      case 'S':
        return ValencePalette.gold;
      case 'A':
        return ValencePalette.red;
      case 'B':
        return ValencePalette.purple;
      case 'C':
        return ValencePalette.blue;
      case 'D':
        return ValencePalette.green;
      default:
        return defaultAccent;
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
    final center = Offset(size.width / 2, size.height / 2 + 6);
    final double maxRadius = min(size.width, size.height) * 0.35;
    const labels = ['STR', 'VIT', 'INT', 'PER', 'AGI'];
    final values = [strLv, vitLv, intLv, perLv, agiLv];
    final int maxVal = max(15, values.reduce(max) + 2);

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

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
      final norm = (values[i] / maxVal).clamp(0.18, 1.0);
      final pt = Offset(center.dx + cos(angle) * maxRadius * norm, center.dy + sin(angle) * maxRadius * norm);
      if (i == 0) {
        statPath.moveTo(pt.dx, pt.dy);
      } else {
        statPath.lineTo(pt.dx, pt.dy);
      }

      final outerPt = Offset(center.dx + cos(angle) * maxRadius, center.dy + sin(angle) * maxRadius);
      canvas.drawLine(center, outerPt, gridPaint);

      final labelPt = Offset(center.dx + cos(angle) * (maxRadius + 22) - 18, center.dy + sin(angle) * (maxRadius + 16) - 7);
      final tp = TextPainter(
        text: TextSpan(
          text: "${labels[i]}${values[i]}",
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, labelPt);
    }
    statPath.close();

    canvas.drawPath(statPath, Paint()..color = auraColor.withValues(alpha: 0.28)..style = PaintingStyle.fill);
    canvas.drawPath(statPath, Paint()..color = auraColor..style = PaintingStyle.stroke..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(covariant AttributeRadarPainter oldDelegate) => true;
}

class RankAscensionDialog extends StatelessWidget {
  final String newRankName;
  final Color accentColor;
  final VoidCallback onClaimed;

  const RankAscensionDialog({
    super.key,
    required this.newRankName,
    required this.accentColor,
    required this.onClaimed,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: TactileCard(
            borderColor: ValencePalette.gold,
            lipColor: ValencePalette.goldLip,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.emoji_events_rounded, color: ValencePalette.gold, size: 64),
                const SizedBox(height: 12),
                const Text("LEAGUE PROMOTION!", style: TextStyle(color: ValencePalette.gold, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1)),
                const SizedBox(height: 6),
                Text(
                  newRankName.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Your daily consistency unlocked the next rank tier!",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: TactileButton(
                    label: "CLAIM RANK",
                    color: ValencePalette.gold,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    fontSize: 14,
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