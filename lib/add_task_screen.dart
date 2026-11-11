import 'package:flutter/material.dart';
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
      backgroundColor: ValencePalette.bgCanvas,
      appBar: AppBar(
        title: const Text('CREATE QUEST', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
        backgroundColor: ValencePalette.bgCard,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TactileCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                    decoration: InputDecoration(
                      labelText: 'Quest Title (e.g. BJJ Sparring, Accounting Seminar)',
                      labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                      filled: true,
                      fillColor: ValencePalette.bgRecessed,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _descriptionController,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      labelText: 'Room / Gym / Notes (Optional)',
                      labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                      filled: true,
                      fillColor: ValencePalette.bgRecessed,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('CATEGORY', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w900)),
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
                          backgroundColor: ValencePalette.bgRecessed,
                          labelStyle: TextStyle(color: isSelected ? const Color(0xFF0F191E) : Colors.white70, fontWeight: FontWeight.w900, fontSize: 12),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  const Text('LINKED SKILL (OPTIONAL)', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w900)),
                  DropdownButton<int>(
                    value: _selectedSkillId,
                    dropdownColor: ValencePalette.bgCard,
                    isExpanded: true,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
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
                      const Text('TARGET ATTRIBUTES', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w900)),
                      Text(
                        _manualStatOverride ? 'Manual / Skill Sync' : '✨ Auto-Detected',
                        style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w900),
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
                        backgroundColor: ValencePalette.bgRecessed,
                        labelStyle: TextStyle(color: isPrimary ? const Color(0xFF0F191E) : Colors.white, fontWeight: FontWeight.w900, fontSize: 11),
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

            TactileCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('TIME & SCHEDULE', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: ValencePalette.borderLip, width: 2),
                            backgroundColor: ValencePalette.bgRecessed,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _pickStartTime,
                          icon: Icon(Icons.access_time_rounded, color: accent, size: 18),
                          label: Text('Start: ${startTime.format(context)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: ValencePalette.borderLip, width: 2),
                            backgroundColor: ValencePalette.bgRecessed,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _pickEndTime,
                          icon: Icon(Icons.access_time_filled_rounded, color: accent, size: 18),
                          label: Text('End: ${endTime.format(context)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
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
                            backgroundColor: ValencePalette.bgRecessed,
                            labelStyle: TextStyle(color: isSelected ? const Color(0xFF0F191E) : Colors.white70, fontWeight: FontWeight.w900, fontSize: 12),
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
                          side: const BorderSide(color: ValencePalette.borderLip, width: 2),
                          backgroundColor: ValencePalette.bgRecessed,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _pickSingleDate,
                        icon: Icon(Icons.event_rounded, color: accent, size: 18),
                        label: Text(
                          _recurrenceType == 'once'
                              ? DateFormat('EEEE, MMM d, yyyy').format(_questDate)
                              : 'Starts ${df.format(_questDate)} (Day ${_questDate.day} monthly)',
                          style: const TextStyle(fontWeight: FontWeight.w800),
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
                              color: isSelected ? accent : ValencePalette.bgRecessed,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isSelected ? accent : ValencePalette.borderLip, width: 2),
                            ),
                            child: Text(dayLabels[index], style: TextStyle(color: isSelected ? const Color(0xFF0F191E) : Colors.white70, fontWeight: FontWeight.w900)),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: ValencePalette.borderLip), backgroundColor: ValencePalette.bgRecessed),
                            onPressed: () => _pickRecurrenceDate(true),
                            child: Text(_recurrenceStart == null ? 'From: Any' : 'From: ${df.format(_recurrenceStart!)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: ValencePalette.borderLip), backgroundColor: ValencePalette.bgRecessed),
                            onPressed: () => _pickRecurrenceDate(false),
                            child: Text(_recurrenceEnd == null ? 'To: Ongoing' : 'To: ${df.format(_recurrenceEnd!)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            TactileCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.location_on_rounded, color: ValencePalette.blue, size: 20),
                          SizedBox(width: 8),
                          Text('Require GPS Geofence', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                        ],
                      ),
                      Switch(value: _requireGps, activeThumbColor: accent, onChanged: (val) => setState(() => _requireGps = val)),
                    ],
                  ),
                  if (_requireGps) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
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
                                      color: accent.withValues(alpha: 0.24),
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
                                backgroundColor: ValencePalette.bgCard,
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
                        const Text('Radius', style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w700)),
                        Text('${_radiusMeters.toInt()} m', style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 12)),
                      ],
                    ),
                    Slider(
                      value: _radiusMeters,
                      min: 50,
                      max: 500,
                      divisions: 18,
                      activeColor: accent,
                      inactiveColor: ValencePalette.bgRecessed,
                      onChanged: (val) => setState(() => _radiusMeters = val),
                    ),
                  ],
                  const Divider(color: ValencePalette.borderLip),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.emoji_events_rounded, color: ValencePalette.gold, size: 20),
                          SizedBox(width: 8),
                          Text('Boss Challenge (50/50 Check)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                        ],
                      ),
                      Switch(
                        value: _isBossEncounter,
                        activeThumbColor: ValencePalette.gold,
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
                        const Text('Stake Amount', style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w700)),
                        Text('±$_bossStake RR', style: const TextStyle(color: ValencePalette.gold, fontWeight: FontWeight.w900, fontSize: 12)),
                      ],
                    ),
                    Slider(
                      value: _bossStake.toDouble(),
                      min: 200,
                      max: 1000,
                      divisions: 8,
                      activeColor: ValencePalette.gold,
                      inactiveColor: ValencePalette.bgRecessed,
                      onChanged: (val) => setState(() => _bossStake = val.round()),
                    ),
                  ],
                  const Divider(color: ValencePalette.borderLip),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.notifications_active_rounded, color: ValencePalette.orange, size: 20),
                          SizedBox(width: 8),
                          Text('Advance Reminders', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
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
                          backgroundColor: ValencePalette.bgRecessed,
                          labelStyle: TextStyle(color: isSel ? const Color(0xFF0F191E) : Colors.white70, fontWeight: FontWeight.w900, fontSize: 11),
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

            TactileButton(
              label: _isBossEncounter ? 'SAVE BOSS CHALLENGE' : 'SAVE QUEST',
              color: _isBossEncounter ? ValencePalette.gold : accent,
              padding: const EdgeInsets.symmetric(vertical: 16),
              fontSize: 15,
              onPressed: _saveTask,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}