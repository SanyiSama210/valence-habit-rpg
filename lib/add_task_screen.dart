import 'package:flutter/material.dart';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:path/path.dart' show join;
import 'package:sqflite/sqflite.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_application_1/rpg_system.dart';

class AddTaskScreen extends StatefulWidget {
  final DateTime? initialDate;
  final JsonList skills;
  final Color accentColor;
  final JsonMap? existingTask;

  const AddTaskScreen({
    super.key,
    this.initialDate,
    required this.skills,
    required this.accentColor,
    this.existingTask,
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
  int _customIntervalValue = 3;
  String _customIntervalUnit = 'days'; // days, weeks, months

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

    if (widget.existingTask != null) {
      final t = widget.existingTask!;
      _titleController.text = t['title'] as String? ?? '';
      _descriptionController.text = t['description'] as String? ?? '';
      _selectedCategory = t['category'] as String? ?? 'Academic';
      _primaryStat = t['primary_stat'] as String? ?? 'INT';
      _secondaryStat = t['secondary_stat'] as String? ?? 'PER';
      _selectedSkillId = t['skill_id'] as int? ?? -1;
      
      final rec = t['recurrence_type'] as String? ?? 'weekly';
      if (rec.startsWith('custom:')) {
        _recurrenceType = 'custom';
        final parts = rec.replaceFirst('custom:', '').split('_');
        if (parts.length == 2) {
          _customIntervalValue = int.tryParse(parts[0]) ?? 3;
          _customIntervalUnit = parts[1];
        }
      } else {
        _recurrenceType = rec;
      }

      _isBossEncounter = (t['is_boss'] as int? ?? 0) == 1;
      _bossStake = t['boss_stake'] as int? ?? 400;
      _requireGps = (t['require_gps'] as int? ?? 1) == 1;
      _radiusMeters = (t['radius_meters'] as num?)?.toDouble() ?? 150.0;
      startTime = TimeOfDay(hour: t['start_hour'] as int? ?? 8, minute: t['start_minute'] as int? ?? 0);
      endTime = TimeOfDay(hour: t['end_hour'] as int? ?? 10, minute: t['end_minute'] as int? ?? 0);
      final double lat = (t['target_lat'] as num?)?.toDouble() ?? 0.0;
      final double lng = (t['target_lng'] as num?)?.toDouble() ?? 0.0;
      if (lat != 0.0 && lng != 0.0) {
        _selectedLatLng = LatLng(lat, lng);
      }
      final String leadsStr = (t['notify_leads'] as String?) ?? '15';
      _selectedLeadTimes.clear();
      _selectedLeadTimes.addAll(
        leadsStr.split(',').map((e) => int.tryParse(e.trim())).whereType<int>(),
      );
      if (_selectedLeadTimes.isEmpty) _selectedLeadTimes.add(15);
      _notifyEnabled = (t['notify_enabled'] as int? ?? 1) == 1;
      _manualStatOverride = true;
    } else if (widget.initialDate != null) {
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

  void _showCustomRecurrenceDialog() {
    HapticFeedback.selectionClick();
    int tempValue = _customIntervalValue;
    String tempUnit = _customIntervalUnit;
    final ctrl = TextEditingController(text: tempValue.toString());

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            backgroundColor: SystemTheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: SystemTheme.border)),
            title: const Text("CUSTOM REPETITION INTERVAL", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Repeat every:", style: TextStyle(color: Color(0xFF7E92A8), fontSize: 12)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(
                      width: 70,
                      child: TextField(
                        controller: ctrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: SystemTheme.surfaceElevated,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        ),
                        onChanged: (val) {
                          tempValue = int.tryParse(val) ?? tempValue;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButton<String>(
                        value: tempUnit,
                        dropdownColor: SystemTheme.surfaceElevated,
                        isExpanded: true,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                        items: const [
                          DropdownMenuItem(value: 'days', child: Text("Days")),
                          DropdownMenuItem(value: 'weeks', child: Text("Weeks")),
                          DropdownMenuItem(value: 'months', child: Text("Months")),
                        ],
                        onChanged: (v) {
                          if (v != null) setDlgState(() => tempUnit = v);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL", style: TextStyle(color: Colors.white38))),
              SystemButton(
                label: "CONFIRM",
                color: widget.accentColor,
                onPressed: () {
                  setState(() {
                    _customIntervalValue = max(1, tempValue);
                    _customIntervalUnit = tempUnit;
                    _recurrenceType = 'custom';
                  });
                  Navigator.pop(ctx);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCustomLeadTimeDialog() {
    HapticFeedback.selectionClick();
    int tempValue = 3;
    String tempUnit = 'hours'; // minutes, hours, days, weeks
    final ctrl = TextEditingController(text: tempValue.toString());

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            backgroundColor: SystemTheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: SystemTheme.border)),
            title: const Text("CUSTOM NOTIFICATION TIMING", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Notify prior to commencement:", style: TextStyle(color: Color(0xFF7E92A8), fontSize: 12)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(
                      width: 70,
                      child: TextField(
                        controller: ctrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: SystemTheme.surfaceElevated,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        ),
                        onChanged: (val) {
                          tempValue = int.tryParse(val) ?? tempValue;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButton<String>(
                        value: tempUnit,
                        dropdownColor: SystemTheme.surfaceElevated,
                        isExpanded: true,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                        items: const [
                          DropdownMenuItem(value: 'minutes', child: Text("Minutes")),
                          DropdownMenuItem(value: 'hours', child: Text("Hours")),
                          DropdownMenuItem(value: 'days', child: Text("Days")),
                          DropdownMenuItem(value: 'weeks', child: Text("Weeks")),
                        ],
                        onChanged: (v) {
                          if (v != null) setDlgState(() => tempUnit = v);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL", style: TextStyle(color: Colors.white38))),
              SystemButton(
                label: "ADD REMINDER",
                color: widget.accentColor,
                onPressed: () {
                  int calculatedMinutes = tempValue;
                  if (tempUnit == 'hours') calculatedMinutes = tempValue * 60;
                  if (tempUnit == 'days') calculatedMinutes = tempValue * 1440;
                  if (tempUnit == 'weeks') calculatedMinutes = tempValue * 10080;

                  setState(() {
                    _selectedLeadTimes.add(max(1, calculatedMinutes));
                  });
                  Navigator.pop(ctx);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatLeadMinutes(int mins) {
    if (mins >= 10080 && mins % 10080 == 0) return '${mins ~/ 10080}w';
    if (mins >= 1440 && mins % 1440 == 0) return '${mins ~/ 1440}d';
    if (mins >= 60 && mins % 60 == 0) return '${mins ~/ 60}h';
    if (mins >= 60) return '${mins ~/ 60}h ${mins % 60}m';
    return '${mins}m';
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

  Future<void> _deleteExistingQuest() async {
    if (widget.existingTask == null) return;
    final id = widget.existingTask!['id'] as int;
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'habits.db');
    final db = await openDatabase(path);
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _saveTask() async {
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final double lat = _requireGps ? _selectedLatLng.latitude : 0.0;
    final double lng = _requireGps ? _selectedLatLng.longitude : 0.0;
    final df = DateFormat('yyyy-MM-dd');

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Directive title required.')));
      return;
    }

    if ((_recurrenceType == 'weekly' || _recurrenceType == 'biweekly') && selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one active day.')));
      return;
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'habits.db');
    final db = await openDatabase(path);

    String repeatDaysStr = '1,2,3,4,5,6,7';
    String? startStr;
    String? endStr;
    String finalRecurrenceType = _recurrenceType;

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
    } else if (_recurrenceType == 'custom') {
      finalRecurrenceType = 'custom:${_customIntervalValue}_$_customIntervalUnit';
      startStr = df.format(_recurrenceStart ?? _questDate);
      endStr = _recurrenceEnd != null ? df.format(_recurrenceEnd!) : null;
      repeatDaysStr = '1,2,3,4,5,6,7';
    } else {
      repeatDaysStr = (selectedDays.toList()..sort()).join(',');
      startStr = _recurrenceStart != null ? df.format(_recurrenceStart!) : null;
      endStr = _recurrenceEnd != null ? df.format(_recurrenceEnd!) : null;
    }

    final leadsStr = (_selectedLeadTimes.toList()..sort()).join(',');

    final payload = {
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
      'recurrence_start_date': startStr,
      'recurrence_end_date': endStr,
      'recurrence_type': finalRecurrenceType,
      'notify_enabled': _notifyEnabled ? 1 : 0,
      'notify_leads': leadsStr.isEmpty ? "15" : leadsStr,
      'require_gps': _requireGps ? 1 : 0,
      'is_boss': _isBossEncounter ? 1 : 0,
      'boss_stake': _bossStake,
      'primary_stat': _primaryStat,
      'secondary_stat': _secondaryStat,
      'skill_id': _selectedSkillId,
    };

    if (widget.existingTask != null) {
      await db.update('tasks', payload, where: 'id = ?', whereArgs: [widget.existingTask!['id']]);
    } else {
      payload['last_completed_date'] = null;
      payload['is_completed'] = 0;
      payload['excluded_dates'] = '';
      payload['penalty_applied_date'] = '';
      payload['prep_stacks'] = 0;
      await db.insert('tasks', payload);
    }

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd');
    final accent = widget.accentColor;
    final isEditing = widget.existingTask != null;

    return Scaffold(
      backgroundColor: SystemTheme.background,
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          isEditing ? 'EDIT DIRECTIVE' : 'REGISTER DIRECTIVE',
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.0),
        ),
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: SystemTheme.dangerRed),
              onPressed: _deleteExistingQuest,
            ),
        ],
        backgroundColor: SystemTheme.surface,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SystemCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      labelText: 'Directive Title',
                      labelStyle: SystemTheme.captionStyle,
                      filled: true,
                      fillColor: SystemTheme.surfaceElevated,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _descriptionController,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Location / Notes (Optional)',
                      labelStyle: SystemTheme.captionStyle,
                      filled: true,
                      fillColor: SystemTheme.surfaceElevated,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('DISCIPLINE SECTOR', style: SystemTheme.captionStyle),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: _categories.map((cat) {
                      final isSelected = _selectedCategory == cat;
                      return ChoiceChip(
                        label: Text(cat.toUpperCase()),
                        selected: isSelected,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _selectedCategory = cat),
                        selectedColor: accent.withValues(alpha: 0.16),
                        backgroundColor: SystemTheme.surfaceElevated,
                        side: BorderSide(color: isSelected ? accent : SystemTheme.border, width: 1.0),
                        labelStyle: TextStyle(
                          color: isSelected ? accent : Colors.white70,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  Text('LINKED SPECIALIZATION', style: SystemTheme.captionStyle),
                  DropdownButton<int>(
                    value: _selectedSkillId,
                    dropdownColor: SystemTheme.surface,
                    isExpanded: true,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                    items: [
                      const DropdownMenuItem<int>(
                        value: -1,
                        child: Text("None (Direct Stat Only)", style: TextStyle(color: Colors.white38)),
                      ),
                      ...widget.skills.map((s) {
                        final letter = SystemRanks.getSkillRankLetter((s['mastery_xp'] as int?) ?? 0);
                        return DropdownMenuItem<int>(
                          value: s['id'] as int,
                          child: Text("${s['name']} ($letter-Rank)"),
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
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('ATTRIBUTES TARGETED', style: SystemTheme.captionStyle),
                      Text(
                        _manualStatOverride ? '[ MANUAL ]' : '[ AUTO DETECTED ]',
                        style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.w800, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: ['STR', 'VIT', 'INT', 'PER', 'AGI'].map((stat) {
                      final isPrimary = _primaryStat == stat;
                      final isSecondary = _secondaryStat == stat;
                      final bool isSelected = isPrimary || isSecondary;
                      return ChoiceChip(
                        label: Text(isPrimary ? "$stat (1°)" : (isSecondary ? "$stat (2°)" : stat)),
                        selected: isSelected,
                        showCheckmark: false,
                        selectedColor: accent.withValues(alpha: 0.16),
                        backgroundColor: SystemTheme.surfaceElevated,
                        side: BorderSide(
                          color: isPrimary ? accent : (isSecondary ? accent.withValues(alpha: 0.5) : SystemTheme.border),
                          width: 1.0,
                        ),
                        labelStyle: TextStyle(
                          color: isPrimary ? accent : (isSecondary ? Colors.white : Colors.white70),
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
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
            const SizedBox(height: 12),

            SystemCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TIMELINE & RECURRENCE', style: SystemTheme.captionStyle),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: SystemTheme.border),
                            backgroundColor: SystemTheme.surfaceElevated,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          onPressed: _pickStartTime,
                          child: Text('Start: ${startTime.format(context)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: SystemTheme.border),
                            backgroundColor: SystemTheme.surfaceElevated,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          onPressed: _pickEndTime,
                          child: Text('End: ${endTime.format(context)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        {'id': 'once', 'label': 'ONE-TIME'},
                        {'id': 'weekly', 'label': 'WEEKLY'},
                        {'id': 'biweekly', 'label': 'BI-WEEKLY'},
                        {'id': 'monthly', 'label': 'MONTHLY'},
                        {
                          'id': 'custom',
                          'label': _recurrenceType == 'custom'
                              ? 'EVERY $_customIntervalValue ${_customIntervalUnit.toUpperCase()}'
                              : 'CUSTOM...'
                        },
                      ].map((item) {
                        final isSelected = _recurrenceType == item['id'];
                        return Padding(
                          padding: const EdgeInsets.only(right: 6.0),
                          child: ChoiceChip(
                            label: Text(item['label']!),
                            selected: isSelected,
                            showCheckmark: false,
                            onSelected: (_) {
                              if (item['id'] == 'custom') {
                                _showCustomRecurrenceDialog();
                              } else {
                                setState(() => _recurrenceType = item['id']!);
                              }
                            },
                            selectedColor: accent.withValues(alpha: 0.16),
                            backgroundColor: SystemTheme.surfaceElevated,
                            side: BorderSide(color: isSelected ? accent : SystemTheme.border),
                            labelStyle: TextStyle(
                              color: isSelected ? accent : Colors.white70,
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_recurrenceType == 'once' || _recurrenceType == 'monthly')
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: SystemTheme.border),
                          backgroundColor: SystemTheme.surfaceElevated,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onPressed: _pickSingleDate,
                        child: Text(
                          _recurrenceType == 'once'
                              ? DateFormat('EEEE, MMM d, yyyy').format(_questDate).toUpperCase()
                              : 'STARTS ${df.format(_questDate)} (DAY ${_questDate.day} MONTHLY)',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
                        ),
                      ),
                    )
                  else if (_recurrenceType == 'custom') ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: SystemTheme.border),
                              backgroundColor: SystemTheme.surfaceElevated,
                            ),
                            onPressed: () => _pickRecurrenceDate(true),
                            child: Text(_recurrenceStart == null ? 'From: Today' : 'From: ${df.format(_recurrenceStart!)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: SystemTheme.border),
                              backgroundColor: SystemTheme.surfaceElevated,
                            ),
                            onPressed: () => _pickRecurrenceDate(false),
                            child: Text(_recurrenceEnd == null ? 'To: Ongoing' : 'To: ${df.format(_recurrenceEnd!)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
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
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected ? accent.withValues(alpha: 0.16) : SystemTheme.surfaceElevated,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: isSelected ? accent : SystemTheme.border, width: 1.0),
                            ),
                            child: Text(
                              dayLabels[index],
                              style: TextStyle(
                                color: isSelected ? accent : Colors.white70,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: SystemTheme.border),
                              backgroundColor: SystemTheme.surfaceElevated,
                            ),
                            onPressed: () => _pickRecurrenceDate(true),
                            child: Text(_recurrenceStart == null ? 'From: Any' : 'From: ${df.format(_recurrenceStart!)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: SystemTheme.border),
                              backgroundColor: SystemTheme.surfaceElevated,
                            ),
                            onPressed: () => _pickRecurrenceDate(false),
                            child: Text(_recurrenceEnd == null ? 'To: Ongoing' : 'To: ${df.format(_recurrenceEnd!)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Advance Notification Timers
            SystemCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.notifications_active_outlined, color: SystemTheme.cyan, size: 16),
                          SizedBox(width: 8),
                          Text('ADVANCE REMINDERS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                        ],
                      ),
                      Switch(
                        value: _notifyEnabled,
                        activeThumbColor: accent,
                        onChanged: (val) => setState(() => _notifyEnabled = val),
                      ),
                    ],
                  ),
                  if (_notifyEnabled) ...[
                    const SizedBox(height: 8),
                    Text('LEAD TIME PRIOR TO COMMENCEMENT', style: SystemTheme.captionStyle),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ...{10, 15, 30, 60, 1440, ..._selectedLeadTimes}.map((mins) {
                          final bool isSel = _selectedLeadTimes.contains(mins);
                          return ChoiceChip(
                            label: Text(_formatLeadMinutes(mins)),
                            selected: isSel,
                            showCheckmark: false,
                            selectedColor: accent.withValues(alpha: 0.16),
                            backgroundColor: SystemTheme.surfaceElevated,
                            side: BorderSide(color: isSel ? accent : SystemTheme.border, width: 1.0),
                            labelStyle: TextStyle(
                              color: isSel ? accent : Colors.white70,
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                            ),
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedLeadTimes.add(mins);
                                } else if (_selectedLeadTimes.length > 1) {
                                  _selectedLeadTimes.remove(mins);
                                }
                              });
                            },
                          );
                        }),
                        ActionChip(
                          avatar: const Icon(Icons.add, color: SystemTheme.cyan, size: 14),
                          label: const Text("CUSTOM", style: TextStyle(color: SystemTheme.cyan, fontSize: 10, fontWeight: FontWeight.w900)),
                          backgroundColor: SystemTheme.surfaceElevated,
                          side: const BorderSide(color: SystemTheme.cyan, width: 0.8),
                          onPressed: _showCustomLeadTimeDialog,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            SystemCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.gps_fixed, color: SystemTheme.cyan, size: 16),
                          SizedBox(width: 8),
                          Text('COORDINATE LOCK (GPS)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                        ],
                      ),
                      Switch(value: _requireGps, activeThumbColor: accent, onChanged: (val) => setState(() => _requireGps = val)),
                    ],
                  ),
                  if (_requireGps) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        height: 180,
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
                                      borderStrokeWidth: 1.2,
                                    ),
                                  ],
                                ),
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: _selectedLatLng,
                                      width: 32,
                                      height: 32,
                                      child: Icon(Icons.location_pin, color: accent, size: 30),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: FloatingActionButton.small(
                                heroTag: 'gps_sync_btn',
                                backgroundColor: SystemTheme.surface,
                                foregroundColor: accent,
                                onPressed: _fetchingLocation ? null : _centerMapOnCurrentLocation,
                                child: _fetchingLocation
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.my_location_rounded, size: 16),
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
                        Text('Radius Tolerance', style: SystemTheme.captionStyle),
                        Text('${_radiusMeters.toInt()}m', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w900)),
                      ],
                    ),
                    Slider(
                      value: _radiusMeters,
                      min: 50,
                      max: 500,
                      divisions: 18,
                      activeColor: accent,
                      inactiveColor: SystemTheme.surfaceElevated,
                      onChanged: (val) => setState(() => _radiusMeters = val),
                    ),
                  ],
                  const Divider(color: SystemTheme.border),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: SystemTheme.shadowViolet, size: 16),
                          SizedBox(width: 8),
                          Text('BOSS CHALLENGE GATE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                        ],
                      ),
                      Switch(
                        value: _isBossEncounter,
                        activeThumbColor: SystemTheme.shadowViolet,
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
                        Text('Stake Amount', style: SystemTheme.captionStyle),
                        Text('±$_bossStake RR', style: const TextStyle(color: SystemTheme.shadowViolet, fontWeight: FontWeight.w900, fontSize: 11)),
                      ],
                    ),
                    Slider(
                      value: _bossStake.toDouble(),
                      min: 200,
                      max: 1000,
                      divisions: 8,
                      activeColor: SystemTheme.shadowViolet,
                      inactiveColor: SystemTheme.surfaceElevated,
                      onChanged: (val) => setState(() => _bossStake = val.round()),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),

            SystemButton(
              label: isEditing
                  ? 'UPDATE DIRECTIVE'
                  : (_isBossEncounter ? 'OPEN GATE DIRECTIVE' : 'SUBMIT DIRECTIVE'),
              color: _isBossEncounter ? SystemTheme.shadowViolet : accent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              fontSize: 12,
              onPressed: _saveTask,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}