import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/rpg_system.dart';

void main() {
  group('Valence Core RPG & Classifier Tests', () {
    test('Rank ladder thresholds map correctly up to Monarch', () {
      expect(SystemRanks.getRankName(0), 'E-Rank');
      expect(SystemRanks.getRankName(500), 'D-Rank');
      expect(SystemRanks.getRankName(2800), 'B-Rank');
      expect(SystemRanks.getRankName(5000), 'A-Rank');
      expect(SystemRanks.getRankName(45000), 'Monarch');
      expect(SystemRanks.getRankName(999999), 'Monarch');
    });

    test('Skill ranks and floor-rounded averages calculate accurately', () {
      expect(SystemRanks.getSkillRankLetter(0), 'E');
      expect(SystemRanks.getSkillRankLetter(120), 'D');
      expect(SystemRanks.getSkillRankLetter(340), 'C');
      expect(SystemRanks.getSkillRankLetter(750), 'B');
      expect(SystemRanks.getSkillRankLetter(1600), 'A');
      expect(SystemRanks.getSkillRankLetter(3500), 'S');

      final int bNum = SystemRanks.getSkillRankNumeric(750);
      final int cNum = SystemRanks.getSkillRankNumeric(340);
      final int flooredAvg = ((bNum + cNum) / 2).floor();
      expect(SystemRanks.numericToLetter(flooredAvg), 'C');
    });

    test('AutoStatClassifier correctly routes disciplines and boss gates', () {
      final bjj = AutoStatClassifier.classify('No-Gi BJJ Rolling');
      expect(bjj['category'], 'Fitness');
      expect(bjj['primary'], 'INT');
      expect(bjj['secondary'], 'STR');

      final kb = AutoStatClassifier.classify('Kickboxing Sparring');
      expect(kb['primary'], 'AGI');
      expect(kb['secondary'], 'PER');

      final exam = AutoStatClassifier.classify('Accounting Midterm Exam');
      expect(exam['category'], 'Academic');
      expect(exam['isBoss'], true);
    });
  });
}