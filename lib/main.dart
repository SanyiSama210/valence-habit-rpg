import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:path/path.dart' show join;
import 'package:sqflite/sqflite.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

typedef JsonMap = Map<String, dynamic>;
typedef JsonList = List<JsonMap>;
typedef SlotRange = Map<String, int>;

final FlutterLocalNotificationsPlugin notificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  try {
    final dynamic tzInfo = await FlutterTimezone.getLocalTimezone();
    String tzName = 'Europe/Bucharest';
    try {
      tzName = tzInfo.name as String;
    } catch (_) {
      tzName = tzInfo.toString();
    }
    tz.setLocalLocation(tz.getLocation(tzName));
  } catch (_) {
    tz.setLocalLocation(tz.getLocation('Europe/Bucharest'));
  }

  const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings = InitializationSettings(android: androidSettings);

  await notificationsPlugin.initialize(settings: initSettings);

  final androidImpl = notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  if (androidImpl != null) {
    const AndroidNotificationChannel questChannel = AndroidNotificationChannel(
      'quest_reminders_v2',
      'Quest Reminders',
      description: 'Advance alarms for classes and workout routines',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    const AndroidNotificationChannel streakChannel = AndroidNotificationChannel(
      'streak_channel_v2',
      'Streak Protection',
      description: 'Reminders to protect your streak before midnight',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    const AndroidNotificationChannel penaltyChannel = AndroidNotificationChannel(
      'quest_penalties',
      'Quest Penalties',
      description: 'Notifications for missed quest deadlines',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    const AndroidNotificationChannel surgeChannel = AndroidNotificationChannel(
      'surge_quests',
      'Surge Micro-Quests',
      description: 'Random productivity prompts popping up in your free time',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await androidImpl.createNotificationChannel(questChannel);
    await androidImpl.createNotificationChannel(streakChannel);
    await androidImpl.createNotificationChannel(penaltyChannel);
    await androidImpl.createNotificationChannel(surgeChannel);
    await androidImpl.requestNotificationsPermission();
    await androidImpl.requestExactAlarmsPermission();
  }

  runApp(const MaterialApp(
    title: 'Valence',
    home: HabitApp(),
    debugShowCheckedModeBanner: false,
  ));
}

// ============================================================================
// RPG CONSTANTS & AUTO-STAT CLASSIFIER
// ============================================================================

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
        return const Color(0xFFFBBF24);
      case 'A':
        return const Color(0xFFF43F5E);
      case 'B':
        return const Color(0xFFA855F7);
      case 'C':
        return const Color(0xFF38BDF8);
      case 'D':
        return const Color(0xFF10B981);
      default:
        return defaultAccent.withValues(alpha: 0.8);
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

// ============================================================================
// MAIN APPLICATION STATE
// ============================================================================

class HabitApp extends StatefulWidget {
  const HabitApp({super.key});

  @override
  State<HabitApp> createState() => _HabitAppState();
}

class _HabitAppState extends State<HabitApp> {
  Database? _database;

  int currentStreak = 0;
  int highestStreak = 0;
  int perfectStreak = 0;
  int highestPerfectStreak = 0;
  int shieldCharges = 0;
  int totalRr = 0;
  int highestRankIdx = 0;

  int strXp = 400;
  int vitXp = 300;
  int intXp = 600;
  int perXp = 400;
  int agiXp = 300;

  double sleepHours = 7.8;
  String sleepTier = 'well_rested';
  String sleepLoggedDate = '';

  int _uiColorOverride = 0xFF38BDF8; // Clean Sky Blue default

  int _selectedTabIndex = 0;
  String _selectedCategoryFilter = 'All';
  late DateTime _selectedCalendarDate;
  late DateTime _calendarMonthCursor;
  final DateTime _today = DateTime.now();

  JsonList _allTasks = [];
  JsonList _todayTasks = [];
  JsonList _calendarDayTasks = [];
  JsonList _skills = [];
  List<String> _skillCategories = ['Combat', 'Intellect', 'Conditioning'];

  final Set<String> _expandedSkillCategories = {'Combat', 'Intellect', 'Conditioning'};

  JsonMap? _activeSurgeQuest;
  bool _surgeGambleArmed = false;

  static const JsonList microQuestPool = [
    {'title': '25 Push-ups Reset', 'category': 'Fitness', 'primary': 'STR', 'secondary': 'VIT', 'baseRr': 25, 'desc': 'Quick upper-body activation away from your desk.'},
    {'title': '15-Minute Flash Recall', 'category': 'Academic', 'primary': 'INT', 'secondary': 'PER', 'baseRr': 30, 'desc': 'Review key seminar notes or formulas without distractions.'},
    {'title': '3-Min Shadowboxing Footwork', 'category': 'Fitness', 'primary': 'AGI', 'secondary': 'PER', 'baseRr': 25, 'desc': 'Light angles, pivots, and guard checks.'},
    {'title': 'Desk Reset & 500ml Water', 'category': 'General', 'primary': 'VIT', 'secondary': 'PER', 'baseRr': 20, 'desc': 'Hydrate and clear your workspace.'},
  ];

  static final JsonList themePalette = [
    {'name': 'Sky Blue', 'color': const Color(0xFF38BDF8)},
    {'name': 'Indigo Violet', 'color': const Color(0xFF818CF8)},
    {'name': 'Emerald', 'color': const Color(0xFF10B981)},
    {'name': 'Amber Gold', 'color': const Color(0xFFFBBF24)},
    {'name': 'Rose Coral', 'color': const Color(0xFFF43F5E)},
  ];

  @override
  void initState() {
    super.initState();
    _selectedCalendarDate = DateTime(_today.year, _today.month, _today.day);
    _calendarMonthCursor = DateTime(_today.year, _today.month, 1);
    _startApp();
  }

  Color get accentColor => Color(_uiColorOverride == -1 ? 0xFF38BDF8 : _uiColorOverride);

  double get sleepRrMultiplier {
    if (sleepTier == 'fatigue') return 0.80;
    if (sleepTier == 'well_rested') return 1.15;
    return 1.00;
  }

  String get sleepShortLabel {
    if (sleepTier == 'fatigue') return '${sleepHours.toStringAsFixed(1)}h (-20%)';
    if (sleepTier == 'well_rested') return '${sleepHours.toStringAsFixed(1)}h (+15%)';
    return '${sleepHours.toStringAsFixed(1)}h (1.0x)';
  }

  Color get sleepTierColor {
    if (sleepTier == 'fatigue') return const Color(0xFFF43F5E);
    if (sleepTier == 'well_rested') return const Color(0xFF10B981);
    return accentColor;
  }

  String _classifySleepHours(double hours) {
    if (hours >= 1.0 && hours < 5.0) return 'fatigue';
    if (hours >= 7.0 && hours <= 9.5) return 'well_rested';
    return 'standard';
  }

  JsonMap? _findSkillById(int id) {
    if (id == -1) return null;
    for (final s in _skills) {
      if (s['id'] == id) return s;
    }
    return null;
  }

  Future<void> _setAccentColor(int colorValue) async {
    HapticFeedback.selectionClick();
    setState(() => _uiColorOverride = colorValue);
    final db = await database;
    await db.update('user_profile', {'ui_color_override': colorValue}, where: 'id = ?', whereArgs: [1]);
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'habits.db');

    _database = await openDatabase(
      path,
      version: 17,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE user_profile (
            id INTEGER PRIMARY KEY,
            current_streak INTEGER NOT NULL,
            highest_streak INTEGER DEFAULT 0,
            perfect_streak INTEGER DEFAULT 0,
            highest_perfect_streak INTEGER DEFAULT 0,
            shield_charges INTEGER DEFAULT 0,
            last_completed_date TEXT,
            last_perfect_date TEXT,
            total_rr INTEGER DEFAULT 0,
            highest_rank_level INTEGER DEFAULT 0,
            last_evaluated_date TEXT,
            ui_color_override INTEGER DEFAULT 4281908728,
            emblem_color_override INTEGER DEFAULT -1,
            str_xp INTEGER DEFAULT 0,
            vit_xp INTEGER DEFAULT 0,
            int_xp INTEGER DEFAULT 0,
            per_xp INTEGER DEFAULT 0,
            agi_xp INTEGER DEFAULT 0,
            sleep_hours REAL DEFAULT 7.5,
            sleep_tier TEXT DEFAULT 'well_rested',
            sleep_logged_date TEXT DEFAULT '',
            custom_categories TEXT DEFAULT 'Combat,Intellect,Conditioning'
          )
        ''');

        await db.execute('''
          CREATE TABLE skills (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            category TEXT NOT NULL,
            primary_stat TEXT NOT NULL,
            secondary_stat TEXT NOT NULL,
            mastery_xp INTEGER DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            category TEXT NOT NULL,
            description TEXT DEFAULT '',
            color_value INTEGER DEFAULT 4281908728,
            start_hour INTEGER NOT NULL,
            start_minute INTEGER NOT NULL,
            end_hour INTEGER NOT NULL,
            end_minute INTEGER NOT NULL,
            target_lat REAL NOT NULL,
            target_lng REAL NOT NULL,
            radius_meters REAL NOT NULL,
            repeat_days TEXT NOT NULL,
            last_completed_date TEXT,
            is_completed INTEGER DEFAULT 0,
            recurrence_start_date TEXT,
            recurrence_end_date TEXT,
            recurrence_type TEXT DEFAULT 'weekly',
            notify_enabled INTEGER DEFAULT 1,
            notify_leads TEXT DEFAULT "15",
            require_gps INTEGER DEFAULT 1,
            excluded_dates TEXT DEFAULT '',
            penalty_applied_date TEXT DEFAULT '',
            is_boss INTEGER DEFAULT 0,
            boss_stake INTEGER DEFAULT 400,
            prep_stacks INTEGER DEFAULT 0,
            primary_stat TEXT DEFAULT 'INT',
            secondary_stat TEXT DEFAULT 'PER',
            skill_id INTEGER DEFAULT -1
          )
        ''');

        await db.execute('''
          CREATE TABLE surge_quests (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            category TEXT NOT NULL,
            description TEXT DEFAULT '',
            base_rr INTEGER NOT NULL,
            start_epoch INTEGER NOT NULL,
            expire_epoch INTEGER NOT NULL,
            status TEXT DEFAULT 'pending',
            is_gamble INTEGER DEFAULT 0
          )
        ''');

        await db.insert('user_profile', {
          'id': 1,
          'current_streak': 0,
          'highest_streak': 0,
          'perfect_streak': 0,
          'highest_perfect_streak': 0,
          'shield_charges': 0,
          'last_completed_date': null,
          'last_perfect_date': null,
          'total_rr': 0,
          'highest_rank_level': 0,
          'last_evaluated_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
          'ui_color_override': 0xFF38BDF8,
          'emblem_color_override': -1,
          'str_xp': 0,
          'vit_xp': 0,
          'int_xp': 0,
          'per_xp': 0,
          'agi_xp': 0,
          'sleep_hours': 7.5,
          'sleep_tier': 'well_rested',
          'sleep_logged_date': '',
          'custom_categories': 'Combat,Intellect,Conditioning',
        });

        await _seedInitialSkills(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        Future<void> addColumnSafely(String table, String colDef) async {
          try {
            await db.execute('ALTER TABLE $table ADD COLUMN $colDef');
          } catch (_) {}
        }

        await addColumnSafely('user_profile', 'ui_color_override INTEGER DEFAULT 4281908728');
        await addColumnSafely('user_profile', 'emblem_color_override INTEGER DEFAULT -1');
        await addColumnSafely('user_profile', 'shield_charges INTEGER DEFAULT 0');
        await addColumnSafely('user_profile', 'str_xp INTEGER DEFAULT 0');
        await addColumnSafely('user_profile', 'vit_xp INTEGER DEFAULT 0');
        await addColumnSafely('user_profile', 'int_xp INTEGER DEFAULT 0');
        await addColumnSafely('user_profile', 'per_xp INTEGER DEFAULT 0');
        await addColumnSafely('user_profile', 'agi_xp INTEGER DEFAULT 0');
        await addColumnSafely('user_profile', 'sleep_hours REAL DEFAULT 7.5');
        await addColumnSafely('user_profile', 'sleep_tier TEXT DEFAULT "well_rested"');
        await addColumnSafely('user_profile', 'sleep_logged_date TEXT DEFAULT ""');
        await addColumnSafely('user_profile', 'custom_categories TEXT DEFAULT "Combat,Intellect,Conditioning"');

        await addColumnSafely('tasks', 'recurrence_type TEXT DEFAULT "weekly"');
        await addColumnSafely('tasks', 'is_boss INTEGER DEFAULT 0');
        await addColumnSafely('tasks', 'boss_stake INTEGER DEFAULT 400');
        await addColumnSafely('tasks', 'prep_stacks INTEGER DEFAULT 0');
        await addColumnSafely('tasks', 'primary_stat TEXT DEFAULT "INT"');
        await addColumnSafely('tasks', 'secondary_stat TEXT DEFAULT "PER"');
        await addColumnSafely('tasks', 'skill_id INTEGER DEFAULT -1');

        try {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS skills (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              category TEXT NOT NULL,
              primary_stat TEXT NOT NULL,
              secondary_stat TEXT NOT NULL,
              mastery_xp INTEGER DEFAULT 0
            )
          ''');
          final countRes = await db.rawQuery('SELECT COUNT(*) as c FROM skills');
          if ((countRes.first['c'] as int? ?? 0) == 0) {
            await _seedInitialSkills(db);
          }
        } catch (_) {}

        try {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS surge_quests (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              category TEXT NOT NULL,
              description TEXT DEFAULT '',
              base_rr INTEGER NOT NULL,
              start_epoch INTEGER NOT NULL,
              expire_epoch INTEGER NOT NULL,
              status TEXT DEFAULT 'pending',
              is_gamble INTEGER DEFAULT 0
            )
          ''');
        } catch (_) {}
        await addColumnSafely('surge_quests', 'is_gamble INTEGER DEFAULT 0');
      },
    );
    return _database!;
  }

  static Future<void> _seedInitialSkills(Database db) async {
    await db.insert('skills', {'name': 'Striking (Kickboxing)', 'category': 'Combat', 'primary_stat': 'AGI', 'secondary_stat': 'PER', 'mastery_xp': 120});
    await db.insert('skills', {'name': 'Grappling (BJJ)', 'category': 'Combat', 'primary_stat': 'INT', 'secondary_stat': 'STR', 'mastery_xp': 340});
    await db.insert('skills', {'name': 'Accounting & Audit', 'category': 'Intellect', 'primary_stat': 'INT', 'secondary_stat': 'PER', 'mastery_xp': 420});
    await db.insert('skills', {'name': 'Strength & Hypertrophy', 'category': 'Conditioning', 'primary_stat': 'STR', 'secondary_stat': 'VIT', 'mastery_xp': 180});
  }

  String _formatDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  double _getPerfectStreakMultiplier(int pStreak) {
    if (pStreak >= 30) return 2.0;
    if (pStreak >= 22) return 1.75;
    if (pStreak >= 15) return 1.5;
    if (pStreak >= 7) return 1.25;
    return 1.0;
  }

  int _getBaseReward(String category, String difficulty) {
    final cat = category.toLowerCase();
    if (cat == 'academic') {
      if (difficulty == 'Low') return 75;
      if (difficulty == 'High') return 175;
      return 125;
    } else if (cat == 'fitness') {
      if (difficulty == 'Low') return 60;
      if (difficulty == 'High') return 150;
      return 100;
    } else {
      if (difficulty == 'Low') return 40;
      if (difficulty == 'High') return 100;
      return 70;
    }
  }

  int _getStandardPenalty(JsonMap task) {
    final int isBoss = (task['is_boss'] as int?) ?? 0;
    if (isBoss == 1) {
      final int stake = (task['boss_stake'] as int?) ?? 400;
      final int stacks = _getEffectiveBossPrepStacks(task);
      final double mitigation = 1.0 - (stacks * 0.10);
      return (stake * mitigation).round();
    }
    final base = _getBaseReward(task['category'] as String, 'Medium');
    return (base * 0.5).round();
  }

  int _getEffectiveBossPrepStacks(JsonMap task) {
    int baseStacks = ((task['prep_stacks'] as int?) ?? 0).clamp(0, 5);
    final int skillId = (task['skill_id'] as int?) ?? -1;
    final skill = _findSkillById(skillId);
    if (skill != null && SystemRanks.getSkillRankNumeric((skill['mastery_xp'] as int?) ?? 0) >= 3) {
      baseStacks = (baseStacks + 1).clamp(0, 5);
    }
    return baseStacks;
  }

  bool _isTaskActiveOnDate(JsonMap task, DateTime targetDate) {
    final targetStr = _formatDate(targetDate);
    final excludedStr = (task['excluded_dates'] as String?) ?? '';
    if (excludedStr.isNotEmpty) {
      final excludedList = excludedStr.split(',');
      if (excludedList.contains(targetStr)) return false;
    }

    final startDateStr = task['recurrence_start_date'] as String?;
    final endDateStr = task['recurrence_end_date'] as String?;

    if (startDateStr != null && startDateStr.isNotEmpty && targetStr.compareTo(startDateStr) < 0) return false;
    if (endDateStr != null && endDateStr.isNotEmpty && targetStr.compareTo(endDateStr) > 0) return false;

    final recurrenceType = (task['recurrence_type'] as String?) ?? 'weekly';

    if (recurrenceType == 'once') {
      return targetStr == startDateStr;
    }

    if (recurrenceType == 'monthly') {
      if (startDateStr != null && startDateStr.isNotEmpty) {
        try {
          final startDate = DateFormat('yyyy-MM-dd').parse(startDateStr);
          final maxDayInTargetMonth = DateTime(targetDate.year, targetDate.month + 1, 0).day;
          final expectedDay = min(startDate.day, maxDayInTargetMonth);
          return targetDate.day == expectedDay;
        } catch (_) {}
      }
      return false;
    }

    if (recurrenceType == 'biweekly') {
      final repeatDaysStr = (task['repeat_days'] as String?) ?? '1,2,3,4,5,6,7';
      final activeDays = repeatDaysStr.split(',').map((e) => int.tryParse(e)).whereType<int>().toList();
      if (!activeDays.contains(targetDate.weekday)) return false;

      if (startDateStr != null && startDateStr.isNotEmpty) {
        try {
          final startDate = DateFormat('yyyy-MM-dd').parse(startDateStr);
          final startMonday = DateTime(startDate.year, startDate.month, startDate.day)
              .subtract(Duration(days: startDate.weekday - 1));
          final targetMonday = DateTime(targetDate.year, targetDate.month, targetDate.day)
              .subtract(Duration(days: targetDate.weekday - 1));
          final diffDays = targetMonday.difference(startMonday).inDays;
          final diffWeeks = (diffDays / 7).round();
          return diffWeeks >= 0 && (diffWeeks % 2 == 0);
        } catch (_) {}
      }
      return false;
    }

    final repeatDaysStr = (task['repeat_days'] as String?) ?? '1,2,3,4,5,6,7';
    final activeDays = repeatDaysStr.split(',').map((e) => int.tryParse(e)).whereType<int>().toList();
    return activeDays.contains(targetDate.weekday);
  }

  Future<void> _openGoogleMapsDirections(double lat, double lng) async {
    HapticFeedback.selectionClick();
    final Uri navUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=walking',
    );
    try {
      await launchUrl(navUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      final Uri geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
      if (await canLaunchUrl(geoUri)) {
        await launchUrl(geoUri);
      } else {
        _showMessage("Navigation Unavailable", "Could not open Google Maps on this device.");
      }
    }
  }

  Future<void> _startApp() async {
    final db = await database;
    try {
      await db.execute('ALTER TABLE user_profile ADD COLUMN custom_categories TEXT DEFAULT "Combat,Intellect,Conditioning"');
    } catch (_) {}

    final todayStr = _formatDate(_today);

    final profileRes = await db.query('user_profile', where: 'id = ?', whereArgs: [1]);
    bool completedToday = false;

    final taskRes = await db.query('tasks');
    _allTasks = JsonList.from(taskRes);

    final skillRes = await db.query('skills', orderBy: 'category ASC, mastery_xp DESC');
    _skills = JsonList.from(skillRes);

    if (profileRes.isNotEmpty) {
      final profile = profileRes.first;
      final lastDateStr = profile['last_completed_date'] as String?;
      final lastEvalStr = (profile['last_evaluated_date'] as String?) ?? todayStr;
      int streak = (profile['current_streak'] as int?) ?? 0;
      int maxStreak = (profile['highest_streak'] as int?) ?? streak;
      int pStreak = (profile['perfect_streak'] as int?) ?? 0;
      int maxPStreak = (profile['highest_perfect_streak'] as int?) ?? pStreak;
      int shields = (profile['shield_charges'] as int?) ?? 0;
      int rr = (profile['total_rr'] as int?) ?? 0;
      int maxRank = (profile['highest_rank_level'] as int?) ?? 0;

      strXp = (profile['str_xp'] as int?) ?? 0;
      vitXp = (profile['vit_xp'] as int?) ?? 0;
      intXp = (profile['int_xp'] as int?) ?? 0;
      perXp = (profile['per_xp'] as int?) ?? 0;
      agiXp = (profile['agi_xp'] as int?) ?? 0;

      sleepHours = (profile['sleep_hours'] as num?)?.toDouble() ?? 7.5;
      sleepTier = (profile['sleep_tier'] as String?) ?? 'well_rested';
      sleepLoggedDate = (profile['sleep_logged_date'] as String?) ?? '';

      final String savedCatsStr = (profile['custom_categories'] as String?) ?? 'Combat,Intellect,Conditioning';
      final Set<String> catSet = savedCatsStr
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet();
      for (final sk in _skills) {
        final c = (sk['category'] as String?)?.trim() ?? '';
        if (c.isNotEmpty) catSet.add(c);
      }
      if (catSet.isEmpty) {
        catSet.addAll(['Combat', 'Intellect', 'Conditioning']);
      }
      _skillCategories = catSet.toList();
      _expandedSkillCategories.addAll(_skillCategories);

      final int savedUiColor = (profile['ui_color_override'] as int?) ?? 0xFF38BDF8;
      _uiColorOverride = savedUiColor == -1 ? 0xFF38BDF8 : savedUiColor;

      final todayDate = DateFormat('yyyy-MM-dd').parse(todayStr);
      final lastEvalDate = DateFormat('yyyy-MM-dd').parse(lastEvalStr);
      final daysSinceEval = todayDate.difference(lastEvalDate).inDays;

      if (daysSinceEval > 0) {
        int missedTasks = 0;
        int totalPenalty = 0;
        for (int i = 1; i <= daysSinceEval; i++) {
          final pastDate = lastEvalDate.add(Duration(days: i - 1));
          final pastDateStr = _formatDate(pastDate);
          for (final task in _allTasks) {
            if (_isTaskActiveOnDate(task, pastDate)) {
              if (task['last_completed_date'] != pastDateStr) {
                missedTasks++;
                totalPenalty += _getStandardPenalty(task);
              }
            }
          }
        }

        if (missedTasks > 0) {
          if (shields > 0) {
            shields -= 1;
            _showMessage(
              "Rest Day Shield Used 🛡️",
              "A Rest Day Shield absorbed $missedTasks missed quest(s) from previous days.\nYour streaks ($streak d / $pStreak d) and RR were protected.",
            );
          } else {
            rr = max(0, rr - totalPenalty);
            streak = 0;
            pStreak = 0;
            _showMessage(
              "Missed Quests Penalty",
              "You missed $missedTasks quest(s) on previous active days.\n-$totalPenalty RR deducted and streaks reset.",
            );
          }
        }

        await db.update('user_profile', {
          'total_rr': rr,
          'current_streak': streak,
          'perfect_streak': pStreak,
          'shield_charges': shields,
          'last_evaluated_date': todayStr,
        }, where: 'id = ?', whereArgs: [1]);
      }

      if (lastDateStr != null && todayDate.difference(DateFormat('yyyy-MM-dd').parse(lastDateStr)).inDays == 0) {
        completedToday = true;
      }

      currentStreak = streak;
      highestStreak = max(maxStreak, streak);
      perfectStreak = pStreak;
      highestPerfectStreak = max(maxPStreak, pStreak);
      shieldCharges = shields;
      totalRr = rr;
      highestRankIdx = max(maxRank, SystemRanks.getRankIndex(rr));

      await db.update('user_profile', {
        'highest_streak': highestStreak,
        'highest_perfect_streak': highestPerfectStreak,
        'highest_rank_level': highestRankIdx,
      }, where: 'id = ?', whereArgs: [1]);
    }

    _filterTasks();
    await _checkActiveSurgeQuest();
    await _checkAndApplyImmediatePenalties();
    await _rescheduleTaskNotifications();
    await _ensureDailySurgeQuestScheduled();

    if (completedToday) {
      await notificationsPlugin.cancel(id: 1001);
    } else {
      _scheduleEveningAlert();
    }
  }

  Future<void> _addCustomSkillCategory(String newCategory) async {
    final clean = newCategory.trim().replaceAll(',', '');
    if (clean.isEmpty) return;
    if (!_skillCategories.any((c) => c.toLowerCase() == clean.toLowerCase())) {
      setState(() {
        _skillCategories.add(clean);
        _expandedSkillCategories.add(clean);
      });
      final db = await database;
      await db.update(
        'user_profile',
        {'custom_categories': _skillCategories.join(',')},
        where: 'id = ?',
        whereArgs: [1],
      );
    }
  }

  void _showAddCategoryDialog() {
    HapticFeedback.selectionClick();
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151924),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF22293A))),
        title: const Text("New Skill Category", style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "e.g. Languages, Music, Career",
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
            filled: true,
            fillColor: const Color(0xFF0D1017),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.black),
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                await _addCustomSkillCategory(name);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text("Add Category", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _filterTasks() {
    final todayFiltered = _allTasks.where((task) => _isTaskActiveOnDate(task, _today)).toList();
    todayFiltered.sort((a, b) {
      final int startA = (a['start_hour'] as int) * 60 + (a['start_minute'] as int);
      final int startB = (b['start_hour'] as int) * 60 + (b['start_minute'] as int);
      return startA.compareTo(startB);
    });

    final calendarFiltered = _allTasks.where((task) => _isTaskActiveOnDate(task, _selectedCalendarDate)).toList();
    calendarFiltered.sort((a, b) {
      final int startA = (a['start_hour'] as int) * 60 + (a['start_minute'] as int);
      final int startB = (b['start_hour'] as int) * 60 + (b['start_minute'] as int);
      return startA.compareTo(startB);
    });

    setState(() {
      _todayTasks = todayFiltered;
      _calendarDayTasks = calendarFiltered;
    });
  }

  Future<void> _grantAttributeXp(String stat, int xpAmount) async {
    if (xpAmount <= 0) return;
    final db = await database;
    switch (stat.toUpperCase()) {
      case 'STR':
        strXp += xpAmount;
        await db.update('user_profile', {'str_xp': strXp}, where: 'id = ?', whereArgs: [1]);
        break;
      case 'VIT':
        vitXp += xpAmount;
        await db.update('user_profile', {'vit_xp': vitXp}, where: 'id = ?', whereArgs: [1]);
        break;
      case 'INT':
        intXp += xpAmount;
        await db.update('user_profile', {'int_xp': intXp}, where: 'id = ?', whereArgs: [1]);
        break;
      case 'PER':
        perXp += xpAmount;
        await db.update('user_profile', {'per_xp': perXp}, where: 'id = ?', whereArgs: [1]);
        break;
      case 'AGI':
        agiXp += xpAmount;
        await db.update('user_profile', {'agi_xp': agiXp}, where: 'id = ?', whereArgs: [1]);
        break;
    }
  }

  void _showSleepSyncModal() {
    HapticFeedback.selectionClick();
    double tempHours = sleepHours;
    final todayStr = _formatDate(_today);
    final bool alreadyClaimedToday = sleepLoggedDate == todayStr;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151924),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final String previewTier = _classifySleepHours(tempHours);
            final Color previewColor = previewTier == 'fatigue'
                ? const Color(0xFFF43F5E)
                : previewTier == 'well_rested'
                    ? const Color(0xFF10B981)
                    : accentColor;
            final String previewTitle = previewTier == 'fatigue'
                ? 'Fatigue Debuff (-20% RR · 0 XP)'
                : previewTier == 'well_rested'
                    ? 'Well Rested (+15% RR · +8 VIT / +6 PER)'
                    : 'Standard Recovery (1.0x RR · +3 VIT / +2 PER)';

            return Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Sleep Recovery Sync",
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "1–4.9h: Fatigue (-20%) · 7–9.5h: Well Rested (+15%) · Other: Standard",
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Sleep Duration", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                      Text(
                        "${tempHours.toStringAsFixed(1)} hours",
                        style: TextStyle(color: previewColor, fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Slider(
                    value: tempHours,
                    min: 1.0,
                    max: 12.0,
                    divisions: 22,
                    activeColor: previewColor,
                    inactiveColor: const Color(0xFF22293A),
                    onChanged: (val) => setModalState(() => tempHours = val),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: previewColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: previewColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      previewTitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: previewColor, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: previewColor,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _applySleepRecovery(tempHours, alreadyClaimedToday);
                      },
                      child: Text(
                        alreadyClaimedToday ? "Update Sleep Status" : "Save & Claim Recovery XP",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _applySleepRecovery(double hours, bool alreadyClaimedToday) async {
    final db = await database;
    final todayStr = _formatDate(_today);
    final tier = _classifySleepHours(hours);

    int vitGain = 0;
    int perGain = 0;
    if (!alreadyClaimedToday) {
      if (tier == 'well_rested') {
        vitGain = 8;
        perGain = 6;
      } else if (tier == 'standard') {
        vitGain = 3;
        perGain = 2;
      }
      await _grantAttributeXp('VIT', vitGain);
      await _grantAttributeXp('PER', perGain);
    }

    await db.update('user_profile', {
      'sleep_hours': hours,
      'sleep_tier': tier,
      'sleep_logged_date': todayStr,
    }, where: 'id = ?', whereArgs: [1]);

    setState(() {
      sleepHours = hours;
      sleepTier = tier;
      sleepLoggedDate = todayStr;
    });

    HapticFeedback.mediumImpact();
  }

  Future<void> _checkActiveSurgeQuest() async {
    final db = await database;
    final nowEpoch = DateTime.now().millisecondsSinceEpoch;

    final expiredGambles = await db.query(
      'surge_quests',
      where: 'status = ? AND is_gamble = 1 AND expire_epoch <= ?',
      whereArgs: ['accepted_gamble', nowEpoch],
    );

    if (expiredGambles.isNotEmpty) {
      final profileRes = await db.query('user_profile', where: 'id = ?', whereArgs: [1]);
      int rr = profileRes.isNotEmpty ? ((profileRes.first['total_rr'] as int?) ?? 0) : 0;
      int totalLoss = 0;

      for (final g in expiredGambles) {
        final int loss = (g['base_rr'] as int) * 2;
        totalLoss += loss;
        await db.update('surge_quests', {'status': 'failed_gamble'}, where: 'id = ?', whereArgs: [g['id']]);
      }

      rr = max(0, rr - totalLoss);
      await db.update('user_profile', {'total_rr': rr}, where: 'id = ?', whereArgs: [1]);
      totalRr = rr;
      _showMessage(
        "Gamble Quest Expired",
        "The 30-minute timer ran out on your 2x gamble quest.\n-$totalLoss RR deducted.",
      );
    }

    final res = await db.query(
      'surge_quests',
      where: '(status = ? OR status = ?) AND expire_epoch > ?',
      whereArgs: ['pending', 'accepted_gamble', nowEpoch],
      orderBy: 'expire_epoch ASC',
      limit: 1,
    );

    if (res.isNotEmpty) {
      setState(() {
        _activeSurgeQuest = res.first;
        _surgeGambleArmed = (res.first['is_gamble'] as int? ?? 0) == 1;
      });
    } else {
      setState(() {
        _activeSurgeQuest = null;
        _surgeGambleArmed = false;
      });
    }
  }

  Future<void> _ensureDailySurgeQuestScheduled() async {
    final now = DateTime.now();
    const int dayStartMin = 360;
    const int dayEndMin = 1380;

    final List<SlotRange> freeSlots = [];
    int cursor = max(dayStartMin, now.hour * 60 + now.minute + 10);

    for (final task in _todayTasks) {
      final int tStart = (task['start_hour'] as int) * 60 + (task['start_minute'] as int);
      final int tEnd = (task['end_hour'] as int) * 60 + (task['end_minute'] as int);

      if (tStart > cursor && (tStart - cursor) >= 45) {
        freeSlots.add({'start': cursor, 'end': tStart});
      }
      cursor = max(cursor, tEnd);
    }

    if (dayEndMin > cursor && (dayEndMin - cursor) >= 45) {
      freeSlots.add({'start': cursor, 'end': dayEndMin});
    }

    if (freeSlots.isEmpty) return;

    final db = await database;
    final todayStartEpoch = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final todayEndEpoch = DateTime(now.year, now.month, now.day, 23, 59).millisecondsSinceEpoch;

    final existing = await db.query(
      'surge_quests',
      where: 'start_epoch >= ? AND start_epoch <= ?',
      whereArgs: [todayStartEpoch, todayEndEpoch],
    );

    if (existing.isNotEmpty) return;

    final rand = Random();
    final chosenSlot = freeSlots[rand.nextInt(freeSlots.length)];
    final int slotDuration = chosenSlot['end']! - chosenSlot['start']!;
    final int offsetMins = rand.nextInt(max(1, slotDuration - 35));
    final int triggerMinute = chosenSlot['start']! + offsetMins;

    final triggerTime = DateTime(now.year, now.month, now.day, triggerMinute ~/ 60, triggerMinute % 60);
    final expireTime = triggerTime.add(const Duration(minutes: 30));

    final template = microQuestPool[rand.nextInt(microQuestPool.length)];

    final questId = await db.insert('surge_quests', {
      'title': template['title'],
      'category': template['category'],
      'description': template['desc'],
      'base_rr': template['baseRr'],
      'start_epoch': triggerTime.millisecondsSinceEpoch,
      'expire_epoch': expireTime.millisecondsSinceEpoch,
      'status': 'pending',
      'is_gamble': 0,
    });

    const AndroidNotificationDetails surgeDetails = AndroidNotificationDetails(
      'surge_quests',
      'Surge Micro-Quests',
      channelDescription: 'Random productivity prompts popping up in your free time',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    await notificationsPlugin.zonedSchedule(
      id: 99000 + questId,
      title: '⚡ Bonus Surge Quest Available',
      body: '${template['title']} (+${template['baseRr']} RR). 30 min window!',
      scheduledDate: tz.TZDateTime.from(triggerTime, tz.local),
      notificationDetails: const NotificationDetails(android: surgeDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> _lockInTarnishedGamble(JsonMap surge) async {
    HapticFeedback.heavyImpact();
    final db = await database;
    await db.update(
      'surge_quests',
      {'status': 'accepted_gamble', 'is_gamble': 1},
      where: 'id = ?',
      whereArgs: [surge['id']],
    );
    await _checkActiveSurgeQuest();
  }

  Future<void> _completeSurgeQuest(JsonMap surge) async {
    HapticFeedback.heavyImpact();
    final db = await database;
    final double mult = _getPerfectStreakMultiplier(perfectStreak) * sleepRrMultiplier;
    final bool isGamble = (surge['is_gamble'] as int? ?? 0) == 1 || _surgeGambleArmed;
    final int base = (surge['base_rr'] as int) * (isGamble ? 2 : 1);
    final int earnedRr = (base * mult).round();

    await db.update('surge_quests', {'status': 'completed'}, where: 'id = ?', whereArgs: [surge['id']]);
    await _grantAttributeXp('VIT', isGamble ? 6 : 3);

    final profileRes = await db.query('user_profile', where: 'id = ?', whereArgs: [1]);
    final profile = profileRes.first;
    int oldRr = (profile['total_rr'] as int?) ?? 0;
    int maxRank = (profile['highest_rank_level'] as int?) ?? 0;

    final newRr = oldRr + earnedRr;
    final oldRankIdx = SystemRanks.getRankIndex(oldRr);
    final newRankIdx = SystemRanks.getRankIndex(newRr);
    maxRank = max(maxRank, newRankIdx);

    await db.update('user_profile', {
      'total_rr': newRr,
      'highest_rank_level': maxRank,
    }, where: 'id = ?', whereArgs: [1]);

    setState(() {
      _activeSurgeQuest = null;
      _surgeGambleArmed = false;
    });

    if (newRankIdx > oldRankIdx) {
      _triggerRankAscensionCeremony(oldRankIdx, newRankIdx);
    } else {
      _showMessage(
        isGamble ? "2x Gamble Completed! 🔥" : "Surge Quest Complete! ⚡",
        "+$earnedRr RR & +${isGamble ? 6 : 3} VIT XP earned.",
      );
    }

    _startApp();
  }

  Future<void> _dismissSurgeQuest(JsonMap surge) async {
    HapticFeedback.lightImpact();
    final db = await database;
    final bool isLockedGamble = surge['status'] == 'accepted_gamble';

    if (isLockedGamble) {
      final int penalty = (surge['base_rr'] as int) * 2;
      final profileRes = await db.query('user_profile', where: 'id = ?', whereArgs: [1]);
      final int oldRr = (profileRes.first['total_rr'] as int?) ?? 0;
      final int newRr = max(0, oldRr - penalty);

      await db.update('user_profile', {'total_rr': newRr}, where: 'id = ?', whereArgs: [1]);
      await db.update('surge_quests', {'status': 'failed_gamble'}, where: 'id = ?', whereArgs: [surge['id']]);
      _showMessage("Gamble Forfeited", "You backed out of an active 2x gamble.\n-$penalty RR deducted.");
    } else {
      await db.update('surge_quests', {'status': 'dismissed'}, where: 'id = ?', whereArgs: [surge['id']]);
    }

    setState(() {
      _activeSurgeQuest = null;
      _surgeGambleArmed = false;
    });
    _startApp();
  }

  Future<void> _checkAndApplyImmediatePenalties() async {
    final db = await database;
    final now = DateTime.now();
    final todayStr = _formatDate(_today);

    final profileRes = await db.query('user_profile', where: 'id = ?', whereArgs: [1]);
    if (profileRes.isEmpty) return;
    final profile = profileRes.first;
    int rr = (profile['total_rr'] as int?) ?? 0;

    int penalizedCount = 0;

    for (final task in _todayTasks) {
      final int taskId = task['id'] as int;
      final isCompleted = task['last_completed_date'] == todayStr;
      final penaltyAppliedDate = (task['penalty_applied_date'] as String?) ?? '';

      final endDt = DateTime(now.year, now.month, now.day, task['end_hour'] as int, task['end_minute'] as int)
          .add(const Duration(minutes: 15));

      if (now.isAfter(endDt) && !isCompleted && penaltyAppliedDate != todayStr) {
        penalizedCount++;
        final penalty = _getStandardPenalty(task);
        rr = max(0, rr - penalty);

        await db.update('tasks', {'penalty_applied_date': todayStr}, where: 'id = ?', whereArgs: [taskId]);

        const AndroidNotificationDetails penaltyDetails = AndroidNotificationDetails(
          'quest_penalties',
          'Quest Penalties',
          channelDescription: 'Notifications for missed quest deadlines',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        );
        await notificationsPlugin.show(
          id: 5000 + taskId,
          title: 'Quest Missed ⚠️',
          body: '"${task['title']}" window closed. -$penalty RR deducted.',
          notificationDetails: const NotificationDetails(android: penaltyDetails),
        );
      }
    }

    if (penalizedCount > 0) {
      await db.update('user_profile', {
        'total_rr': rr,
        'perfect_streak': 0,
      }, where: 'id = ?', whereArgs: [1]);

      perfectStreak = 0;
      totalRr = rr;
      setState(() {});
    }
  }

  Future<void> _cancelTaskNotifications(int taskId) async {
    for (int i = 0; i <= 99; i++) {
      await notificationsPlugin.cancel(id: taskId * 100 + i);
    }
  }

  Future<void> _rescheduleTaskNotifications() async {
    try {
      final pending = await notificationsPlugin.pendingNotificationRequests();
      for (final p in pending) {
        if (p.id != 1001 && p.id < 99000) {
          await notificationsPlugin.cancel(id: p.id);
        }
      }
    } catch (_) {}

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'quest_reminders_v2',
      'Quest Reminders',
      channelDescription: 'Advance alarms for classes and workout routines',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
    );
    const NotificationDetails notificationDetails = NotificationDetails(android: androidDetails);

    final now = DateTime.now();

    for (final task in _todayTasks) {
      final int taskId = task['id'] as int;
      final int notifyEnabled = (task['notify_enabled'] as int?) ?? 1;
      if (notifyEnabled == 0) continue;

      final String leadsStr = (task['notify_leads'] as String?) ?? '15';
      final leadMinutesList = leadsStr
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .toList();

      final startDt = DateTime(now.year, now.month, now.day, task['start_hour'] as int, task['start_minute'] as int);

      for (int i = 0; i < leadMinutesList.length; i++) {
        final leadMin = leadMinutesList[i];
        final alertTime = startDt.subtract(Duration(minutes: leadMin));

        if (alertTime.isAfter(now)) {
          final int notificationId = taskId * 100 + i;
          await notificationsPlugin.zonedSchedule(
            id: notificationId,
            title: '${task['title']} in $leadMin min',
            body: '${task['category']} starts at ${task['start_hour'].toString().padLeft(2, '0')}:${task['start_minute'].toString().padLeft(2, '0')}.',
            scheduledDate: tz.TZDateTime.from(alertTime, tz.local),
            notificationDetails: notificationDetails,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          );
        }
      }

      final endDt = DateTime(now.year, now.month, now.day, task['end_hour'] as int, task['end_minute'] as int)
          .add(const Duration(minutes: 15));

      final bool isCompleted = task['last_completed_date'] == _formatDate(_today);

      if (endDt.isAfter(now) && !isCompleted) {
        final penalty = _getStandardPenalty(task);
        const AndroidNotificationDetails penaltyDetails = AndroidNotificationDetails(
          'quest_penalties',
          'Quest Penalties',
          channelDescription: 'Notifications for missed quest deadlines',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        );
        final int penaltyNotifId = taskId * 100 + 99;
        await notificationsPlugin.zonedSchedule(
          id: penaltyNotifId,
          title: 'Quest Missed ⚠️',
          body: '"${task['title']}" expired. -$penalty RR deducted.',
          scheduledDate: tz.TZDateTime.from(endDt, tz.local),
          notificationDetails: const NotificationDetails(android: penaltyDetails),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      }
    }
  }

  Future<void> _scheduleEveningAlert() async {
    final now = DateTime.now();
    var scheduledDate = DateTime(now.year, now.month, now.day, 20, 30);
    if (now.isAfter(scheduledDate)) return;

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'streak_channel_v2',
      'Streak Protection',
      channelDescription: 'Reminders to protect your streak before midnight',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    const NotificationDetails notificationDetails = NotificationDetails(android: androidDetails);

    await notificationsPlugin.zonedSchedule(
      id: 1001,
      title: 'Streak Reminder 🔥',
      body: 'You still have uncompleted quests today. Check in before midnight!',
      scheduledDate: tz.TZDateTime.from(scheduledDate, tz.local),
      notificationDetails: notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  void _triggerRankAscensionCeremony(int oldRankIdx, int newRankIdx) {
    HapticFeedback.vibrate();
    final newRankName = SystemRanks.hunterLadder[newRankIdx]['name'] as String;
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.90),
      pageBuilder: (dialogCtx, anim1, anim2) {
        return RankAscensionDialog(
          newRankName: newRankName,
          accentColor: accentColor,
          onClaimed: () => Navigator.pop(dialogCtx),
        );
      },
    );
  }

  Future<void> _attemptCheckIn(JsonMap task) async {
    final now = DateTime.now();
    final startTime = DateTime(now.year, now.month, now.day, task['start_hour'] as int, task['start_minute'] as int)
        .subtract(const Duration(minutes: 15));
    final endTime = DateTime(now.year, now.month, now.day, task['end_hour'] as int, task['end_minute'] as int)
        .add(const Duration(minutes: 15));

    if (now.isBefore(startTime) || now.isAfter(endTime)) {
      HapticFeedback.heavyImpact();
      _showMessage("Check-In Locked", "Window opens 15m before start and closes 15m after end.");
      return;
    }

    final int requireGps = (task['require_gps'] as int?) ?? 1;
    if (requireGps == 1) {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showMessage("GPS Permission Needed", "Enable location access to verify attendance.");
          return;
        }
      }

      Position userPos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      double distanceMeters = Geolocator.distanceBetween(
        userPos.latitude,
        userPos.longitude,
        task['target_lat'] as double,
        task['target_lng'] as double,
      );

      final double allowedRadius = (task['radius_meters'] as num).toDouble();
      if (distanceMeters > allowedRadius) {
        HapticFeedback.heavyImpact();
        _showMessage(
          "Outside Geofence",
          "You are ${distanceMeters.toStringAsFixed(0)}m away (must be within ${allowedRadius.toInt()}m).",
        );
        return;
      }
    }

    final int isBoss = (task['is_boss'] as int?) ?? 0;
    if (isBoss == 1) {
      _showBossResolutionModal(task);
    } else {
      _showDifficultySelectionModal(task);
    }
  }

  void _showBossResolutionModal(JsonMap task) {
    HapticFeedback.heavyImpact();
    final int baseStake = (task['boss_stake'] as int?) ?? 400;
    final int stacks = _getEffectiveBossPrepStacks(task);
    final double mult = _getPerfectStreakMultiplier(perfectStreak) * sleepRrMultiplier;

    final int victoryGain = (baseStake * (1.0 + stacks * 0.10) * mult).round();
    final int defeatLoss = (baseStake * (1.0 - stacks * 0.10)).round();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151924),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Boss Encounter Result",
                    style: TextStyle(color: Color(0xFFFBBF24), fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFBBF24).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      "🛡️ $stacks/5 Prep Buffs",
                      style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                task['title'] as String,
                style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  _finalizeBossEncounter(task, true, victoryGain);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 22),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Succeeded / Passed", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                            Text("Full stake + Prep bonus & Stat XP", style: TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                      ),
                      Text("+$victoryGain RR", style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  _finalizeBossEncounter(task, false, defeatLoss);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF43F5E).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF43F5E).withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cancel, color: Color(0xFFF43F5E), size: 22),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Failed / Defeated", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                            Text("Prep-mitigated RR penalty deducted", style: TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                      ),
                      Text("-$defeatLoss RR", style: const TextStyle(color: Color(0xFFF43F5E), fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _finalizeBossEncounter(JsonMap task, bool succeeded, int rrDelta) async {
    final db = await database;
    final todayStr = _formatDate(_today);

    await db.update(
      'tasks',
      {'last_completed_date': todayStr, 'is_completed': 1, 'prep_stacks': 0},
      where: 'id = ?',
      whereArgs: [task['id']],
    );

    await notificationsPlugin.cancel(id: (task['id'] as int) * 100 + 99);

    final String pStat = (task['primary_stat'] as String?) ?? 'INT';
    final String sStat = (task['secondary_stat'] as String?) ?? 'PER';
    final int skillId = (task['skill_id'] as int?) ?? -1;

    if (succeeded) {
      await _grantAttributeXp(pStat, 16);
      await _grantAttributeXp(sStat, 8);
      final skill = _findSkillById(skillId);
      if (skill != null) {
        final int newXp = ((skill['mastery_xp'] as int?) ?? 0) + 50;
        await db.update('skills', {'mastery_xp': newXp}, where: 'id = ?', whereArgs: [skillId]);
      }
    }

    final profileRes = await db.query('user_profile', where: 'id = ?', whereArgs: [1]);
    final profile = profileRes.first;
    final lastDateStr = profile['last_completed_date'] as String?;
    final lastPerfectDateStr = profile['last_perfect_date'] as String?;
    int streak = (profile['current_streak'] as int?) ?? 0;
    int maxStreak = (profile['highest_streak'] as int?) ?? streak;
    int pStreak = (profile['perfect_streak'] as int?) ?? 0;
    int maxPStreak = (profile['highest_perfect_streak'] as int?) ?? pStreak;
    int shields = (profile['shield_charges'] as int?) ?? 0;
    int oldRr = (profile['total_rr'] as int?) ?? 0;
    int maxRank = (profile['highest_rank_level'] as int?) ?? 0;

    if (lastDateStr == null) {
      streak = 1;
    } else {
      final todayParsed = DateFormat('yyyy-MM-dd').parse(todayStr);
      final lastDateParsed = DateFormat('yyyy-MM-dd').parse(lastDateStr);
      final diff = todayParsed.difference(lastDateParsed).inDays;
      if (diff == 1) {
        streak += 1;
      } else if (diff > 1) {
        streak = 1;
      }
    }
    maxStreak = max(maxStreak, streak);

    final allTodayRes = await db.query('tasks');
    final activeToday = allTodayRes.where((t) => _isTaskActiveOnDate(t, _today)).toList();
    final bool allDone = activeToday.every((t) => t['last_completed_date'] == todayStr);

    bool forgedShield = false;
    if (allDone && lastPerfectDateStr != todayStr) {
      if (lastPerfectDateStr == null) {
        pStreak = 1;
      } else {
        final todayParsed = DateFormat('yyyy-MM-dd').parse(todayStr);
        final lastPDateParsed = DateFormat('yyyy-MM-dd').parse(lastPerfectDateStr);
        final pDiff = todayParsed.difference(lastPDateParsed).inDays;
        if (pDiff == 1) {
          pStreak += 1;
        } else if (pDiff > 1) {
          pStreak = 1;
        }
      }
      maxPStreak = max(maxPStreak, pStreak);

      if (pStreak > 0 && pStreak % 7 == 0 && shields < 3) {
        shields += 1;
        forgedShield = true;
      }
    }

    final int newRr = succeeded ? (oldRr + rrDelta) : max(0, oldRr - rrDelta);
    final int oldRankIdx = SystemRanks.getRankIndex(oldRr);
    final int newRankIdx = SystemRanks.getRankIndex(newRr);
    maxRank = max(maxRank, newRankIdx);

    await db.update('user_profile', {
      'current_streak': streak,
      'highest_streak': maxStreak,
      'perfect_streak': pStreak,
      'highest_perfect_streak': maxPStreak,
      'shield_charges': shields,
      'last_completed_date': todayStr,
      'last_perfect_date': allDone ? todayStr : lastPerfectDateStr,
      'total_rr': newRr,
      'highest_rank_level': maxRank,
    }, where: 'id = ?', whereArgs: [1]);

    await notificationsPlugin.cancel(id: 1001);

    if (succeeded && newRankIdx > oldRankIdx) {
      _triggerRankAscensionCeremony(oldRankIdx, newRankIdx);
    } else if (succeeded) {
      HapticFeedback.heavyImpact();
      _showMessage(
        "Boss Cleared! 👑",
        "+$rrDelta RR · +16 $pStat / +8 $sStat XP${forgedShield ? '\n🛡️ +1 Rest Day Shield forged!' : ''}",
      );
    } else {
      HapticFeedback.vibrate();
      _showMessage(
        "Boss Failed",
        "-$rrDelta RR deducted.",
      );
    }

    _startApp();
  }

  void _showDifficultySelectionModal(JsonMap task) {
    HapticFeedback.selectionClick();
    final String category = task['category'] as String;
    final String pStat = (task['primary_stat'] as String?) ?? 'INT';
    final String sStat = (task['secondary_stat'] as String?) ?? 'PER';
    final int skillId = (task['skill_id'] as int?) ?? -1;
    final skill = _findSkillById(skillId);
    final double skillBonus = skill != null ? SystemRanks.getSkillRrBonusMultiplier((skill['mastery_xp'] as int?) ?? 0) : 0.0;
    final double mult = _getPerfectStreakMultiplier(perfectStreak) * sleepRrMultiplier * (1.0 + skillBonus);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151924),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Session Intensity",
                    style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    "${mult.toStringAsFixed(2)}x Multiplier",
                    style: TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                task['title'] as String,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildIntensityTile("Low / Light", "+4 $pStat, +2 $sStat${skill != null ? ' · +15 Skill XP' : ''}", (_getBaseReward(category, 'Low') * mult).round(), () {
                Navigator.pop(ctx);
                _finalizeCheckIn(task, 'Low');
              }),
              const SizedBox(height: 10),
              _buildIntensityTile("Medium / Standard", "+8 $pStat, +4 $sStat${skill != null ? ' · +25 Skill XP' : ''}", (_getBaseReward(category, 'Medium') * mult).round(), () {
                Navigator.pop(ctx);
                _finalizeCheckIn(task, 'Medium');
              }),
              const SizedBox(height: 10),
              _buildIntensityTile("High / Demanding", "+14 $pStat, +7 $sStat${skill != null ? ' · +40 Skill XP' : ''}", (_getBaseReward(category, 'High') * mult).round(), () {
                Navigator.pop(ctx);
                _finalizeCheckIn(task, 'High');
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildIntensityTile(String title, String sub, int rrGain, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1017),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF22293A)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(sub, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text("+$rrGain RR", style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _finalizeCheckIn(JsonMap task, String difficulty) async {
    final db = await database;
    final todayStr = _formatDate(_today);
    final String category = task['category'] as String;
    final String pStat = (task['primary_stat'] as String?) ?? 'INT';
    final String sStat = (task['secondary_stat'] as String?) ?? 'PER';
    final int skillId = (task['skill_id'] as int?) ?? -1;

    final int pXp = difficulty == 'High' ? 14 : (difficulty == 'Low' ? 4 : 8);
    final int sXp = difficulty == 'High' ? 7 : (difficulty == 'Low' ? 2 : 4);
    final int skillXpGain = difficulty == 'High' ? 40 : (difficulty == 'Low' ? 15 : 25);

    final skill = _findSkillById(skillId);
    final double skillBonus = skill != null ? SystemRanks.getSkillRrBonusMultiplier((skill['mastery_xp'] as int?) ?? 0) : 0.0;
    final double mult = _getPerfectStreakMultiplier(perfectStreak) * sleepRrMultiplier * (1.0 + skillBonus);
    final int earnedRr = (_getBaseReward(category, difficulty) * mult).round();

    await db.update(
      'tasks',
      {'last_completed_date': todayStr, 'is_completed': 1},
      where: 'id = ?',
      whereArgs: [task['id']],
    );

    await notificationsPlugin.cancel(id: (task['id'] as int) * 100 + 99);

    await _grantAttributeXp(pStat, pXp);
    await _grantAttributeXp(sStat, sXp);

    String skillRankUpNotice = '';
    if (skill != null) {
      final int oldSkillXp = (skill['mastery_xp'] as int?) ?? 0;
      final int newSkillXp = oldSkillXp + skillXpGain;
      final String oldLetter = SystemRanks.getSkillRankLetter(oldSkillXp);
      final String newLetter = SystemRanks.getSkillRankLetter(newSkillXp);
      await db.update('skills', {'mastery_xp': newSkillXp}, where: 'id = ?', whereArgs: [skillId]);
      if (newLetter != oldLetter) {
        skillRankUpNotice = '\n🎉 ${skill['name']} ranked up to $newLetter-Rank!';
      } else {
        skillRankUpNotice = '\n+$skillXpGain XP → ${skill['name']}';
      }
    }

    int buffedBosses = 0;
    if (category == 'Academic' || category == 'Fitness') {
      final todayOnly = DateTime(_today.year, _today.month, _today.day);
      for (final other in _allTasks) {
        if ((other['is_boss'] as int? ?? 0) == 1 && other['last_completed_date'] != todayStr) {
          final startStr = other['recurrence_start_date'] as String?;
          if (startStr != null && startStr.isNotEmpty) {
            try {
              final bossDate = DateFormat('yyyy-MM-dd').parse(startStr);
              final daysUntil = bossDate.difference(todayOnly).inDays;
              if (daysUntil >= 0 && daysUntil <= 7) {
                final int curStacks = (other['prep_stacks'] as int?) ?? 0;
                if (curStacks < 5) {
                  await db.update('tasks', {'prep_stacks': curStacks + 1}, where: 'id = ?', whereArgs: [other['id']]);
                  buffedBosses++;
                }
              }
            } catch (_) {}
          }
        }
      }
    }

    final profileRes = await db.query('user_profile', where: 'id = ?', whereArgs: [1]);
    final profile = profileRes.first;
    final lastDateStr = profile['last_completed_date'] as String?;
    final lastPerfectDateStr = profile['last_perfect_date'] as String?;
    int streak = (profile['current_streak'] as int?) ?? 0;
    int maxStreak = (profile['highest_streak'] as int?) ?? streak;
    int pStreak = (profile['perfect_streak'] as int?) ?? 0;
    int maxPStreak = (profile['highest_perfect_streak'] as int?) ?? pStreak;
    int shields = (profile['shield_charges'] as int?) ?? 0;
    int oldRr = (profile['total_rr'] as int?) ?? 0;
    int maxRank = (profile['highest_rank_level'] as int?) ?? 0;

    if (lastDateStr == null) {
      streak = 1;
    } else {
      final todayParsed = DateFormat('yyyy-MM-dd').parse(todayStr);
      final lastDateParsed = DateFormat('yyyy-MM-dd').parse(lastDateStr);
      final diff = todayParsed.difference(lastDateParsed).inDays;

      if (diff == 1) {
        streak += 1;
      } else if (diff > 1) {
        streak = 1;
      }
    }
    maxStreak = max(maxStreak, streak);

    final allTodayRes = await db.query('tasks');
    final activeToday = allTodayRes.where((t) => _isTaskActiveOnDate(t, _today)).toList();
    final bool allDone = activeToday.every((t) => t['last_completed_date'] == todayStr);

    bool forgedShield = false;
    if (allDone && lastPerfectDateStr != todayStr) {
      if (lastPerfectDateStr == null) {
        pStreak = 1;
      } else {
        final todayParsed = DateFormat('yyyy-MM-dd').parse(todayStr);
        final lastPDateParsed = DateFormat('yyyy-MM-dd').parse(lastPerfectDateStr);
        final pDiff = todayParsed.difference(lastPDateParsed).inDays;

        if (pDiff == 1) {
          pStreak += 1;
        } else if (pDiff > 1) {
          pStreak = 1;
        }
      }
      maxPStreak = max(maxPStreak, pStreak);

      if (pStreak > 0 && pStreak % 7 == 0 && shields < 3) {
        shields += 1;
        forgedShield = true;
      }
    }

    final newRr = oldRr + earnedRr;
    final oldRankIdx = SystemRanks.getRankIndex(oldRr);
    final newRankIdx = SystemRanks.getRankIndex(newRr);
    maxRank = max(maxRank, newRankIdx);

    await db.update('user_profile', {
      'current_streak': streak,
      'highest_streak': maxStreak,
      'perfect_streak': pStreak,
      'highest_perfect_streak': maxPStreak,
      'shield_charges': shields,
      'last_completed_date': todayStr,
      'last_perfect_date': allDone ? todayStr : lastPerfectDateStr,
      'total_rr': newRr,
      'highest_rank_level': maxRank,
    }, where: 'id = ?', whereArgs: [1]);

    await notificationsPlugin.cancel(id: 1001);

    if (newRankIdx > oldRankIdx) {
      _triggerRankAscensionCeremony(oldRankIdx, newRankIdx);
    } else {
      HapticFeedback.lightImpact();
      String extra = skillRankUpNotice;
      if (buffedBosses > 0) extra += '\n⚔️ +1 Boss Prep Buff gained!';
      if (forgedShield) extra += '\n🛡️ +1 Rest Day Shield forged!';
      _showMessage("Quest Complete! ✓", "+$earnedRr RR · +$pXp $pStat, +$sXp $sStat XP$extra");
    }

    _startApp();
  }

  void _promptDeleteTask(JsonMap task, [DateTime? forDate]) {
    final targetDate = forDate ?? _today;
    HapticFeedback.lightImpact();
    final int taskId = task['id'] as int;
    final String title = task['title'] as String;
    final String recurrenceType = (task['recurrence_type'] as String?) ?? 'weekly';
    final bool isRecurring = recurrenceType != 'once';
    final String dateLabel = _formatDate(targetDate) == _formatDate(_today)
        ? "today"
        : DateFormat('MMM d').format(targetDate);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151924),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Remove \"$title\"",
              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 14),
            if (isRecurring) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.today, color: accentColor, size: 22),
                title: Text("Skip for $dateLabel only", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: const Text("Keeps future occurrences on your schedule", style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _excludeTaskForDate(taskId, targetDate);
                },
              ),
              const Divider(color: Color(0xFF22293A)),
            ],
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_outline, color: Color(0xFFF43F5E), size: 22),
              title: Text(isRecurring ? "Delete all occurrences" : "Delete quest", style: const TextStyle(color: Color(0xFFF43F5E), fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: const Text("Permanently removes this quest", style: TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () async {
                Navigator.pop(ctx);
                await _deleteTaskPermanently(taskId);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _excludeTaskForDate(int id, DateTime date) async {
    await _cancelTaskNotifications(id);
    final db = await database;
    final dateStr = _formatDate(date);
    final res = await db.query('tasks', columns: ['excluded_dates'], where: 'id = ?', whereArgs: [id]);
    if (res.isNotEmpty) {
      final currentExcluded = (res.first['excluded_dates'] as String?) ?? '';
      final list = currentExcluded.isEmpty ? <String>[] : currentExcluded.split(',');
      if (!list.contains(dateStr)) {
        list.add(dateStr);
      }
      await db.update('tasks', {'excluded_dates': list.join(',')}, where: 'id = ?', whereArgs: [id]);
    }
    _startApp();
  }

  Future<void> _deleteTaskPermanently(int id) async {
    await _cancelTaskNotifications(id);
    final db = await database;
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
    _startApp();
  }

  void _showMessage(String title, String body) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151924),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF22293A)),
        ),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
        content: Text(body, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("OK", style: TextStyle(color: accentColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showTaskDetailSheet(JsonMap task, [DateTime? forDate]) {
    HapticFeedback.selectionClick();
    final String description = (task['description'] as String?) ?? '';
    final String startRange = (task['recurrence_start_date'] as String?) ?? 'Any';
    final String endRange = (task['recurrence_end_date'] as String?) ?? 'Ongoing';
    final String recurrenceType = (task['recurrence_type'] as String?) ?? 'weekly';
    final int requireGps = (task['require_gps'] as int?) ?? 1;
    final int isBoss = (task['is_boss'] as int?) ?? 0;
    final int bossStake = (task['boss_stake'] as int?) ?? 400;
    final int prepStacks = _getEffectiveBossPrepStacks(task);
    final double targetLat = (task['target_lat'] as num?)?.toDouble() ?? 0.0;
    final double targetLng = (task['target_lng'] as num?)?.toDouble() ?? 0.0;
    final String pStat = (task['primary_stat'] as String?) ?? 'INT';
    final String sStat = (task['secondary_stat'] as String?) ?? 'PER';
    final int skillId = (task['skill_id'] as int?) ?? -1;
    final skill = _findSkillById(skillId);
    final int penalty = _getStandardPenalty(task);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151924),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isBoss == 1 ? const Color(0xFFFBBF24) : accentColor).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isBoss == 1 ? "👑 Boss · ${task['category']}" : "${task['category']} · +$pStat / +$sStat",
                      style: TextStyle(color: isBoss == 1 ? const Color(0xFFFBBF24) : accentColor, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    "${task['start_hour'].toString().padLeft(2, '0')}:${task['start_minute'].toString().padLeft(2, '0')} – ${task['end_hour'].toString().padLeft(2, '0')}:${task['end_minute'].toString().padLeft(2, '0')}",
                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                task['title'] as String,
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                skill != null
                    ? "Linked Skill: ${skill['name']} (${SystemRanks.getSkillRankLetter((skill['mastery_xp'] as int?) ?? 0)}-Rank)"
                    : "Stat-Only Quest (Unlinked)",
                style: TextStyle(color: skill != null ? const Color(0xFF10B981) : Colors.white54, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1017),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(description, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Schedule: ${recurrenceType.toUpperCase()} ($startRange → $endRange)", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  Text(
                    isBoss == 1 ? "Stake: ±$bossStake RR ($prepStacks/5 Prep)" : "Penalty: -$penalty RR",
                    style: const TextStyle(color: Color(0xFFF43F5E), fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(requireGps == 1 ? Icons.location_on_outlined : Icons.public, color: Colors.white54, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      requireGps == 1 ? "GPS Geofence (${(task['radius_meters'] as num).toInt()}m)" : "Any location allowed",
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                  if (requireGps == 1 && (targetLat != 0.0 || targetLng != 0.0))
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor.withValues(alpha: 0.16),
                        foregroundColor: accentColor,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _openGoogleMapsDirections(targetLat, targetLng),
                      icon: const Icon(Icons.directions, size: 16),
                      label: const Text("Directions", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFF43F5E),
                    side: BorderSide(color: const Color(0xFFF43F5E).withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _promptDeleteTask(task, forDate);
                  },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text("Remove / Skip Quest", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openAddTaskScreen() async {
    HapticFeedback.lightImpact();
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddTaskScreen(
          initialDate: _selectedTabIndex == 1 ? _selectedCalendarDate : _today,
          skills: _skills,
          accentColor: accentColor,
        ),
      ),
    );
    if (result == true) {
      _startApp();
    }
  }

  void _showCreateSkillModal() {
    HapticFeedback.selectionClick();
    final nameCtrl = TextEditingController();
    final customCatCtrl = TextEditingController();
    String selectedCat = _skillCategories.isNotEmpty ? _skillCategories.first : 'Combat';
    bool addingNewCat = false;
    String pStat = 'STR';
    String sStat = 'AGI';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151924),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(22, 22, 22, MediaQuery.of(context).viewInsets.bottom + 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Add New Skill", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Skill Name (e.g. MMA, Kickboxing, Accounting)",
                      labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF0D1017),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Category", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                      TextButton.icon(
                        onPressed: () => setModalState(() => addingNewCat = !addingNewCat),
                        icon: Icon(addingNewCat ? Icons.close : Icons.add, size: 15, color: accentColor),
                        label: Text(addingNewCat ? "Pick Existing" : "New Category", style: TextStyle(color: accentColor, fontSize: 12)),
                      ),
                    ],
                  ),
                  if (addingNewCat)
                    TextField(
                      controller: customCatCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Enter new category name...",
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                        filled: true,
                        fillColor: const Color(0xFF0D1017),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _skillCategories.map((cat) {
                        final isSel = selectedCat == cat;
                        return ChoiceChip(
                          label: Text(cat),
                          selected: isSel,
                          selectedColor: accentColor,
                          backgroundColor: const Color(0xFF0D1017),
                          labelStyle: TextStyle(color: isSel ? Colors.black : Colors.white70, fontWeight: FontWeight.bold, fontSize: 12),
                          onSelected: (_) => setModalState(() => selectedCat = cat),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Primary Stat", style: TextStyle(color: Colors.white70, fontSize: 12)),
                            DropdownButton<String>(
                              value: pStat,
                              dropdownColor: const Color(0xFF151924),
                              isExpanded: true,
                              style: TextStyle(color: accentColor, fontWeight: FontWeight.bold),
                              items: ['STR', 'VIT', 'INT', 'PER', 'AGI'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                              onChanged: (v) {
                                if (v != null) setModalState(() => pStat = v);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Secondary Stat", style: TextStyle(color: Colors.white70, fontSize: 12)),
                            DropdownButton<String>(
                              value: sStat,
                              dropdownColor: const Color(0xFF151924),
                              isExpanded: true,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              items: ['STR', 'VIT', 'INT', 'PER', 'AGI'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                              onChanged: (v) {
                                if (v != null) setModalState(() => sStat = v);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) return;
                        String finalCat = selectedCat;
                        if (addingNewCat && customCatCtrl.text.trim().isNotEmpty) {
                          finalCat = customCatCtrl.text.trim();
                          await _addCustomSkillCategory(finalCat);
                        }
                        final db = await database;
                        await db.insert('skills', {
                          'name': name,
                          'category': finalCat,
                          'primary_stat': pStat,
                          'secondary_stat': sStat,
                          'mastery_xp': 0,
                        });
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        _startApp();
                      },
                      child: const Text("Create Skill", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _exportProfileData() async {
    HapticFeedback.mediumImpact();
    final db = await database;
    final profileRes = await db.query('user_profile', where: 'id = ?', whereArgs: [1]);
    final tasksRes = await db.query('tasks');
    final skillsRes = await db.query('skills');

    final exportMap = {
      'version': 5,
      'exported_at': DateTime.now().toIso8601String(),
      'profile': profileRes.isNotEmpty ? profileRes.first : {},
      'tasks': tasksRes,
      'skills': skillsRes,
    };

    final jsonString = jsonEncode(exportMap);
    await Clipboard.setData(ClipboardData(text: jsonString));

    _showMessage("Backup Copied 📋", "Your profile, stats, custom skills, categories, and quests are copied to your clipboard.");
  }

  Future<void> _importProfileDataPrompt() async {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151924),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF22293A))),
        title: const Text("Restore Backup", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
        content: TextField(
          controller: textController,
          maxLines: 4,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(
            hintText: 'Paste backup JSON here...',
            hintStyle: const TextStyle(color: Colors.white24),
            filled: true,
            fillColor: const Color(0xFF0D1017),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel", style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.black),
            onPressed: () async {
              final raw = textController.text.trim();
              if (raw.isEmpty) return;
              try {
                final JsonMap data = jsonDecode(raw) as JsonMap;
                final db = await database;

                if (data.containsKey('profile')) {
                  final p = JsonMap.from(data['profile'] as Map);
                  await db.update('user_profile', {
                    'total_rr': p['total_rr'] ?? 0,
                    'current_streak': p['current_streak'] ?? 0,
                    'highest_streak': p['highest_streak'] ?? 0,
                    'perfect_streak': p['perfect_streak'] ?? 0,
                    'highest_perfect_streak': p['highest_perfect_streak'] ?? 0,
                    'shield_charges': p['shield_charges'] ?? 0,
                    'highest_rank_level': p['highest_rank_level'] ?? 0,
                    'last_completed_date': p['last_completed_date'],
                    'last_perfect_date': p['last_perfect_date'],
                    'last_evaluated_date': p['last_evaluated_date'],
                    'ui_color_override': p['ui_color_override'] ?? 0xFF38BDF8,
                    'str_xp': p['str_xp'] ?? 0,
                    'vit_xp': p['vit_xp'] ?? 0,
                    'int_xp': p['int_xp'] ?? 0,
                    'per_xp': p['per_xp'] ?? 0,
                    'agi_xp': p['agi_xp'] ?? 0,
                    'custom_categories': p['custom_categories'] ?? 'Combat,Intellect,Conditioning',
                  }, where: 'id = ?', whereArgs: [1]);
                }

                if (data.containsKey('skills')) {
                  await db.delete('skills');
                  for (final item in (data['skills'] as Iterable)) {
                    final s = JsonMap.from(item as Map);
                    s.remove('id');
                    await db.insert('skills', s);
                  }
                }

                if (data.containsKey('tasks')) {
                  await db.delete('tasks');
                  for (final item in (data['tasks'] as Iterable)) {
                    final task = JsonMap.from(item as Map);
                    task.remove('id');
                    await db.insert('tasks', task);
                  }
                }

                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                _showMessage("Restored!", "All stats, skills, categories, and quests restored.");
                _startApp();
              } catch (_) {
                _showMessage("Invalid Backup", "The pasted text is not a valid backup JSON.");
              }
            },
            child: const Text("Restore", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _formatMinutes(int totalMinutes) {
    final int h = totalMinutes ~/ 60;
    final int m = totalMinutes % 60;
    return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final accent = accentColor;

    Widget currentBody;
    if (_selectedTabIndex == 0) {
      currentBody = _buildTodayTab();
    } else if (_selectedTabIndex == 1) {
      currentBody = _buildCalendarTab();
    } else if (_selectedTabIndex == 2) {
      currentBody = _buildSkillsTab();
    } else {
      currentBody = _buildProfileTab();
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      body: SafeArea(child: currentBody),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF11151F),
          border: Border(top: BorderSide(color: Color(0xFF1E2433), width: 1)),
        ),
        child: NavigationBar(
          height: 66,
          backgroundColor: const Color(0xFF11151F),
          selectedIndex: _selectedTabIndex,
          indicatorColor: accent.withValues(alpha: 0.16),
          onDestinationSelected: (idx) {
            HapticFeedback.selectionClick();
            setState(() => _selectedTabIndex = idx);
          },
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.check_circle_outline, color: Colors.white54),
              selectedIcon: Icon(Icons.check_circle, color: accent),
              label: 'Today',
            ),
            NavigationDestination(
              icon: const Icon(Icons.calendar_today_outlined, color: Colors.white54),
              selectedIcon: Icon(Icons.calendar_today, color: accent),
              label: 'Calendar',
            ),
            NavigationDestination(
              icon: const Icon(Icons.radar_outlined, color: Colors.white54),
              selectedIcon: Icon(Icons.radar, color: accent),
              label: 'Skills',
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline, color: Colors.white54),
              selectedIcon: Icon(Icons.person, color: accent),
              label: 'Profile',
            ),
          ],
        ),
      ),
      floatingActionButton: _selectedTabIndex >= 2
          ? null
          : FloatingActionButton(
              backgroundColor: accent,
              foregroundColor: Colors.black,
              elevation: 2,
              onPressed: _openAddTaskScreen,
              child: const Icon(Icons.add, size: 26),
            ),
    );
  }

  // ============================================================================
  // TAB 0: TODAY (Clean Overview + Streamlined Quest Feed)
  // ============================================================================
  Widget _buildTodayTab() {
    final accent = accentColor;
    final int rankIdx = SystemRanks.getRankIndex(totalRr);
    final String rankName = SystemRanks.hunterLadder[rankIdx]['name'] as String;
    final int curMinRr = SystemRanks.hunterLadder[rankIdx]['minRr'] as int;
    final int nextMinRr = rankIdx < SystemRanks.hunterLadder.length - 1
        ? (SystemRanks.hunterLadder[rankIdx + 1]['minRr'] as int)
        : curMinRr + 10000;
    final double progress = ((totalRr - curMinRr) / max(1, nextMinRr - curMinRr)).clamp(0.0, 1.0);

    final int completedCount = _todayTasks.where((t) => t['last_completed_date'] == _formatDate(_today)).length;
    final double streakMult = _getPerfectStreakMultiplier(perfectStreak);

    final visibleTasks = _selectedCategoryFilter == 'All'
        ? _todayTasks
        : _todayTasks.where((t) => (t['category'] as String).toLowerCase() == _selectedCategoryFilter.toLowerCase()).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Unified Clean Overview Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF141824),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF22293A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('EEEE, MMM d').format(_today),
                          style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          rankName,
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        "${NumberFormat('#,###').format(totalRr)} RR",
                        style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 7,
                    backgroundColor: const Color(0xFF0B0E14),
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "$completedCount of ${_todayTasks.length} completed today",
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    Text(
                      rankIdx < SystemRanks.hunterLadder.length - 1
                          ? "${nextMinRr - totalRr} RR to ${SystemRanks.hunterLadder[rankIdx + 1]['name']}"
                          : "Max Rank Achieved",
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(color: Color(0xFF202636), height: 1),
                const SizedBox(height: 12),
                // 4 Compact Status Pills (including 1-tap Sleep Sync)
                Row(
                  children: [
                    _compactStatusPill(Icons.local_fire_department, "$currentStreak d", "Streak", const Color(0xFFF97316), null),
                    const SizedBox(width: 8),
                    _compactStatusPill(Icons.bolt, "${streakMult}x", "Perfect", const Color(0xFFFBBF24), null),
                    const SizedBox(width: 8),
                    _compactStatusPill(Icons.shield_outlined, "$shieldCharges/3", "Shields", const Color(0xFF38BDF8), null),
                    const SizedBox(width: 8),
                    _compactStatusPill(Icons.bedtime_outlined, sleepShortLabel, "Sleep", sleepTierColor, _showSleepSyncModal),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (_activeSurgeQuest != null) ...[
            _buildSurgeQuestBanner(_activeSurgeQuest!, accent),
            const SizedBox(height: 16),
          ],

          // Clean Category Filter Row
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: ['All', 'Academic', 'Fitness', 'General'].map((cat) {
                      final isSelected = _selectedCategoryFilter == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text(cat),
                          selected: isSelected,
                          showCheckmark: false,
                          onSelected: (val) {
                            if (val) {
                              HapticFeedback.selectionClick();
                              setState(() => _selectedCategoryFilter = cat);
                            }
                          },
                          selectedColor: accent,
                          backgroundColor: const Color(0xFF141824),
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.black : Colors.white70,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: isSelected ? accent : const Color(0xFF22293A)),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (visibleTasks.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 44),
              alignment: Alignment.center,
              child: const Text(
                "No quests scheduled for today.",
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
            )
          else
            ...visibleTasks.map((task) => _buildCleanQuestCard(task, accent)),

          const SizedBox(height: 60),
        ],
      ),
    );
  }

  Widget _compactStatusPill(IconData icon, String value, String label, Color color, VoidCallback? onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1017),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: onTap != null ? color.withValues(alpha: 0.4) : const Color(0xFF1E2433)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: color, size: 13),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      value,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSurgeQuestBanner(JsonMap surge, Color accent) {
    final int expireEpoch = surge['expire_epoch'] as int;
    final int minsRemaining = max(0, (expireEpoch - DateTime.now().millisecondsSinceEpoch) ~/ 60000);
    final bool isLockedGamble = surge['status'] == 'accepted_gamble';
    final bool effectiveGamble = isLockedGamble || _surgeGambleArmed;

    final int baseRr = surge['base_rr'] as int;
    final double mult = _getPerfectStreakMultiplier(perfectStreak) * sleepRrMultiplier;
    final int scaledReward = ((baseRr * (effectiveGamble ? 2 : 1)) * mult).round();
    final int gambleLoss = baseRr * 2;

    final Color bannerColor = effectiveGamble ? const Color(0xFFF43F5E) : accent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141824),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: bannerColor.withValues(alpha: 0.6), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.flash_on, color: bannerColor, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    effectiveGamble ? "2x Gamble Quest" : "Free-Time Bonus Quest",
                    style: TextStyle(color: bannerColor, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ],
              ),
              Text("${minsRemaining}m left", style: TextStyle(color: bannerColor, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            surge['title'] as String,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            effectiveGamble
                ? "${surge['description']} · Risking -$gambleLoss RR if not completed in time."
                : "${surge['description']} · Optional bonus RR.",
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          if (!isLockedGamble) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Double-or-Nothing Gamble (2x RR / -$gambleLoss RR)",
                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
                ),
                Switch(
                  value: _surgeGambleArmed,
                  activeThumbColor: const Color(0xFFF43F5E),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (val) {
                    HapticFeedback.selectionClick();
                    setState(() => _surgeGambleArmed = val);
                  },
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white60,
                    side: const BorderSide(color: Color(0xFF22293A)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _dismissSurgeQuest(surge),
                  child: Text(isLockedGamble ? "Forfeit (-$gambleLoss)" : "Dismiss", style: const TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: bannerColor,
                    foregroundColor: effectiveGamble ? Colors.white : Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    if (_surgeGambleArmed && !isLockedGamble) {
                      _lockInTarnishedGamble(surge);
                    } else {
                      _completeSurgeQuest(surge);
                    }
                  },
                  child: Text(
                    _surgeGambleArmed && !isLockedGamble ? "Lock Gamble" : "Complete (+$scaledReward RR)",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCleanQuestCard(JsonMap task, Color accent) {
    final todayStr = _formatDate(_today);
    final bool isCompleted = task['last_completed_date'] == todayStr;
    final int requireGps = (task['require_gps'] as int?) ?? 1;
    final String description = (task['description'] as String?) ?? '';
    final int isBoss = (task['is_boss'] as int?) ?? 0;
    final int prepStacks = _getEffectiveBossPrepStacks(task);
    final String pStat = (task['primary_stat'] as String?) ?? 'INT';
    final String sStat = (task['secondary_stat'] as String?) ?? 'PER';
    final int skillId = (task['skill_id'] as int?) ?? -1;
    final skill = _findSkillById(skillId);

    final Color cardAccent = isBoss == 1 ? const Color(0xFFFBBF24) : accent;

    final now = DateTime.now();
    final startDt = DateTime(now.year, now.month, now.day, task['start_hour'] as int, task['start_minute'] as int);
    final endDt = DateTime(now.year, now.month, now.day, task['end_hour'] as int, task['end_minute'] as int);
    final windowStart = startDt.subtract(const Duration(minutes: 15));
    final windowEnd = endDt.add(const Duration(minutes: 15));

    final bool isWindowOpen = now.isAfter(windowStart) && now.isBefore(windowEnd);
    final bool isPastWindow = now.isAfter(windowEnd);
    final bool canCheckIn = !isCompleted && isWindowOpen;

    final String timeLabel =
        "${task['start_hour'].toString().padLeft(2, '0')}:${task['start_minute'].toString().padLeft(2, '0')} – ${task['end_hour'].toString().padLeft(2, '0')}:${task['end_minute'].toString().padLeft(2, '0')}";

    return GestureDetector(
      onTap: () => _showTaskDetailSheet(task, _today),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: const Color(0xFF141824),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isCompleted
                ? const Color(0xFF10B981).withValues(alpha: 0.45)
                : isBoss == 1
                    ? const Color(0xFFFBBF24).withValues(alpha: 0.5)
                    : const Color(0xFF22293A),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        timeLabel,
                        style: TextStyle(
                          color: isWindowOpen ? cardAccent : Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: cardAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isBoss == 1 ? "👑 Boss ($prepStacks/5)" : "+$pStat / +$sStat",
                          style: TextStyle(color: cardAccent, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (requireGps == 1) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.location_on, color: Colors.white30, size: 13),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    task['title'] as String,
                    style: TextStyle(
                      color: isCompleted ? Colors.white38 : Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      decoration: isCompleted ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    skill != null
                        ? "${skill['name']} (${SystemRanks.getSkillRankLetter((skill['mastery_xp'] as int?) ?? 0)}-Rank)${description.isNotEmpty ? ' · $description' : ''}"
                        : (description.isNotEmpty ? description : "${task['category']} · Stat-Only"),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: canCheckIn ? cardAccent : const Color(0xFF1D2333),
                foregroundColor: canCheckIn ? Colors.black : Colors.white30,
                disabledBackgroundColor: const Color(0xFF1A1F2E),
                disabledForegroundColor: Colors.white30,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              onPressed: canCheckIn ? () => _attemptCheckIn(task) : null,
              child: Text(
                isCompleted
                    ? "Done"
                    : isWindowOpen
                        ? (isBoss == 1 ? "Resolve" : "Check In")
                        : isPastWindow
                            ? "Missed"
                            : "Locked",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // TAB 1: CALENDAR (Clean Monthly Grid + Green/Red Outlined Timetable)
  // ============================================================================
  Widget _buildCalendarTab() {
    final accent = accentColor;
    final int year = _calendarMonthCursor.year;
    final int month = _calendarMonthCursor.month;
    final int daysInMonth = DateTime(year, month + 1, 0).day;
    final int firstWeekdayOffset = DateTime(year, month, 1).weekday - 1;
    final todayOnly = DateTime(_today.year, _today.month, _today.day);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF141824),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF22293A)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, color: Colors.white70),
                      onPressed: () => setState(() => _calendarMonthCursor = DateTime(year, month - 1, 1)),
                    ),
                    Text(
                      DateFormat('MMMM yyyy').format(_calendarMonthCursor),
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, color: Colors.white70),
                      onPressed: () => setState(() => _calendarMonthCursor = DateTime(year, month + 1, 1)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                      .map((d) => SizedBox(
                            width: 34,
                            child: Text(d, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    childAspectRatio: 1.0,
                  ),
                  itemCount: firstWeekdayOffset + daysInMonth,
                  itemBuilder: (context, idx) {
                    if (idx < firstWeekdayOffset) return const SizedBox.shrink();
                    final int dayNum = idx - firstWeekdayOffset + 1;
                    final DateTime cellDate = DateTime(year, month, dayNum);
                    final String cellStr = _formatDate(cellDate);
                    final bool isSelected = _formatDate(_selectedCalendarDate) == cellStr;
                    final bool isTodayCell = _formatDate(todayOnly) == cellStr;

                    final dayTasks = _allTasks.where((t) => _isTaskActiveOnDate(t, cellDate)).toList();
                    final bool hasBoss = dayTasks.any((t) => (t['is_boss'] as int? ?? 0) == 1);
                    final bool allCleared = dayTasks.isNotEmpty && dayTasks.every((t) => t['last_completed_date'] == cellStr);
                    final bool hasMissed = cellDate.isBefore(todayOnly) && dayTasks.any((t) => t['last_completed_date'] != cellStr);

                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _selectedCalendarDate = cellDate;
                          _filterTasks();
                        });
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? accent
                              : isTodayCell
                                  ? accent.withValues(alpha: 0.14)
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: isTodayCell && !isSelected ? Border.all(color: accent.withValues(alpha: 0.5)) : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "$dayNum",
                              style: TextStyle(
                                color: isSelected ? Colors.black : (isTodayCell ? accent : Colors.white),
                                fontWeight: isSelected || isTodayCell ? FontWeight.bold : FontWeight.normal,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 3),
                            if (dayTasks.isNotEmpty)
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected
                                      ? Colors.black
                                      : hasBoss
                                          ? const Color(0xFFFBBF24)
                                          : allCleared
                                              ? const Color(0xFF10B981)
                                              : hasMissed
                                                  ? const Color(0xFFF43F5E)
                                                  : accent,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            DateFormat('EEEE, MMMM d').format(_selectedCalendarDate),
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          _buildContiguousIntervalsList(accent),
          const SizedBox(height: 60),
        ],
      ),
    );
  }

  Widget _buildContiguousIntervalsList(Color accent) {
    const int dayStart = 360;
    const int dayEnd = 1380;

    final List<Widget> blocks = [];
    int cursor = dayStart;

    final selectedDateStr = _formatDate(_selectedCalendarDate);
    final now = DateTime.now();
    final todayDayOnly = DateTime(now.year, now.month, now.day);
    final selectedDayOnly = DateTime(_selectedCalendarDate.year, _selectedCalendarDate.month, _selectedCalendarDate.day);

    for (final task in _calendarDayTasks) {
      final int taskStart = (task['start_hour'] as int) * 60 + (task['start_minute'] as int);
      final int taskEnd = (task['end_hour'] as int) * 60 + (task['end_minute'] as int);

      if (taskStart > cursor) {
        blocks.add(_buildScheduleIntervalCard(
          startTime: _formatMinutes(cursor),
          endTime: _formatMinutes(taskStart),
          title: "Free Time",
          accent: accent,
          isFreeTime: true,
          isBoss: false,
          status: 'none',
          onTap: null,
        ));
      }

      final bool isCompletedOnDay = task['last_completed_date'] == selectedDateStr;
      bool isMissedOnDay = false;

      if (!isCompletedOnDay) {
        if (selectedDayOnly.isBefore(todayDayOnly)) {
          isMissedOnDay = true;
        } else if (selectedDayOnly.isAtSameMomentAs(todayDayOnly)) {
          final endDt = DateTime(now.year, now.month, now.day, task['end_hour'] as int, task['end_minute'] as int)
              .add(const Duration(minutes: 15));
          if (now.isAfter(endDt)) {
            isMissedOnDay = true;
          }
        }
      }

      final String status = isCompletedOnDay
          ? 'completed'
          : isMissedOnDay
              ? 'missed'
              : 'upcoming';

      final bool isBoss = (task['is_boss'] as int? ?? 0) == 1;

      blocks.add(_buildScheduleIntervalCard(
        startTime: _formatMinutes(taskStart),
        endTime: _formatMinutes(taskEnd),
        title: isBoss ? "👑 ${task['title']}" : (task['title'] as String),
        description: task['description'] as String?,
        accent: accent,
        isFreeTime: false,
        isBoss: isBoss,
        status: status,
        onTap: () => _showTaskDetailSheet(task, _selectedCalendarDate),
      ));

      cursor = max(cursor, taskEnd);
    }

    if (cursor < dayEnd) {
      blocks.add(_buildScheduleIntervalCard(
        startTime: _formatMinutes(cursor),
        endTime: _formatMinutes(dayEnd),
        title: "Free Time",
        accent: accent,
        isFreeTime: true,
        isBoss: false,
        status: 'none',
        onTap: null,
      ));
    }

    return Column(children: blocks);
  }

  Widget _buildScheduleIntervalCard({
    required String startTime,
    required String endTime,
    required String title,
    String? description,
    required Color accent,
    required bool isFreeTime,
    required bool isBoss,
    required String status,
    VoidCallback? onTap,
  }) {
    if (isFreeTime) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            SizedBox(
              width: 88,
              child: Text("$startTime – $endTime", style: const TextStyle(color: Colors.white24, fontSize: 11)),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0E121B),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text("Free Time", style: TextStyle(color: Colors.white24, fontSize: 12)),
              ),
            ),
          ],
        ),
      );
    }

    Color borderColor = const Color(0xFF22293A);
    Color bgColor = const Color(0xFF141824);
    if (status == 'completed') {
      borderColor = const Color(0xFF10B981);
      bgColor = const Color(0xFF10B981).withValues(alpha: 0.10);
    } else if (status == 'missed') {
      borderColor = const Color(0xFFF43F5E);
      bgColor = const Color(0xFFF43F5E).withValues(alpha: 0.10);
    } else if (isBoss) {
      borderColor = const Color(0xFFFBBF24).withValues(alpha: 0.6);
    }

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            SizedBox(
              width: 88,
              child: Text(
                "$startTime – $endTime",
                style: TextStyle(color: isBoss ? const Color(0xFFFBBF24) : Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: status == 'upcoming' ? 1.0 : 1.5),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                          if (description != null && description.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(description, style: const TextStyle(color: Colors.white54, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ],
                      ),
                    ),
                    if (status == 'completed')
                      const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 18)
                    else if (status == 'missed')
                      const Icon(Icons.cancel, color: Color(0xFFF43F5E), size: 18)
                    else
                      const Icon(Icons.chevron_right, color: Colors.white30, size: 18),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // TAB 2: SKILLS & CUSTOM SKILL CATEGORIES
  // ============================================================================
  Widget _buildSkillsTab() {
    final accent = accentColor;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Core Attributes Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF141824),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF22293A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Core Attributes", style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 190,
                  child: CustomPaint(
                    size: const Size(double.infinity, 190),
                    painter: _AttributeRadarPainter(
                      strLv: (strXp ~/ 100) + 1,
                      vitLv: (vitXp ~/ 100) + 1,
                      intLv: (intXp ~/ 100) + 1,
                      perLv: (perXp ~/ 100) + 1,
                      agiLv: (agiXp ~/ 100) + 1,
                      auraColor: accent,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _buildStatProgressRow("Strength (STR)", strXp, accent),
                _buildStatProgressRow("Vitality (VIT)", vitXp, const Color(0xFF10B981)),
                _buildStatProgressRow("Intelligence (INT)", intXp, const Color(0xFF818CF8)),
                _buildStatProgressRow("Perception (PER)", perXp, const Color(0xFFFBBF24)),
                _buildStatProgressRow("Agility (AGI)", agiXp, const Color(0xFFF43F5E)),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // Skill Categories Header with "+ Category" and "+ Skill"
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Skill Categories", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Color(0xFF22293A)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _showAddCategoryDialog,
                    icon: const Icon(Icons.create_new_folder_outlined, size: 15),
                    label: const Text("Category", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _showCreateSkillModal,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text("Skill", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          ..._skillCategories.map((cat) {
            final catSkills = _skills.where((s) => (s['category'] as String).toLowerCase() == cat.toLowerCase()).toList();

            double avgNumeric = 1.0;
            if (catSkills.isNotEmpty) {
              final sum = catSkills.fold<int>(0, (acc, s) => acc + SystemRanks.getSkillRankNumeric((s['mastery_xp'] as int?) ?? 0));
              avgNumeric = sum / catSkills.length;
            }
            // Strict floor-rounded average rank
            final int flooredRank = avgNumeric.floor().clamp(1, 6);
            final String catLetter = catSkills.isEmpty ? 'E' : SystemRanks.numericToLetter(flooredRank);
            final Color catBadgeColor = SystemRanks.getLetterColor(catLetter, accent);
            final bool isExpanded = _expandedSkillCategories.contains(cat);

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF141824),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF22293A)),
              ),
              child: Column(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        if (isExpanded) {
                          _expandedSkillCategories.remove(cat);
                        } else {
                          _expandedSkillCategories.add(cat);
                        }
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Icon(isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, color: Colors.white54, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(cat, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                                Text(
                                  catSkills.isEmpty ? "No skills yet" : "${catSkills.length} skill(s) · Avg ${avgNumeric.toStringAsFixed(1)} (Floored)",
                                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: catBadgeColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text("$catLetter-Rank", style: TextStyle(color: catBadgeColor, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (isExpanded)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: catSkills.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text("Tap '+ Skill' to add a discipline to this category.", style: TextStyle(color: Colors.white38, fontSize: 12)),
                            )
                          : Column(
                              children: catSkills.map((skill) {
                                final int xp = (skill['mastery_xp'] as int?) ?? 0;
                                final String letter = SystemRanks.getSkillRankLetter(xp);
                                final Color sColor = SystemRanks.getLetterColor(letter, accent);
                                final int prevT = SystemRanks.getPrevSkillThreshold(xp);
                                final int nextT = SystemRanks.getNextSkillThreshold(xp);
                                final double frac = ((xp - prevT) / max(1, nextT - prevT)).clamp(0.0, 1.0);
                                final int bonusPct = (SystemRanks.getSkillRrBonusMultiplier(xp) * 100).round();

                                return Container(
                                  margin: const EdgeInsets.only(top: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0D1017),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(skill['name'] as String, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: sColor.withValues(alpha: 0.16),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text("$letter-Rank", style: TextStyle(color: sColor, fontWeight: FontWeight.bold, fontSize: 11)),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "+${skill['primary_stat']} / +${skill['secondary_stat']} · Passive: +$bonusPct% RR",
                                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(4),
                                              child: LinearProgressIndicator(
                                                value: frac,
                                                minHeight: 5,
                                                backgroundColor: const Color(0xFF1A202E),
                                                valueColor: AlwaysStoppedAnimation<Color>(sColor),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Text("$xp / $nextT XP", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                    ),
                ],
              ),
            );
          }),

          const SizedBox(height: 50),
        ],
      ),
    );
  }

  Widget _buildStatProgressRow(String label, int xp, Color color) {
    final int lv = (xp ~/ 100) + 1;
    final int modXp = xp % 100;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
              Text("Lv.$lv  ($modXp/100 XP)", style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: modXp / 100.0,
              minHeight: 6,
              backgroundColor: const Color(0xFF0D1017),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // TAB 3: PROFILE (Milestones, Rank Ladder, Theme & Backup)
  // ============================================================================
  Widget _buildProfileTab() {
    final accent = accentColor;
    final int currentRankIdx = SystemRanks.getRankIndex(totalRr);
    final String currentRankName = SystemRanks.hunterLadder[currentRankIdx]['name'] as String;
    final String peakRankName = SystemRanks.hunterLadder[highestRankIdx.clamp(0, 9)]['name'] as String;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF141824),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF22293A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(currentRankName, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text("${NumberFormat('#,###').format(totalRr)} Total RR · Peak: $peakRankName", style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _profileMetricBox("Current Streak", "$currentStreak days"),
                    const SizedBox(width: 10),
                    _profileMetricBox("Best Streak", "$highestStreak days"),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _profileMetricBox("Perfect Streak", "$perfectStreak days"),
                    const SizedBox(width: 10),
                    _profileMetricBox("Rest Shields", "$shieldCharges / 3"),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Theme Accent Picker
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF141824),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF22293A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Accent Theme", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: themePalette.map((item) {
                    final Color c = item['color'] as Color;
                    final bool isSelected = _uiColorOverride == c.toARGB32();
                    return GestureDetector(
                      onTap: () => _setAccentColor(c.toARGB32()),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? c.withValues(alpha: 0.18) : const Color(0xFF0D1017),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isSelected ? c : const Color(0xFF22293A)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 12, height: 12, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Text(item['name'] as String, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Rank Ladder
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF141824),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF22293A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Rank Progression Ladder", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                ...SystemRanks.hunterLadder.map((tier) {
                  final int idx = tier['index'] as int;
                  final bool isCurrent = idx == currentRankIdx;
                  final bool isUnlocked = idx <= currentRankIdx;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isCurrent ? accent.withValues(alpha: 0.14) : const Color(0xFF0D1017),
                      borderRadius: BorderRadius.circular(8),
                      border: isCurrent ? Border.all(color: accent) : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          tier['name'] as String,
                          style: TextStyle(
                            color: isCurrent ? accent : (isUnlocked ? Colors.white : Colors.white38),
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          "${NumberFormat('#,###').format(tier['minRr'])} RR",
                          style: TextStyle(color: isCurrent ? accent : Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Backup & Restore
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF141824),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF22293A)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _exportProfileData,
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text("Export Backup", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF22293A)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _importProfileDataPrompt,
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text("Restore Backup", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 50),
        ],
      ),
    );
  }

  Widget _profileMetricBox(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1017),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// ADD TASK SCREEN (Clean 3-Section Layout)
// ============================================================================

class AddTaskScreen extends StatefulWidget {
  final DateTime? initialDate;
  final JsonList skills;
  final Color accentColor;

  const AddTaskScreen({
    super.key,
    this.initialDate,
    required this.skills,
    required this.accentColor,
  });

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final MapController _mapController = MapController();

  LatLng _selectedLatLng = const LatLng(45.7471, 21.2315);
  double _radiusMeters = 150.0;

  String _selectedCategory = 'Academic';
  final List<String> _categories = ['Academic', 'Fitness', 'General'];

  String _primaryStat = 'INT';
  String _secondaryStat = 'PER';
  bool _manualStatOverride = false;
  int _selectedSkillId = -1;

  String _recurrenceType = 'weekly';
  bool _isBossEncounter = false;
  int _bossStake = 400;

  late DateTime _questDate;
  DateTime? _recurrenceStart;
  DateTime? _recurrenceEnd;

  TimeOfDay startTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay endTime = const TimeOfDay(hour: 10, minute: 0);
  bool _fetchingLocation = false;

  final List<String> dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  final Set<int> selectedDays = {1, 2, 3, 4, 5};

  bool _notifyEnabled = true;
  final Set<int> _selectedLeadTimes = {15};
  bool _requireGps = true;

  @override
  void initState() {
    super.initState();
    final init = widget.initialDate ?? DateTime.now();
    _questDate = DateTime(init.year, init.month, init.day);
    _recurrenceStart = _questDate;

    if (widget.initialDate != null) {
      selectedDays.clear();
      selectedDays.add(widget.initialDate!.weekday);
    }

    _titleController.addListener(_onTitleChanged);
  }

  @override
  void dispose() {
    _titleController.removeListener(_onTitleChanged);
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _onTitleChanged() {
    if (_manualStatOverride || _selectedSkillId != -1) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final prediction = AutoStatClassifier.classify(title);
    setState(() {
      _selectedCategory = prediction['category'] as String;
      _primaryStat = prediction['primary'] as String;
      _secondaryStat = prediction['secondary'] as String;
      if (prediction['isBoss'] == true && !_isBossEncounter) {
        _isBossEncounter = true;
        _recurrenceType = 'once';
      }
    });
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(context: context, initialTime: startTime);
    if (picked != null) setState(() => startTime = picked);
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(context: context, initialTime: endTime);
    if (picked != null) setState(() => endTime = picked);
  }

  Future<void> _pickSingleDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _questDate,
      firstDate: DateTime(2025, 1, 1),
      lastDate: DateTime(2030, 12, 31),
    );
    if (picked != null) {
      setState(() {
        _questDate = picked;
        _recurrenceStart = picked;
        selectedDays.clear();
        selectedDays.add(picked.weekday);
      });
    }
  }

  Future<void> _pickRecurrenceDate(bool isStart) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? (_recurrenceStart ?? now) : (_recurrenceEnd ?? now.add(const Duration(days: 90))),
      firstDate: DateTime(2025, 1, 1),
      lastDate: DateTime(2030, 12, 31),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _recurrenceStart = picked;
          _questDate = picked;
        } else {
          _recurrenceEnd = picked;
        }
      });
    }
  }

  Future<void> _centerMapOnCurrentLocation() async {
    setState(() => _fetchingLocation = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      final newPos = LatLng(pos.latitude, pos.longitude);
      setState(() => _selectedLatLng = newPos);
      _mapController.move(newPos, 16.0);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not fetch GPS. Check location settings.')),
      );
    } finally {
      if (mounted) setState(() => _fetchingLocation = false);
    }
  }

  Future<void> _saveTask() async {
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final double lat = _requireGps ? _selectedLatLng.latitude : 0.0;
    final double lng = _requireGps ? _selectedLatLng.longitude : 0.0;
    final df = DateFormat('yyyy-MM-dd');

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a quest title.')));
      return;
    }

    if ((_recurrenceType == 'weekly' || _recurrenceType == 'biweekly') && selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select at least one day.')));
      return;
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'habits.db');
    final db = await openDatabase(path);

    String repeatDaysStr = '1,2,3,4,5,6,7';
    String? startStr;
    String? endStr;

    if (_recurrenceType == 'once') {
      startStr = df.format(_questDate);
      endStr = df.format(_questDate);
      repeatDaysStr = '${_questDate.weekday}';
    } else if (_recurrenceType == 'monthly') {
      startStr = df.format(_questDate);
      endStr = _recurrenceEnd != null ? df.format(_recurrenceEnd!) : null;
      repeatDaysStr = '${_questDate.weekday}';
    } else if (_recurrenceType == 'biweekly') {
      repeatDaysStr = (selectedDays.toList()..sort()).join(',');
      startStr = df.format(_recurrenceStart ?? _questDate);
      endStr = _recurrenceEnd != null ? df.format(_recurrenceEnd!) : null;
    } else {
      repeatDaysStr = (selectedDays.toList()..sort()).join(',');
      startStr = _recurrenceStart != null ? df.format(_recurrenceStart!) : null;
      endStr = _recurrenceEnd != null ? df.format(_recurrenceEnd!) : null;
    }

    final leadsStr = (_selectedLeadTimes.toList()..sort()).join(',');

    await db.insert('tasks', {
      'title': title,
      'category': _selectedCategory,
      'description': description,
      'color_value': widget.accentColor.toARGB32(),
      'start_hour': startTime.hour,
      'start_minute': startTime.minute,
      'end_hour': endTime.hour,
      'end_minute': endTime.minute,
      'target_lat': lat,
      'target_lng': lng,
      'radius_meters': _radiusMeters,
      'repeat_days': repeatDaysStr,
      'last_completed_date': null,
      'is_completed': 0,
      'recurrence_start_date': startStr,
      'recurrence_end_date': endStr,
      'recurrence_type': _recurrenceType,
      'notify_enabled': _notifyEnabled ? 1 : 0,
      'notify_leads': leadsStr.isEmpty ? "15" : leadsStr,
      'require_gps': _requireGps ? 1 : 0,
      'excluded_dates': '',
      'penalty_applied_date': '',
      'is_boss': _isBossEncounter ? 1 : 0,
      'boss_stake': _bossStake,
      'prep_stacks': 0,
      'primary_stat': _primaryStat,
      'secondary_stat': _secondaryStat,
      'skill_id': _selectedSkillId,
    });

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd');
    final accent = widget.accentColor;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        title: const Text('New Quest', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF141824),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // SECTION 1: DETAILS & SKILL/STATS
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF141824),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF22293A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Title (e.g. BJJ Sparring, Accounting Seminar)',
                      labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF0D1017),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _descriptionController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Location / Notes (Optional)',
                      labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF0D1017),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Category', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Row(
                    children: _categories.map((cat) {
                      final isSelected = _selectedCategory == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text(cat),
                          selected: isSelected,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _selectedCategory = cat),
                          selectedColor: accent,
                          backgroundColor: const Color(0xFF0D1017),
                          labelStyle: TextStyle(color: isSelected ? Colors.black : Colors.white70, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  const Text('Linked Skill (Optional)', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                  DropdownButton<int>(
                    value: _selectedSkillId,
                    dropdownColor: const Color(0xFF141824),
                    isExpanded: true,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    items: [
                      const DropdownMenuItem<int>(
                        value: -1,
                        child: Text("None — Stat-Only Quest", style: TextStyle(color: Colors.white70)),
                      ),
                      ...widget.skills.map((s) {
                        final letter = SystemRanks.getSkillRankLetter((s['mastery_xp'] as int?) ?? 0);
                        return DropdownMenuItem<int>(
                          value: s['id'] as int,
                          child: Text("${s['name']} ($letter-Rank · ${s['category']})"),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      if (val == null) return;
                      setState(() {
                        _selectedSkillId = val;
                        if (val != -1) {
                          final sk = widget.skills.firstWhere((s) => s['id'] == val);
                          _primaryStat = sk['primary_stat'] as String;
                          _secondaryStat = sk['secondary_stat'] as String;
                          _manualStatOverride = true;
                        } else {
                          _manualStatOverride = false;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Target Attributes', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                      Text(
                        _manualStatOverride ? 'Manual / Skill Sync' : 'Auto-Detected',
                        style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: ['STR', 'VIT', 'INT', 'PER', 'AGI'].map((stat) {
                      final isPrimary = _primaryStat == stat;
                      final isSecondary = _secondaryStat == stat;
                      return ChoiceChip(
                        label: Text(isPrimary ? "$stat (1°)" : (isSecondary ? "$stat (2°)" : stat)),
                        selected: isPrimary || isSecondary,
                        showCheckmark: false,
                        selectedColor: isPrimary ? accent : accent.withValues(alpha: 0.4),
                        backgroundColor: const Color(0xFF0D1017),
                        labelStyle: TextStyle(color: isPrimary ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                        onSelected: (_) {
                          setState(() {
                            _manualStatOverride = true;
                            if (!isPrimary) {
                              _secondaryStat = _primaryStat;
                              _primaryStat = stat;
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // SECTION 2: SCHEDULE & RECURRENCE
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF141824),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF22293A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Time & Schedule', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF22293A)),
                            backgroundColor: const Color(0xFF0D1017),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: _pickStartTime,
                          icon: Icon(Icons.access_time, color: accent, size: 16),
                          label: Text('Start: ${startTime.format(context)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF22293A)),
                            backgroundColor: const Color(0xFF0D1017),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: _pickEndTime,
                          icon: Icon(Icons.access_time_filled, color: accent, size: 16),
                          label: Text('End: ${endTime.format(context)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        {'id': 'once', 'label': 'One-Time'},
                        {'id': 'weekly', 'label': 'Weekly'},
                        {'id': 'biweekly', 'label': 'Every 2 Weeks'},
                        {'id': 'monthly', 'label': 'Monthly'},
                      ].map((item) {
                        final isSelected = _recurrenceType == item['id'];
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ChoiceChip(
                            label: Text(item['label']!),
                            selected: isSelected,
                            showCheckmark: false,
                            onSelected: (_) => setState(() => _recurrenceType = item['id']!),
                            selectedColor: accent,
                            backgroundColor: const Color(0xFF0D1017),
                            labelStyle: TextStyle(color: isSelected ? Colors.black : Colors.white70, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_recurrenceType == 'once' || _recurrenceType == 'monthly')
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFF22293A)),
                          backgroundColor: const Color(0xFF0D1017),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: _pickSingleDate,
                        icon: Icon(Icons.event, color: accent, size: 18),
                        label: Text(
                          _recurrenceType == 'once'
                              ? DateFormat('EEEE, MMM d, yyyy').format(_questDate)
                              : 'Starts ${df.format(_questDate)} (Day ${_questDate.day} monthly)',
                        ),
                      ),
                    )
                  else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(7, (index) {
                        final dayNumber = index + 1;
                        final isSelected = selectedDays.contains(dayNumber);
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                selectedDays.remove(dayNumber);
                              } else {
                                selectedDays.add(dayNumber);
                              }
                            });
                          },
                          child: Container(
                            width: 38,
                            height: 38,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected ? accent : const Color(0xFF0D1017),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(dayLabels[index], style: TextStyle(color: isSelected ? Colors.black : Colors.white70, fontWeight: FontWeight.bold)),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Color(0xFF22293A)), backgroundColor: const Color(0xFF0D1017)),
                            onPressed: () => _pickRecurrenceDate(true),
                            child: Text(_recurrenceStart == null ? 'From: Any' : 'From: ${df.format(_recurrenceStart!)}', style: const TextStyle(fontSize: 11)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Color(0xFF22293A)), backgroundColor: const Color(0xFF0D1017)),
                            onPressed: () => _pickRecurrenceDate(false),
                            child: Text(_recurrenceEnd == null ? 'To: Ongoing' : 'To: ${df.format(_recurrenceEnd!)}', style: const TextStyle(fontSize: 11)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // SECTION 3: LOCATION, BOSS MODE & REMINDERS
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF141824),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF22293A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.location_on_outlined, color: Colors.white70, size: 18),
                          SizedBox(width: 8),
                          Text('Require GPS Geofence', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                        ],
                      ),
                      Switch(value: _requireGps, activeThumbColor: accent, onChanged: (val) => setState(() => _requireGps = val)),
                    ],
                  ),
                  if (_requireGps) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        height: 190,
                        child: Stack(
                          children: [
                            FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                initialCenter: _selectedLatLng,
                                initialZoom: 15.0,
                                onTap: (tapPosition, point) {
                                  HapticFeedback.selectionClick();
                                  setState(() => _selectedLatLng = point);
                                },
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName: 'com.valence.habits',
                                ),
                                CircleLayer(
                                  circles: [
                                    CircleMarker(
                                      point: _selectedLatLng,
                                      radius: _radiusMeters,
                                      useRadiusInMeter: true,
                                      color: accent.withValues(alpha: 0.22),
                                      borderColor: accent,
                                      borderStrokeWidth: 2,
                                    ),
                                  ],
                                ),
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: _selectedLatLng,
                                      width: 40,
                                      height: 40,
                                      child: Icon(Icons.location_pin, color: accent, size: 38),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: FloatingActionButton.small(
                                heroTag: 'gps_center_btn',
                                backgroundColor: const Color(0xFF141824),
                                foregroundColor: accent,
                                onPressed: _fetchingLocation ? null : _centerMapOnCurrentLocation,
                                child: _fetchingLocation
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.my_location, size: 18),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Radius', style: TextStyle(color: Colors.white54, fontSize: 12)),
                        Text('${_radiusMeters.toInt()} m', style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                    Slider(
                      value: _radiusMeters,
                      min: 50,
                      max: 500,
                      divisions: 18,
                      activeColor: accent,
                      inactiveColor: const Color(0xFF22293A),
                      onChanged: (val) => setState(() => _radiusMeters = val),
                    ),
                  ],
                  const Divider(color: Color(0xFF22293A)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.whatshot_outlined, color: Color(0xFFFBBF24), size: 18),
                          SizedBox(width: 8),
                          Text('Boss Encounter (50/50 Check)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                        ],
                      ),
                      Switch(
                        value: _isBossEncounter,
                        activeThumbColor: const Color(0xFFFBBF24),
                        onChanged: (val) {
                          setState(() {
                            _isBossEncounter = val;
                            if (val) _recurrenceType = 'once';
                          });
                        },
                      ),
                    ],
                  ),
                  if (_isBossEncounter) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Stake Amount', style: TextStyle(color: Colors.white54, fontSize: 12)),
                        Text('±$_bossStake RR', style: const TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                    Slider(
                      value: _bossStake.toDouble(),
                      min: 200,
                      max: 1000,
                      divisions: 8,
                      activeColor: const Color(0xFFFBBF24),
                      inactiveColor: const Color(0xFF22293A),
                      onChanged: (val) => setState(() => _bossStake = val.round()),
                    ),
                  ],
                  const Divider(color: Color(0xFF22293A)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.notifications_none, color: Colors.white70, size: 18),
                          SizedBox(width: 8),
                          Text('Advance Reminders', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                        ],
                      ),
                      Switch(value: _notifyEnabled, activeThumbColor: accent, onChanged: (val) => setState(() => _notifyEnabled = val)),
                    ],
                  ),
                  if (_notifyEnabled)
                    Wrap(
                      spacing: 8,
                      children: [10, 15, 30, 60, 90].map((mins) {
                        final isSel = _selectedLeadTimes.contains(mins);
                        final label = mins >= 60 ? '${mins ~/ 60}h ${mins % 60 > 0 ? "${mins % 60}m" : ""}' : '${mins}m';
                        return FilterChip(
                          label: Text(label),
                          selected: isSel,
                          showCheckmark: false,
                          selectedColor: accent,
                          backgroundColor: const Color(0xFF0D1017),
                          labelStyle: TextStyle(color: isSel ? Colors.black : Colors.white70, fontWeight: FontWeight.bold, fontSize: 11),
                          onSelected: (val) {
                            setState(() {
                              if (val) {
                                _selectedLeadTimes.add(mins);
                              } else if (_selectedLeadTimes.length > 1) {
                                _selectedLeadTimes.remove(mins);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _isBossEncounter ? const Color(0xFFFBBF24) : accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _saveTask,
              child: Text(
                _isBossEncounter ? 'Save Boss Encounter' : 'Save Quest',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 5-AXIS ATTRIBUTE RADAR PENTAGON PAINTER
// ============================================================================

class _AttributeRadarPainter extends CustomPainter {
  final int strLv;
  final int vitLv;
  final int intLv;
  final int perLv;
  final int agiLv;
  final Color auraColor;

  _AttributeRadarPainter({
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
      ..color = Colors.white.withValues(alpha: 0.12)
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
      final norm = (values[i] / maxVal).clamp(0.18, 1.0);
      final pt = Offset(center.dx + cos(angle) * maxRadius * norm, center.dy + sin(angle) * maxRadius * norm);
      if (i == 0) {
        statPath.moveTo(pt.dx, pt.dy);
      } else {
        statPath.lineTo(pt.dx, pt.dy);
      }

      final outerPt = Offset(center.dx + cos(angle) * maxRadius, center.dy + sin(angle) * maxRadius);
      canvas.drawLine(center, outerPt, gridPaint);

      final labelPt = Offset(center.dx + cos(angle) * (maxRadius + 20) - 18, center.dy + sin(angle) * (maxRadius + 16) - 7);
      final tp = TextPainter(
        text: TextSpan(
          text: "${labels[i]} ${values[i]}",
          style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, labelPt);
    }
    statPath.close();

    canvas.drawPath(statPath, Paint()..color = auraColor.withValues(alpha: 0.25)..style = PaintingStyle.fill);
    canvas.drawPath(statPath, Paint()..color = auraColor..style = PaintingStyle.stroke..strokeWidth = 2.0);
  }

  @override
  bool shouldRepaint(covariant _AttributeRadarPainter oldDelegate) => true;
}

// ============================================================================
// CLEAN RANK ASCENSION DIALOG
// ============================================================================

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
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF141824),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: accentColor.withValues(alpha: 0.6), width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.workspace_premium, color: accentColor, size: 56),
              const SizedBox(height: 12),
              Text("Rank Up!", style: TextStyle(color: accentColor, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                newRankName,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              const Text(
                "Your consistency has unlocked the next Hunter rank tier.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    HapticFeedback.heavyImpact();
                    onClaimed();
                  },
                  child: const Text("Continue", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}