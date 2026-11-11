import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' show join;
import 'package:sqflite/sqflite.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_application_1/theme.dart';
import 'package:flutter_application_1/rpg_system.dart';
import 'package:flutter_application_1/add_task_screen.dart';
import 'package:flutter_application_1/health_service.dart';

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
      'System Directives',
      description: 'Notifications for daily operational directives',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await androidImpl.createNotificationChannel(questChannel);
    await androidImpl.requestNotificationsPermission();
    await androidImpl.requestExactAlarmsPermission();
  }

  runApp(MaterialApp(
    title: 'Valence System',
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: SystemTheme.background,
      canvasColor: SystemTheme.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: SystemTheme.surface,
        elevation: 0,
      ),
    ),
    home: const HabitApp(),
    debugShowCheckedModeBanner: false,
  ));
}

class HabitApp extends StatefulWidget {
  const HabitApp({super.key});

  static final JsonList themePalette = [
    {'name': 'Cyan Glow', 'color': SystemTheme.cyan},
    {'name': 'Mana Blue', 'color': SystemTheme.electricBlue},
    {'name': 'Shadow Violet', 'color': SystemTheme.shadowViolet},
    {'name': 'Monarch Gold', 'color': SystemTheme.monarchGold},
    {'name': 'Danger Red', 'color': SystemTheme.dangerRed},
  ];

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

  int _uiColorOverride = 0xFF00E5FF;

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

  static const JsonList microQuestPool = [
    {'title': '25 Push-ups Calibration', 'category': 'Fitness', 'primary': 'STR', 'secondary': 'VIT', 'baseRr': 25, 'desc': 'Physical calibration sequence.'},
    {'title': '15-Minute Recall Focus', 'category': 'Academic', 'primary': 'INT', 'secondary': 'PER', 'baseRr': 30, 'desc': 'Neural scan & memory consolidation.'},
    {'title': 'Shadow Striking Angles', 'category': 'Fitness', 'primary': 'AGI', 'secondary': 'PER', 'baseRr': 25, 'desc': 'Motor coordination & footwork calibration.'},
    {'title': 'Hydration & Posture Reset', 'category': 'General', 'primary': 'VIT', 'secondary': 'PER', 'baseRr': 20, 'desc': 'System fluid maintenance.'},
  ];

  @override
  void initState() {
    super.initState();
    _selectedCalendarDate = DateTime(_today.year, _today.month, _today.day);
    _calendarMonthCursor = DateTime(_today.year, _today.month, 1);
    _startApp();
  }

  Color get accentColor => Color(_uiColorOverride == -1 ? 0xFF00E5FF : _uiColorOverride);

  double get sleepRrMultiplier {
    if (sleepTier == 'fatigue') return 0.80;
    if (sleepTier == 'well_rested') return 1.15;
    return 1.00;
  }

  String get sleepTierLabel {
    if (sleepTier == 'fatigue') return 'Fatigue (-20%)';
    if (sleepTier == 'well_rested') return 'Restored (+15%)';
    return 'Nominal (1.0x)';
  }

  String _formatSleepTime(double decimalHours) {
    final int h = decimalHours.floor();
    final int m = ((decimalHours - h) * 60).round();
    return "$h:${m.toString().padLeft(2, '0')}";
  }

  String get sleepShortLabel => _formatSleepTime(sleepHours);

  Color get sleepTierColor {
    if (sleepTier == 'fatigue') return SystemTheme.dangerRed;
    if (sleepTier == 'well_rested') return SystemTheme.cyan;
    return SystemTheme.electricBlue;
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
            ui_color_override INTEGER DEFAULT 4278248959,
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
            color_value INTEGER DEFAULT 4278248959,
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
          'ui_color_override': 0xFF00E5FF,
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

  String _formatMinutes(int totalMinutes) {
    final int h = totalMinutes ~/ 60;
    final int m = totalMinutes % 60;
    return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}";
  }

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

    if (recurrenceType.startsWith('custom:')) {
      if (startDateStr == null || startDateStr.isEmpty) return false;
      try {
        final startDate = DateFormat('yyyy-MM-dd').parse(startDateStr);
        final parts = recurrenceType.replaceFirst('custom:', '').split('_');
        final int interval = int.tryParse(parts[0]) ?? 1;
        final String unit = parts.length > 1 ? parts[1] : 'days';

        if (unit == 'days') {
          final diff = targetDate.difference(startDate).inDays;
          return diff >= 0 && (diff % interval == 0);
        } else if (unit == 'weeks') {
          final diff = targetDate.difference(startDate).inDays;
          return diff >= 0 && ((diff ~/ 7) % interval == 0) && (diff % 7 == 0);
        } else if (unit == 'months') {
          final monthDiff = (targetDate.year - startDate.year) * 12 + targetDate.month - startDate.month;
          return monthDiff >= 0 && (monthDiff % interval == 0) && (targetDate.day == startDate.day);
        }
      } catch (_) {}
      return false;
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
    final Uri navUri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=walking');
    try {
      await launchUrl(navUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      final Uri geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
      if (await canLaunchUrl(geoUri)) {
        await launchUrl(geoUri);
      }
    }
  }

  Future<void> _startApp() async {
    final db = await database;
    final todayStr = _formatDate(_today);

    final profileRes = await db.query('user_profile', where: 'id = ?', whereArgs: [1]);
    final taskRes = await db.query('tasks');
    _allTasks = JsonList.from(taskRes);

    final skillRes = await db.query('skills', orderBy: 'category ASC, mastery_xp DESC');
    _skills = JsonList.from(skillRes);

    if (profileRes.isNotEmpty) {
      final profile = profileRes.first;
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
      final Set<String> catSet = savedCatsStr.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();
      for (final sk in _skills) {
        final c = (sk['category'] as String?)?.trim() ?? '';
        if (c.isNotEmpty) catSet.add(c);
      }
      _skillCategories = catSet.toList();
      _expandedSkillCategories.addAll(_skillCategories);

      final int savedUiColor = (profile['ui_color_override'] as int?) ?? 0xFF00E5FF;
      _uiColorOverride = savedUiColor == -1 ? 0xFF00E5FF : savedUiColor;

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
          } else {
            rr = max<int>(0, rr - totalPenalty);
            streak = 0;
            pStreak = 0;
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

      currentStreak = streak;
      highestStreak = max(maxStreak, streak);
      perfectStreak = pStreak;
      highestPerfectStreak = max(maxPStreak, pStreak);
      shieldCharges = shields;
      totalRr = rr;
      highestRankIdx = max(maxRank, SystemRanks.getRankIndex(rr));
    }

    _filterTasks();
    await _checkActiveSurgeQuest();
    await _checkAndApplyImmediatePenalties();
    await _rescheduleTaskNotifications();
    await _ensureDailySurgeQuestScheduled();

    if (sleepLoggedDate != todayStr) {
      await _autoSyncSleepFromWatch(silent: true);
    }
  }

  Future<void> _autoSyncSleepFromWatch({bool silent = false}) async {
    final granted = await HealthService.requestSleepPermissions();
    if (!granted) return;

    final double? watchHours = await HealthService.fetchLastNightSleepDuration();
    if (watchHours != null) {
      final todayStr = _formatDate(_today);
      final bool alreadyClaimedToday = sleepLoggedDate == todayStr;
      await _applySleepRecovery(watchHours, alreadyClaimedToday);
    }
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
      backgroundColor: SystemTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final String previewTier = _classifySleepHours(tempHours);
            final Color previewColor = previewTier == 'fatigue'
                ? SystemTheme.dangerRed
                : previewTier == 'well_rested'
                    ? SystemTheme.cyan
                    : SystemTheme.electricBlue;

            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          "RECOVERY CALIBRATION",
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                        ),
                      ),
                      SystemButton(
                        label: "SYNC",
                        icon: Icons.sync,
                        color: SystemTheme.cyan,
                        fontSize: 10,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await _autoSyncSleepFromWatch(silent: false);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("RECORDED TIME", style: TextStyle(color: Color(0xFF7E92A8), fontSize: 11, fontWeight: FontWeight.w600)),
                      Text(
                        _formatSleepTime(tempHours),
                        style: TextStyle(color: previewColor, fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  Slider(
                    value: tempHours,
                    min: 1.0,
                    max: 12.0,
                    divisions: 22,
                    activeColor: previewColor,
                    inactiveColor: SystemTheme.surfaceElevated,
                    onChanged: (val) => setModalState(() => tempHours = val),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SystemButton(
                      label: alreadyClaimedToday ? "OVERRIDE VALUE" : "CONFIRM RECOVERY",
                      color: previewColor,
                      fontSize: 12,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _applySleepRecovery(tempHours, alreadyClaimedToday);
                      },
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

    if (!alreadyClaimedToday) {
      if (tier == 'well_rested') {
        await _grantAttributeXp('VIT', 8);
        await _grantAttributeXp('PER', 6);
      } else if (tier == 'standard') {
        await _grantAttributeXp('VIT', 3);
        await _grantAttributeXp('PER', 2);
      }
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

    final res = await db.query(
      'surge_quests',
      where: 'status = ? AND expire_epoch > ?',
      whereArgs: ['pending', nowEpoch],
      orderBy: 'expire_epoch ASC',
      limit: 1,
    );

    setState(() {
      _activeSurgeQuest = res.isNotEmpty ? res.first : null;
    });
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
    final int offsetMins = rand.nextInt(max<int>(1, slotDuration - 35));
    final int triggerMinute = chosenSlot['start']! + offsetMins;

    final triggerTime = DateTime(now.year, now.month, now.day, triggerMinute ~/ 60, triggerMinute % 60);
    final expireTime = triggerTime.add(const Duration(minutes: 30));

    final template = microQuestPool[rand.nextInt(microQuestPool.length)];

    await db.insert('surge_quests', {
      'title': template['title'],
      'category': template['category'],
      'description': template['desc'],
      'base_rr': template['baseRr'],
      'start_epoch': triggerTime.millisecondsSinceEpoch,
      'expire_epoch': expireTime.millisecondsSinceEpoch,
      'status': 'pending',
      'is_gamble': 0,
    });
  }

  Future<void> _completeSurgeQuest(JsonMap surge) async {
    HapticFeedback.heavyImpact();
    final db = await database;
    final int base = surge['base_rr'] as int;

    await db.update('surge_quests', {'status': 'completed'}, where: 'id = ?', whereArgs: [surge['id']]);
    await _grantAttributeXp('VIT', 4);

    final profileRes = await db.query('user_profile', where: 'id = ?', whereArgs: [1]);
    final profile = profileRes.first;
    int oldRr = (profile['total_rr'] as int?) ?? 0;
    int maxRank = (profile['highest_rank_level'] as int?) ?? 0;

    final newRr = oldRr + base;
    final oldRankIdx = SystemRanks.getRankIndex(oldRr);
    final newRankIdx = SystemRanks.getRankIndex(newRr);
    maxRank = max(maxRank, newRankIdx);

    await db.update('user_profile', {'total_rr': newRr, 'highest_rank_level': maxRank}, where: 'id = ?', whereArgs: [1]);

    setState(() => _activeSurgeQuest = null);

    if (newRankIdx > oldRankIdx) {
      _triggerRankAscensionCeremony(oldRankIdx, newRankIdx);
    }

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

      final endDt = DateTime(now.year, now.month, now.day, task['end_hour'] as int, task['end_minute'] as int).add(const Duration(minutes: 15));

      if (now.isAfter(endDt) && !isCompleted && penaltyAppliedDate != todayStr) {
        penalizedCount++;
        final int penalty = _getStandardPenalty(task);
        rr = max<int>(0, rr - penalty);

        await db.update('tasks', {'penalty_applied_date': todayStr}, where: 'id = ?', whereArgs: [taskId]);
      }
    }

    if (penalizedCount > 0) {
      await db.update('user_profile', {'total_rr': rr, 'perfect_streak': 0}, where: 'id = ?', whereArgs: [1]);
      perfectStreak = 0;
      totalRr = rr;
      setState(() {});
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
  }

  void _triggerRankAscensionCeremony(int oldRankIdx, int newRankIdx) {
    HapticFeedback.vibrate();
    final newRankName = SystemRanks.rankLadder[newRankIdx]['name'] as String;
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      pageBuilder: (dialogCtx, anim1, anim2) {
        return RankAscensionDialog(
          newRankName: newRankName,
          onClaimed: () => Navigator.pop(dialogCtx),
        );
      },
    );
  }

  void _openRankDetailsScreen() {
    HapticFeedback.selectionClick();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RankHierarchyScreen(
          currentRr: totalRr,
          accentColor: accentColor,
        ),
      ),
    );
  }

  // Point 11: Granular repeating quest deletion and editing
  void _openQuestOptions(JsonMap task, [DateTime? forDate]) {
    final targetDate = forDate ?? _today;
    final String recurrenceType = (task['recurrence_type'] as String?) ?? 'weekly';
    final bool isRecurring = recurrenceType != 'once';
    final String dateStr = _formatDate(targetDate);
    final String dateLabel = dateStr == _formatDate(_today) ? "Today" : DateFormat('MMM d').format(targetDate);

    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: SystemTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(task['title'] as String, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.edit_outlined, color: SystemTheme.cyan),
                title: const Text("Edit Directive", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                subtitle: const Text("Modify time, location, or parameters", style: TextStyle(color: Color(0xFF7E92A8), fontSize: 12)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final res = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AddTaskScreen(
                        initialDate: targetDate,
                        skills: _skills,
                        accentColor: accentColor,
                        existingTask: task,
                      ),
                    ),
                  );
                  if (res == true) _startApp();
                },
              ),
              const Divider(color: SystemTheme.border),
              if (isRecurring) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.today, color: SystemTheme.monarchGold),
                  title: Text("Skip for $dateLabel Only", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  subtitle: const Text("Keep all upcoming and future days active", style: TextStyle(color: Color(0xFF7E92A8), fontSize: 12)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final db = await database;
                    final currentExcluded = (task['excluded_dates'] as String?) ?? '';
                    final list = currentExcluded.isEmpty ? <String>[] : currentExcluded.split(',');
                    if (!list.contains(dateStr)) list.add(dateStr);
                    await db.update('tasks', {'excluded_dates': list.join(',')}, where: 'id = ?', whereArgs: [task['id']]);
                    _startApp();
                  },
                ),
                const Divider(color: SystemTheme.border),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_busy, color: SystemTheme.dangerRed),
                  title: const Text("End Future Directives", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  subtitle: const Text("Cut recurrence timeline right before this day", style: TextStyle(color: Color(0xFF7E92A8), fontSize: 12)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final db = await database;
                    final yesterdayStr = _formatDate(targetDate.subtract(const Duration(days: 1)));
                    await db.update('tasks', {'recurrence_end_date': yesterdayStr}, where: 'id = ?', whereArgs: [task['id']]);
                    _startApp();
                  },
                ),
                const Divider(color: SystemTheme.border),
              ],
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_forever, color: SystemTheme.dangerRed),
                title: const Text("Purge Completely", style: TextStyle(color: SystemTheme.dangerRed, fontWeight: FontWeight.w700)),
                subtitle: const Text("Erase this directive and all history from memory", style: TextStyle(color: Color(0xFF7E92A8), fontSize: 12)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final db = await database;
                  await db.delete('tasks', where: 'id = ?', whereArgs: [task['id']]);
                  _startApp();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _attemptCheckIn(JsonMap task) async {
    final now = DateTime.now();
    final startTime = DateTime(now.year, now.month, now.day, task['start_hour'] as int, task['start_minute'] as int).subtract(const Duration(minutes: 15));
    final endTime = DateTime(now.year, now.month, now.day, task['end_hour'] as int, task['end_minute'] as int).add(const Duration(minutes: 15));

    if (now.isBefore(startTime) || now.isAfter(endTime)) {
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Window locked. Available ±15m of scheduled time.')),
      );
      return;
    }

    final int requireGps = (task['require_gps'] as int?) ?? 1;
    if (requireGps == 1) {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
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
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GPS distance mismatch: ${distanceMeters.toStringAsFixed(0)}m (Max: ${allowedRadius.toInt()}m)')),
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
      backgroundColor: SystemTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("BOSS GATE CHALLENGE", style: TextStyle(color: SystemTheme.shadowViolet, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
              const SizedBox(height: 8),
              Text(task['title'] as String, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: SystemButton(
                  label: "VICTORY (+$victoryGain RR)",
                  color: SystemTheme.cyan,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _finalizeBossEncounter(task, true, victoryGain);
                  },
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SystemButton(
                  label: "DEFEAT (-$defeatLoss RR)",
                  color: SystemTheme.dangerRed,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _finalizeBossEncounter(task, false, defeatLoss);
                  },
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

    await db.update('tasks', {'last_completed_date': todayStr, 'is_completed': 1, 'prep_stacks': 0}, where: 'id = ?', whereArgs: [task['id']]);

    final String pStat = (task['primary_stat'] as String?) ?? 'INT';
    final String sStat = (task['secondary_stat'] as String?) ?? 'PER';

    if (succeeded) {
      await _grantAttributeXp(pStat, 16);
      await _grantAttributeXp(sStat, 8);
    }

    final profileRes = await db.query('user_profile', where: 'id = ?', whereArgs: [1]);
    final profile = profileRes.first;
    int oldRr = (profile['total_rr'] as int?) ?? 0;
    int maxRank = (profile['highest_rank_level'] as int?) ?? 0;

    final int newRr = succeeded ? (oldRr + rrDelta) : max<int>(0, oldRr - rrDelta);
    final int oldRankIdx = SystemRanks.getRankIndex(oldRr);
    final int newRankIdx = SystemRanks.getRankIndex(newRr);
    maxRank = max(maxRank, newRankIdx);

    await db.update('user_profile', {'total_rr': newRr, 'highest_rank_level': maxRank}, where: 'id = ?', whereArgs: [1]);

    if (newRankIdx > oldRankIdx) {
      _triggerRankAscensionCeremony(oldRankIdx, newRankIdx);
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
      backgroundColor: SystemTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("LOG OPERATIONAL INTENSITY", style: TextStyle(color: SystemTheme.cyan, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
              const SizedBox(height: 6),
              Text(task['title'] as String, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              _buildEffortOption("LIGHT", 4, 2, (_getBaseReward(category, 'Low') * mult).round(), pStat, sStat, SystemTheme.cyan, () {
                Navigator.pop(ctx);
                _finalizeCheckIn(task, 'Low');
              }),
              const SizedBox(height: 8),
              _buildEffortOption("OPTIMAL", 8, 4, (_getBaseReward(category, 'Medium') * mult).round(), pStat, sStat, SystemTheme.electricBlue, () {
                Navigator.pop(ctx);
                _finalizeCheckIn(task, 'Medium');
              }),
              const SizedBox(height: 8),
              _buildEffortOption("PEAK", 14, 7, (_getBaseReward(category, 'High') * mult).round(), pStat, sStat, SystemTheme.monarchGold, () {
                Navigator.pop(ctx);
                _finalizeCheckIn(task, 'High');
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEffortOption(String label, int pXp, int sXp, int rr, String pStat, String sStat, Color col, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: SystemTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: col.withValues(alpha: 0.5), width: 1.0),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: col, fontWeight: FontWeight.w900, fontSize: 13)),
                Text("+$pXp $pStat / +$sXp $sStat", style: const TextStyle(color: Color(0xFF7E92A8), fontSize: 11)),
              ],
            ),
            Text("+$rr RR", style: TextStyle(color: col, fontWeight: FontWeight.w900, fontSize: 14)),
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

    await db.update('tasks', {'last_completed_date': todayStr, 'is_completed': 1}, where: 'id = ?', whereArgs: [task['id']]);
    await _grantAttributeXp(pStat, pXp);
    await _grantAttributeXp(sStat, sXp);

    if (skill != null) {
      final int oldSkillXp = (skill['mastery_xp'] as int?) ?? 0;
      await db.update('skills', {'mastery_xp': oldSkillXp + skillXpGain}, where: 'id = ?', whereArgs: [skillId]);
    }

    final profileRes = await db.query('user_profile', where: 'id = ?', whereArgs: [1]);
    final profile = profileRes.first;
    int oldRr = (profile['total_rr'] as int?) ?? 0;
    int maxRank = (profile['highest_rank_level'] as int?) ?? 0;
    int streak = (profile['current_streak'] as int?) ?? 0;

    final newRr = oldRr + earnedRr;
    final oldRankIdx = SystemRanks.getRankIndex(oldRr);
    final newRankIdx = SystemRanks.getRankIndex(newRr);
    maxRank = max(maxRank, newRankIdx);

    await db.update('user_profile', {
      'current_streak': streak + 1,
      'total_rr': newRr,
      'highest_rank_level': maxRank,
      'last_completed_date': todayStr,
    }, where: 'id = ?', whereArgs: [1]);

    if (newRankIdx > oldRankIdx) {
      _triggerRankAscensionCeremony(oldRankIdx, newRankIdx);
    }

    _startApp();
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
    if (result == true) _startApp();
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

  Future<void> _deleteSkillCategory(String category) async {
    HapticFeedback.mediumImpact();
    setState(() {
      _skillCategories.remove(category);
      _expandedSkillCategories.remove(category);
    });
    final db = await database;
    await db.delete('skills', where: 'category = ?', whereArgs: [category]);
    await db.update(
      'user_profile',
      {'custom_categories': _skillCategories.join(',')},
      where: 'id = ?',
      whereArgs: [1],
    );
    _startApp();
  }

  void _showAddCategoryDialog() {
    HapticFeedback.selectionClick();
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SystemTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: SystemTheme.border)),
        title: const Text("NEW SKILL CATEGORY", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: "e.g. Boxing, Languages, Career",
            hintStyle: const TextStyle(color: Color(0xFF7E92A8), fontSize: 13),
            filled: true,
            fillColor: SystemTheme.surfaceElevated,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white38)),
          ),
          SystemButton(
            label: "ADD CATEGORY",
            color: accentColor,
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                await _addCustomSkillCategory(name);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  void _showEditSkillModal(JsonMap skill) {
    HapticFeedback.selectionClick();
    final nameCtrl = TextEditingController(text: skill['name'] as String);
    final xpCtrl = TextEditingController(text: (skill['mastery_xp'] as int).toString());
    String selectedCat = skill['category'] as String;
    String pStat = skill['primary_stat'] as String;
    String sStat = skill['secondary_stat'] as String;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: SystemTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("EDIT SKILL", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: SystemTheme.dangerRed, size: 22),
                        onPressed: () async {
                          final db = await database;
                          await db.delete('skills', where: 'id = ?', whereArgs: [skill['id']]);
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          _startApp();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      labelText: "Skill Name",
                      labelStyle: const TextStyle(color: Color(0xFF7E92A8), fontSize: 12),
                      filled: true,
                      fillColor: SystemTheme.surfaceElevated,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: xpCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      labelText: "Mastery XP",
                      labelStyle: const TextStyle(color: Color(0xFF7E92A8), fontSize: 12),
                      filled: true,
                      fillColor: SystemTheme.surfaceElevated,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButton<String>(
                          value: pStat,
                          dropdownColor: SystemTheme.surface,
                          isExpanded: true,
                          style: TextStyle(color: accentColor, fontWeight: FontWeight.w900),
                          items: ['STR', 'VIT', 'INT', 'PER', 'AGI'].map((s) => DropdownMenuItem(value: s, child: Text("1°: $s"))).toList(),
                          onChanged: (v) => setModalState(() => pStat = v!),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: DropdownButton<String>(
                          value: sStat,
                          dropdownColor: SystemTheme.surface,
                          isExpanded: true,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                          items: ['STR', 'VIT', 'INT', 'PER', 'AGI'].map((s) => DropdownMenuItem(value: s, child: Text("2°: $s"))).toList(),
                          onChanged: (v) => setModalState(() => sStat = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: SystemButton(
                      label: "SAVE SKILL CHANGES",
                      color: accentColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      onPressed: () async {
                        final name = nameCtrl.text.trim();
                        final int xp = int.tryParse(xpCtrl.text.trim()) ?? (skill['mastery_xp'] as int);
                        if (name.isEmpty) return;
                        final db = await database;
                        await db.update('skills', {
                          'name': name,
                          'category': selectedCat,
                          'primary_stat': pStat,
                          'secondary_stat': sStat,
                          'mastery_xp': xp,
                        }, where: 'id = ?', whereArgs: [skill['id']]);
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        _startApp();
                      },
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
      backgroundColor: SystemTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("OBTAIN SKILL", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      labelText: "Skill Name (e.g. Kickboxing, Accounting)",
                      labelStyle: const TextStyle(color: Color(0xFF7E92A8), fontSize: 12),
                      filled: true,
                      fillColor: SystemTheme.surfaceElevated,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("CATEGORY", style: TextStyle(color: Color(0xFF7E92A8), fontSize: 11, fontWeight: FontWeight.w800)),
                      TextButton(
                        onPressed: () => setModalState(() => addingNewCat = !addingNewCat),
                        child: Text(addingNewCat ? "Existing" : "+ New", style: TextStyle(color: accentColor, fontSize: 11)),
                      ),
                    ],
                  ),
                  if (addingNewCat)
                    TextField(
                      controller: customCatCtrl,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        hintText: "Category name...",
                        hintStyle: const TextStyle(color: Color(0xFF7E92A8), fontSize: 12),
                        filled: true,
                        fillColor: SystemTheme.surfaceElevated,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _skillCategories.map((cat) {
                        final isSel = selectedCat == cat;
                        return ChoiceChip(
                          label: Text(cat),
                          selected: isSel,
                          showCheckmark: false,
                          selectedColor: accentColor.withValues(alpha: 0.16),
                          backgroundColor: SystemTheme.surfaceElevated,
                          side: BorderSide(color: isSel ? accentColor : SystemTheme.border, width: 1.0),
                          labelStyle: TextStyle(color: isSel ? accentColor : Colors.white70, fontSize: 11, fontWeight: FontWeight.w700),
                          onSelected: (_) => setModalState(() => selectedCat = cat),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButton<String>(
                          value: pStat,
                          dropdownColor: SystemTheme.surface,
                          isExpanded: true,
                          style: TextStyle(color: accentColor, fontWeight: FontWeight.w900),
                          items: ['STR', 'VIT', 'INT', 'PER', 'AGI'].map((s) => DropdownMenuItem(value: s, child: Text("1°: $s"))).toList(),
                          onChanged: (v) => setModalState(() => pStat = v!),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: DropdownButton<String>(
                          value: sStat,
                          dropdownColor: SystemTheme.surface,
                          isExpanded: true,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                          items: ['STR', 'VIT', 'INT', 'PER', 'AGI'].map((s) => DropdownMenuItem(value: s, child: Text("2°: $s"))).toList(),
                          onChanged: (v) => setModalState(() => sStat = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: SystemButton(
                      label: "OBTAIN SKILL",
                      color: accentColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
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

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Backup JSON copied to clipboard.')),
    );
  }

  Future<void> _importProfileDataPrompt() async {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SystemTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: SystemTheme.border)),
        title: const Text("RESTORE SYSTEM DATA", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
        content: TextField(
          controller: textController,
          maxLines: 4,
          style: const TextStyle(color: Colors.white, fontSize: 11),
          decoration: InputDecoration(
            hintText: 'Paste backup JSON payload here...',
            hintStyle: const TextStyle(color: Color(0xFF7E92A8), fontSize: 11),
            filled: true,
            fillColor: SystemTheme.surfaceElevated,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL", style: TextStyle(color: Colors.white38))),
          SystemButton(
            label: "RESTORE",
            color: accentColor,
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
                    'ui_color_override': p['ui_color_override'] ?? 0xFF00E5FF,
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
                _startApp();
              } catch (_) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Invalid backup payload.')));
              }
            },
          ),
        ],
      ),
    );
  }

  void _promptFactoryReset() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SystemTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: SystemTheme.dangerRed)),
        title: const Text("ERASE ALL SYSTEM DATA?", style: TextStyle(color: SystemTheme.dangerRed, fontSize: 14, fontWeight: FontWeight.w900)),
        content: const Text(
          "This will reset your rank, rating, attributes, streaks, history, custom disciplines, and directives back to absolute zero. This action is irreversible.",
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
          ),
          SystemButton(
            label: "YES, WIPE EVERYTHING",
            color: SystemTheme.dangerRed,
            onPressed: () async {
              Navigator.pop(ctx);
              await _executeFactoryReset();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _executeFactoryReset() async {
    HapticFeedback.heavyImpact();
    final db = await database;

    // 1. Delete all directive, skill, and surge tables
    await db.delete('tasks');
    await db.delete('skills');
    await db.delete('surge_quests');

    // 2. Explicitly wipe profile records and zero all XP columns
    await db.delete('user_profile');
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
      'ui_color_override': _uiColorOverride,
      'emblem_color_override': -1,
      'str_xp': 0,
      'vit_xp': 0,
      'int_xp': 0,
      'per_xp': 0,
      'agi_xp': 0,
      'sleep_hours': 7.5,
      'sleep_tier': 'well_rested',
      'sleep_logged_date': '',
      'custom_categories': '',
    });

    // 3. Immediately reset all in-memory state variables
    setState(() {
      currentStreak = 0;
      highestStreak = 0;
      perfectStreak = 0;
      highestPerfectStreak = 0;
      shieldCharges = 0;
      totalRr = 0;
      highestRankIdx = 0;
      strXp = 0;
      vitXp = 0;
      intXp = 0;
      perXp = 0;
      agiXp = 0;
      _allTasks = [];
      _todayTasks = [];
      _calendarDayTasks = [];
      _skills = [];
      _skillCategories = [];
      _expandedSkillCategories.clear();
      _activeSurgeQuest = null;
    });

    // 4. Refresh task and calendar filtering
    _filterTasks();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All system records and attribute XP reset to zero.')),
    );
  }

  void _openSettingsScreen() {
    HapticFeedback.selectionClick();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          accentColor: accentColor,
          initialUiColorOverride: _uiColorOverride,
          onColorChanged: (c) {
            _setAccentColor(c);
          },
          onExport: _exportProfileData,
          onRestore: _importProfileDataPrompt,
          onReset: _promptFactoryReset,
        ),
      ),
    );
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
      backgroundColor: SystemTheme.background,
      body: SafeArea(child: currentBody),
      bottomNavigationBar: _buildModernDock(accent),
    );
  }

  Widget _buildModernDock(Color accent) {
    return Container(
      height: 70,
      decoration: const BoxDecoration(
        color: SystemTheme.surface,
        border: Border(top: BorderSide(color: SystemTheme.border, width: 1.0)),
      ),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Row(
            children: [
              _dockItem(0, Icons.shield_outlined, Icons.shield, 'STATUS', accent),
              _dockItem(1, Icons.calendar_month_outlined, Icons.calendar_month, 'CALENDAR', accent),
              const SizedBox(width: 60),
              _dockItem(2, Icons.auto_awesome_outlined, Icons.auto_awesome, 'STATS', accent),
              _dockItem(3, Icons.person_outline, Icons.person, 'PROFILE', accent),
            ],
          ),
          Positioned(
            top: -14,
            child: GestureDetector(
              onTap: _openAddTaskScreen,
              child: Transform.rotate(
                angle: pi / 4,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.45),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Transform.rotate(
                      angle: -pi / 4,
                      child: const Icon(Icons.add, color: Color(0xFF070A0F), size: 28),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dockItem(int idx, IconData icon, IconData activeIcon, String label, Color accent) {
    final isSel = _selectedTabIndex == idx;
    return Expanded(
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedTabIndex = idx);
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isSel ? activeIcon : icon, color: isSel ? accent : Colors.white38, size: 22),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: isSel ? accent : Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // TAB 0: STATUS
  // ============================================================================
  Widget _buildTodayTab() {
    final accent = accentColor;
    final int rankIdx = SystemRanks.getRankIndex(totalRr);
    final String rankName = SystemRanks.rankLadder[rankIdx]['name'] as String;
    final int curMinRr = SystemRanks.rankLadder[rankIdx]['minRr'] as int;
    final int nextMinRr = rankIdx < SystemRanks.rankLadder.length - 1
        ? (SystemRanks.rankLadder[rankIdx + 1]['minRr'] as int)
        : curMinRr + 10000;
    final double progress = ((totalRr - curMinRr) / max(1, nextMinRr - curMinRr)).clamp(0.0, 1.0);
    final int completedCount = _todayTasks.where((t) => t['last_completed_date'] == _formatDate(_today)).length;
    final double streakMult = _getPerfectStreakMultiplier(perfectStreak);

    final visibleTasks = _selectedCategoryFilter == 'All'
        ? _todayTasks
        : _todayTasks.where((t) => (t['category'] as String).toLowerCase() == _selectedCategoryFilter.toLowerCase()).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SystemCard(
            borderColor: accent.withValues(alpha: 0.5),
            onTap: _openRankDetailsScreen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: accent, width: 1.0),
                          ),
                          child: Text(
                            rankName.toUpperCase(),
                            style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 12),
                      ],
                    ),
                    Text(
                      "${NumberFormat('#,###').format(totalRr)} RR",
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SystemGauge(value: progress, color: accent, height: 6),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Directives: $completedCount / ${_todayTasks.length}", style: const TextStyle(color: Color(0xFF7E92A8), fontSize: 11, fontWeight: FontWeight.w600)),
                    Text(
                      rankIdx < SystemRanks.rankLadder.length - 1 ? "${nextMinRr - totalRr} RR to Next Tier" : "APEX REACHED",
                      style: const TextStyle(color: Color(0xFF7E92A8), fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const Divider(color: SystemTheme.border, height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _telemetryPill("STREAK", "$currentStreak d"),
                    _telemetryPill("MULT", "${streakMult.toStringAsFixed(2)}x"),
                    _telemetryPill("SHIELD", "$shieldCharges/3"),
                    _telemetryPill("SLEEP", sleepShortLabel),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (_activeSurgeQuest != null) ...[
            _buildSurgeCard(_activeSurgeQuest!),
            const SizedBox(height: 16),
          ],

          const Text("TODAY'S DIRECTIVES", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
          const SizedBox(height: 8),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['All', 'Academic', 'Fitness', 'General'].map((cat) {
                final isSelected = _selectedCategoryFilter == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _selectedCategoryFilter = cat),
                    selectedColor: accent.withValues(alpha: 0.16),
                    backgroundColor: SystemTheme.surface,
                    side: BorderSide(color: isSelected ? accent : SystemTheme.border),
                    labelStyle: TextStyle(color: isSelected ? accent : Colors.white70, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          if (visibleTasks.isEmpty)
            SystemCard(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Text(
                    "No directives logged for today.\nTap '+' below to add your schedule.",
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white38, fontSize: 13, height: 1.4),
                  ),
                ),
              ),
            )
          else
            ...visibleTasks.map((t) => _buildDirectiveCard(t, accent)),

          const SizedBox(height: 70),
        ],
      ),
    );
  }

  Widget _telemetryPill(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF7E92A8), fontSize: 10, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
      ],
    );
  }

  Widget _buildSurgeCard(JsonMap surge) {
    final int base = surge['base_rr'] as int;
    return SystemCard(
      borderColor: SystemTheme.shadowViolet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt, color: SystemTheme.shadowViolet, size: 18),
              const SizedBox(width: 6),
              const Text("EMERGENCY SURGE DIRECTIVE", style: TextStyle(color: SystemTheme.shadowViolet, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
            ],
          ),
          const SizedBox(height: 8),
          Text(surge['title'] as String, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          SystemButton(
            label: "EXECUTE SURGE (+$base RR)",
            color: SystemTheme.shadowViolet,
            onPressed: () => _completeSurgeQuest(surge),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectiveCard(JsonMap task, Color accent) {
    final todayStr = _formatDate(_today);
    final bool isCompleted = task['last_completed_date'] == todayStr;
    final int isBoss = (task['is_boss'] as int?) ?? 0;
    final double targetLat = (task['target_lat'] as num?)?.toDouble() ?? 0.0;
    final double targetLng = (task['target_lng'] as num?)?.toDouble() ?? 0.0;
    final bool hasLocation = targetLat != 0.0 || targetLng != 0.0;
    final String pStat = (task['primary_stat'] as String?) ?? 'INT';
    final String sStat = (task['secondary_stat'] as String?) ?? 'PER';
    final String timeStr = "${task['start_hour'].toString().padLeft(2, '0')}:${task['start_minute'].toString().padLeft(2, '0')} - ${task['end_hour'].toString().padLeft(2, '0')}:${task['end_minute'].toString().padLeft(2, '0')}";

    final Color statusColor = isCompleted
        ? SystemTheme.clearGreen
        : (isBoss == 1 ? SystemTheme.shadowViolet : SystemTheme.cyan);

    return InkWell(
      onTap: () => _openQuestOptions(task),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SystemTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isCompleted ? SystemTheme.clearGreen.withValues(alpha: 0.35) : statusColor.withValues(alpha: 0.5),
            width: 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(timeStr, style: const TextStyle(color: Color(0xFF7E92A8), fontSize: 11, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text(
                        task['title'] as String,
                        style: TextStyle(
                          color: isCompleted ? Colors.white38 : Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          decoration: isCompleted ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isBoss == 1 ? "GATE CHALLENGE · ±${task['boss_stake']} RR" : "+$pStat / +$sStat",
                        style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SystemButton(
                  label: isCompleted ? "CLEARED" : (isBoss == 1 ? "ENGAGE" : "CHECK IN"),
                  color: isCompleted ? SystemTheme.clearGreen : statusColor,
                  onPressed: isCompleted ? null : () => _attemptCheckIn(task),
                ),
              ],
            ),
            if (hasLocation) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () => _openGoogleMapsDirections(targetLat, targetLng),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: SystemTheme.cyan.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: SystemTheme.cyan.withValues(alpha: 0.4), width: 0.8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.directions_outlined, color: SystemTheme.cyan, size: 14),
                      SizedBox(width: 4),
                      Text("DIRECTIONS", style: TextStyle(color: SystemTheme.cyan, fontSize: 10, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // TAB 1: CALENDAR
  // ============================================================================
  Widget _buildCalendarTab() {
    final accent = accentColor;
    final int year = _calendarMonthCursor.year;
    final int month = _calendarMonthCursor.month;
    final int daysInMonth = DateTime(year, month + 1, 0).day;
    final int firstWeekdayOffset = DateTime(year, month, 1).weekday - 1;
    final todayStr = _formatDate(_today);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SystemCard(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, color: Colors.white, size: 22),
                      onPressed: () => setState(() => _calendarMonthCursor = DateTime(year, month - 1, 1)),
                    ),
                    Text(
                      DateFormat('MMMM yyyy').format(_calendarMonthCursor).toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, color: Colors.white, size: 22),
                      onPressed: () => setState(() => _calendarMonthCursor = DateTime(year, month + 1, 1)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'].map((d) {
                    return SizedBox(
                      width: 36,
                      child: Text(
                        d,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF7E92A8), fontSize: 10, fontWeight: FontWeight.w800),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 1.1),
                  itemCount: firstWeekdayOffset + daysInMonth,
                  itemBuilder: (context, idx) {
                    if (idx < firstWeekdayOffset) return const SizedBox.shrink();
                    final int dayNum = idx - firstWeekdayOffset + 1;
                    final DateTime cellDate = DateTime(year, month, dayNum);
                    final String cellStr = _formatDate(cellDate);
                    final bool isSelected = _formatDate(_selectedCalendarDate) == cellStr;
                    final bool isToday = cellStr == todayStr;

                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _selectedCalendarDate = cellDate;
                          _filterTasks();
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: isSelected ? accent.withValues(alpha: 0.22) : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSelected
                                ? accent
                                : (isToday ? SystemTheme.monarchGold : SystemTheme.borderSubtle),
                            width: isToday || isSelected ? 1.5 : 0.8,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            "$dayNum",
                            style: TextStyle(
                              color: isSelected
                                  ? accent
                                  : (isToday ? SystemTheme.monarchGold : Colors.white70),
                              fontSize: 12,
                              fontWeight: isToday || isSelected ? FontWeight.w900 : FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "TIMETABLE · ${_formatDate(_selectedCalendarDate)}",
            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.8),
          ),
          const SizedBox(height: 10),
          _buildDayTimetable(accent),
          const SizedBox(height: 70),
        ],
      ),
    );
  }

  Widget _buildDayTimetable(Color accent) {
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
        blocks.add(_buildTimeSlotCard(
          start: _formatMinutes(cursor),
          end: _formatMinutes(taskStart),
          title: "Available Buffer",
          isFree: true,
          status: 'none',
        ));
      }

      final bool isCompleted = task['last_completed_date'] == selectedDateStr;
      bool isMissed = false;

      if (!isCompleted) {
        if (selectedDayOnly.isBefore(todayDayOnly)) {
          isMissed = true;
        } else if (selectedDayOnly.isAtSameMomentAs(todayDayOnly)) {
          final endDt = DateTime(now.year, now.month, now.day, task['end_hour'] as int, task['end_minute'] as int).add(const Duration(minutes: 15));
          if (now.isAfter(endDt)) isMissed = true;
        }
      }

      final String status = isCompleted ? 'completed' : (isMissed ? 'missed' : 'upcoming');

      blocks.add(_buildTimeSlotCard(
        start: _formatMinutes(taskStart),
        end: _formatMinutes(taskEnd),
        title: task['title'] as String,
        isFree: false,
        status: status,
        isBoss: (task['is_boss'] as int? ?? 0) == 1,
        onTap: () => _openQuestOptions(task, _selectedCalendarDate),
      ));

      cursor = max(cursor, taskEnd);
    }

    if (cursor < dayEnd) {
      blocks.add(_buildTimeSlotCard(
        start: _formatMinutes(cursor),
        end: _formatMinutes(dayEnd),
        title: "Available Buffer",
        isFree: true,
        status: 'none',
      ));
    }

    return Column(children: blocks);
  }

  Widget _buildTimeSlotCard({
    required String start,
    required String end,
    required String title,
    required bool isFree,
    required String status,
    bool isBoss = false,
    VoidCallback? onTap,
  }) {
    if (isFree) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            SizedBox(
              width: 86,
              child: Text("$start - $end", style: const TextStyle(color: Colors.white24, fontSize: 10, fontFamily: 'monospace')),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: SystemTheme.surfaceElevated.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text("Free Period", style: TextStyle(color: Colors.white24, fontSize: 11)),
              ),
            ),
          ],
        ),
      );
    }

    Color borderCol = SystemTheme.border;
    Color tagCol = SystemTheme.cyan;
    if (status == 'completed') {
      borderCol = SystemTheme.clearGreen;
      tagCol = SystemTheme.clearGreen;
    } else if (status == 'missed') {
      borderCol = SystemTheme.dangerRed;
      tagCol = SystemTheme.dangerRed;
    } else if (isBoss) {
      borderCol = SystemTheme.shadowViolet;
      tagCol = SystemTheme.shadowViolet;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            child: Text("$start - $end", style: TextStyle(color: tagCol, fontSize: 10, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
          ),
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: SystemTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: borderCol.withValues(alpha: 0.6), width: 1.0),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        isBoss ? "👑 $title" : title,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      status.toUpperCase(),
                      style: TextStyle(color: tagCol, fontSize: 10, fontWeight: FontWeight.w900),
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

  // ============================================================================
  // TAB 2: ATTRIBUTES
  // ============================================================================
  Widget _buildSkillsTab() {
    final accent = accentColor;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SystemCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("ATTRIBUTES", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                const SizedBox(height: 10),
                SizedBox(
                  height: 190,
                  child: CustomPaint(
                    size: const Size(double.infinity, 190),
                    painter: AttributeRadarPainter(
                      strLv: (strXp ~/ 100) + 1,
                      vitLv: (vitXp ~/ 100) + 1,
                      intLv: (intXp ~/ 100) + 1,
                      perLv: (perXp ~/ 100) + 1,
                      agiLv: (agiXp ~/ 100) + 1,
                      auraColor: accent,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _statRowWithGauge("STR · Strength", strXp, SystemTheme.dangerRed),
                _statRowWithGauge("VIT · Vitality", vitXp, SystemTheme.cyan),
                _statRowWithGauge("INT · Intellect", intXp, SystemTheme.electricBlue),
                _statRowWithGauge("PER · Perception", perXp, SystemTheme.monarchGold),
                _statRowWithGauge("AGI · Agility", agiXp, SystemTheme.shadowViolet),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("SKILLS & DISCIPLINES", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
              Row(
                children: [
                  SystemButton(
                    label: "+ CATEGORY",
                    color: SystemTheme.shadowViolet,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    fontSize: 9,
                    onPressed: _showAddCategoryDialog,
                  ),
                  const SizedBox(width: 6),
                  SystemButton(
                    label: "+ SKILL",
                    color: accent,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    fontSize: 9,
                    onPressed: _showCreateSkillModal,
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
            final int flooredRank = avgNumeric.floor().clamp(1, 6);
            final String catLetter = catSkills.isEmpty ? 'E' : SystemRanks.numericToLetter(flooredRank);
            final Color catBadgeColor = SystemRanks.getLetterColor(catLetter, accent);
            final bool isExpanded = _expandedSkillCategories.contains(cat);

            return SystemCard(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      InkWell(
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
                        child: Row(
                          children: [
                            Icon(isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, color: Colors.white70, size: 20),
                            const SizedBox(width: 4),
                            Text(cat.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: catBadgeColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: catBadgeColor, width: 0.8),
                            ),
                            child: Text(
                              "$catLetter-RANK",
                              style: TextStyle(color: catBadgeColor, fontWeight: FontWeight.w900, fontSize: 10),
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, color: Colors.white38, size: 18),
                            color: SystemTheme.surfaceElevated,
                            onSelected: (val) {
                              if (val == 'delete') _deleteSkillCategory(cat);
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text("Delete Category", style: TextStyle(color: SystemTheme.dangerRed, fontSize: 12)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (isExpanded) ...[
                    const SizedBox(height: 8),
                    if (catSkills.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text("No skills logged under this category.", style: TextStyle(color: Colors.white38, fontSize: 12)),
                      )
                    else
                      ...catSkills.map((skill) {
                        final int xp = (skill['mastery_xp'] as int?) ?? 0;
                        final String letter = SystemRanks.getSkillRankLetter(xp);
                        final Color sColor = SystemRanks.getLetterColor(letter, accent);
                        final int prevT = SystemRanks.getPrevSkillThreshold(xp);
                        final int nextT = SystemRanks.getNextSkillThreshold(xp);
                        final double frac = ((xp - prevT) / max(1, nextT - prevT)).clamp(0.0, 1.0);

                        return InkWell(
                          onTap: () => _showEditSkillModal(skill),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: SystemTheme.surfaceElevated,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: SystemTheme.border, width: 0.8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(skill['name'] as String, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                                    Text("$letter-Rank", style: TextStyle(color: sColor, fontWeight: FontWeight.w900, fontSize: 12)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                SystemGauge(value: frac, color: sColor, height: 5),
                                const SizedBox(height: 5),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text("+${skill['primary_stat']} / +${skill['secondary_stat']}", style: const TextStyle(color: Color(0xFF7E92A8), fontSize: 10, fontWeight: FontWeight.w600)),
                                    Text("$xp / $nextT XP (Tap to edit)", style: const TextStyle(color: Color(0xFF7E92A8), fontSize: 10, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                ],
              ),
            );
          }),

          const SizedBox(height: 70),
        ],
      ),
    );
  }

  Widget _statRowWithGauge(String lbl, int xp, Color c) {
    final int lv = (xp ~/ 100) + 1;
    final int modXp = xp % 100;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(lbl, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              Text("Lv.$lv ($modXp/100 XP)", style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 4),
          SystemGauge(value: modXp / 100.0, color: c, height: 5),
        ],
      ),
    );
  }

  // ============================================================================
  // TAB 3: PROFILE
  // ============================================================================
  Widget _buildProfileTab() {
    final accent = accentColor;
    final int currentRankIdx = SystemRanks.getRankIndex(totalRr);
    final String currentRankName = SystemRanks.rankLadder[currentRankIdx]['name'] as String;
    final double mult = _getPerfectStreakMultiplier(perfectStreak) * sleepRrMultiplier;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("HUNTER DOSSIER", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
              IconButton(
                icon: const Icon(Icons.settings, color: Colors.white70, size: 22),
                onPressed: _openSettingsScreen,
              ),
            ],
          ),
          const SizedBox(height: 8),

          SystemCard(
            borderColor: accent.withValues(alpha: 0.5),
            onTap: _openRankDetailsScreen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      currentRankName.toUpperCase(),
                      style: TextStyle(color: accent, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.0),
                    ),
                    const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 14),
                  ],
                ),
                Text(
                  "OVERALL RATING: ${NumberFormat('#,###').format(totalRr)} RR",
                  style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    _profileMetricBox("CURRENT STREAK", "$currentStreak d"),
                    const SizedBox(width: 8),
                    _profileMetricBox("BEST STREAK", "$highestStreak d"),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _profileMetricBox("PERFECT STREAK", "$perfectStreak d"),
                    const SizedBox(width: 8),
                    _profileMetricBox("BEST PERFECT", "$highestPerfectStreak d"),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _profileMetricBox("SHIELDS", "$shieldCharges / 3"),
                    const SizedBox(width: 8),
                    _profileMetricBox("MULT", "${mult.toStringAsFixed(2)}x"),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          SystemCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("SLEEP PROTOCOL", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      "${_formatSleepTime(sleepHours)} · $sleepTierLabel",
                      style: TextStyle(color: sleepTierColor, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                SystemButton(
                  label: "LOG / SYNC",
                  color: sleepTierColor,
                  onPressed: _showSleepSyncModal,
                ),
              ],
            ),
          ),

          const SizedBox(height: 70),
        ],
      ),
    );
  }

  Widget _profileMetricBox(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: SystemTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: SystemTheme.border, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Color(0xFF7E92A8), fontSize: 9, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// RANK HIERARCHY SCREEN
// ============================================================================
class RankHierarchyScreen extends StatelessWidget {
  final int currentRr;
  final Color accentColor;

  const RankHierarchyScreen({
    super.key,
    required this.currentRr,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final int currentRankIdx = SystemRanks.getRankIndex(currentRr);

    return Scaffold(
      backgroundColor: SystemTheme.background,
      appBar: AppBar(
        centerTitle: true,
        title: const Text("RANK HIERARCHY", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
        backgroundColor: SystemTheme.surface,
        elevation: 0,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: SystemRanks.rankLadder.length,
        itemBuilder: (context, idx) {
          final rank = SystemRanks.rankLadder[idx];
          final bool isCurrent = idx == currentRankIdx;
          final bool isUnlocked = idx <= currentRankIdx;
          final int minRr = rank['minRr'] as int;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isCurrent ? accentColor.withValues(alpha: 0.15) : SystemTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isCurrent ? accentColor : (isUnlocked ? SystemTheme.border : SystemTheme.borderSubtle),
                width: isCurrent ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isCurrent ? accentColor : SystemTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      rank['short'] as String,
                      style: TextStyle(
                        color: isCurrent ? const Color(0xFF070A0F) : (isUnlocked ? Colors.white : Colors.white24),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            rank['name'] as String,
                            style: TextStyle(
                              color: isCurrent ? accentColor : (isUnlocked ? Colors.white : Colors.white38),
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            "${NumberFormat('#,###').format(minRr)} RR",
                            style: TextStyle(
                              color: isCurrent ? accentColor : Colors.white60,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        rank['desc'] as String,
                        style: const TextStyle(color: Color(0xFF7E92A8), fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// SETTINGS SCREEN
// ============================================================================
class SettingsScreen extends StatefulWidget {
  final Color accentColor;
  final int initialUiColorOverride;
  final ValueChanged<int> onColorChanged;
  final VoidCallback onExport;
  final VoidCallback onRestore;
  final VoidCallback onReset;

  const SettingsScreen({
    super.key,
    required this.accentColor,
    required this.initialUiColorOverride,
    required this.onColorChanged,
    required this.onExport,
    required this.onRestore,
    required this.onReset,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int _currentColor;

  @override
  void initState() {
    super.initState();
    _currentColor = widget.initialUiColorOverride;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SystemTheme.background,
      appBar: AppBar(
        centerTitle: true,
        title: const Text("SYSTEM SETTINGS", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
        backgroundColor: SystemTheme.surface,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text("VISUAL THEME", style: TextStyle(color: Color(0xFF7E92A8), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          SystemCard(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: HabitApp.themePalette.map((item) {
                final Color c = item['color'] as Color;
                final bool isSel = _currentColor == c.toARGB32();
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _currentColor = c.toARGB32());
                    widget.onColorChanged(c.toARGB32());
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSel ? c.withValues(alpha: 0.2) : SystemTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: isSel ? c : SystemTheme.border, width: isSel ? 1.5 : 1.0),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text(item['name'] as String, style: TextStyle(color: isSel ? c : Colors.white70, fontSize: 11, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),

          const Text("DATA MANAGEMENT", style: TextStyle(color: Color(0xFF7E92A8), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          SystemCard(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.copy, color: SystemTheme.cyan),
                  title: const Text("Export Backup", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                  subtitle: const Text("Copy database state to clipboard", style: TextStyle(color: Color(0xFF7E92A8), fontSize: 11)),
                  onTap: widget.onExport,
                ),
                const Divider(color: SystemTheme.border),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.download, color: SystemTheme.electricBlue),
                  title: const Text("Restore Backup", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                  subtitle: const Text("Import JSON database snapshot", style: TextStyle(color: Color(0xFF7E92A8), fontSize: 11)),
                  onTap: widget.onRestore,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const Text("DANGER ZONE", style: TextStyle(color: SystemTheme.dangerRed, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          SystemCard(
            borderColor: SystemTheme.dangerRed.withValues(alpha: 0.6),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.warning, color: SystemTheme.dangerRed),
              title: const Text("Factory Reset System", style: TextStyle(color: SystemTheme.dangerRed, fontWeight: FontWeight.w800, fontSize: 14)),
              subtitle: const Text("Erase all stats, disciplines, ratings, and directives", style: TextStyle(color: Color(0xFF7E92A8), fontSize: 11)),
              onTap: widget.onReset,
            ),
          ),
        ],
      ),
    );
  }
}