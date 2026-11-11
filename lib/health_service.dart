import 'dart:math';
import 'package:health/health.dart';

class HealthService {
  static final Health _health = Health();

  static const List<HealthDataType> _types = [
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_SESSION,
  ];

  /// Requests permission to read sleep records from Health Connect
  static Future<bool> requestSleepPermissions() async {
    try {
      await _health.configure();
      final bool? hasPermissions = await _health.hasPermissions(_types);
      if (hasPermissions == true) return true;
      return await _health.requestAuthorization(_types);
    } catch (_) {
      return false;
    }
  }

  /// Queries sleep sessions logged between yesterday evening and this morning.
  /// Returns total duration in hours, or null if no records exist.
  static Future<double?> fetchLastNightSleepDuration() async {
    try {
      await _health.configure();

      final now = DateTime.now();
      // Search window: yesterday 18:00 to today now
      final startTime = DateTime(now.year, now.month, now.day - 1, 18, 0);
      final endTime = now;

      final List<HealthDataPoint> data = await _health.getHealthDataFromTypes(
        types: _types,
        startTime: startTime,
        endTime: endTime,
      );

      if (data.isEmpty) return null;

      // Filter out overlapping stages or calculate from sessions
      int totalMinutes = 0;

      // Prefer SLEEP_SESSION if available
      final sessions = data.where((p) => p.type == HealthDataType.SLEEP_SESSION).toList();
      if (sessions.isNotEmpty) {
        for (final s in sessions) {
          totalMinutes += s.dateTo.difference(s.dateFrom).inMinutes;
        }
      } else {
        // Fall back to asleep stage intervals
        final asleepStages = data.where((p) => p.type == HealthDataType.SLEEP_ASLEEP).toList();
        for (final stage in asleepStages) {
          totalMinutes += stage.dateTo.difference(stage.dateFrom).inMinutes;
        }
      }

      if (totalMinutes <= 0) return null;

      // Clamp to reasonable human range (1.0h to 14.0h)
      final double totalHours = totalMinutes / 60.0;
      return double.parse(max(1.0, min(14.0, totalHours)).toStringAsFixed(1));
    } catch (_) {
      return null;
    }
  }
}