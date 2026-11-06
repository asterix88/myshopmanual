import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'diagnostics.dart';
import 'quiz.dart';

/// Quiz reminders on the phone itself: a daily one at the mechanic's chosen
/// time and a streak warning at 20.00. Android shows them at that time even
/// without signal or with the app closed. Each time the app learns the quiz
/// state (Home card, Quiz page, after a set) the next 7 days are planned
/// again, so a day whose quiz is done gets no reminder.
const quizPayload = 'quiz';
const _channelId = 'quiz-reminders';
const _dailyId = 300;
const _streakId = 320;
const _days = 7;

/// A quiz day runs from 04.00 to 04.00 the next morning.
const quizDayStartHour = 4;

/// The streak warning's hour.
const streakHour = 20;

class ReminderSettings {
  const ReminderSettings({this.daily = true, this.hour = 7, this.minute = 0, this.streak = true});

  factory ReminderSettings.fromJson(Map<String, dynamic> j) => ReminderSettings(
        daily: j['daily'] != false,
        hour: ((j['hour'] as num?)?.toInt() ?? 7).clamp(0, 23),
        minute: ((j['minute'] as num?)?.toInt() ?? 0).clamp(0, 59),
        streak: j['streak'] != false,
      );

  final bool daily;
  final int hour;
  final int minute;
  final bool streak;

  ReminderSettings copyWith({bool? daily, int? hour, int? minute, bool? streak}) => ReminderSettings(
        daily: daily ?? this.daily,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        streak: streak ?? this.streak,
      );

  Map<String, dynamic> toJson() => {'daily': daily, 'hour': hour, 'minute': minute, 'streak': streak};

  /// "07.00".
  String get time => '${hour.toString().padLeft(2, '0')}.${minute.toString().padLeft(2, '0')}';
}

class PlannedReminder {
  const PlannedReminder(this.id, this.at, this.title, this.body);

  final int id;
  final DateTime at;
  final String title;
  final String body;

  @override
  String toString() => 'PlannedReminder($id, $at, $title, $body)';
}

/// "2026-11-06": the quiz day that [t] (local time) belongs to.
String quizDayOf(DateTime t) {
  final d = t.subtract(const Duration(hours: quizDayStartHour));
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

String _nextDay(String day) {
  final d = DateTime.tryParse('${day}T00:00:00Z');
  if (d == null) return '';
  return d.add(const Duration(days: 1)).toIso8601String().substring(0, 10);
}

/// The reminders for the next 7 days from [now], given the quiz state
/// [home] from the server. Pure, so tests can check it.
List<PlannedReminder> planReminders(DateTime now, ReminderSettings settings, QuizHome home) {
  if (home.questions == 0) return const [];
  final today = home.day.isEmpty ? quizDayOf(now) : home.day;
  final tomorrow = _nextDay(today);
  // The streak still stands on that quiz day if it is kept up until then:
  // today while today's quiz is not done yet, tomorrow once it is done.
  bool streakAlive(String day) =>
      home.streak > 0 && ((day == today && !home.done) || (day == tomorrow && home.done));
  bool done(String day) => day == today && home.done;

  final out = <PlannedReminder>[];
  final first = DateTime(now.year, now.month, now.day);
  for (var k = 0; k < _days; k++) {
    final date = DateTime(first.year, first.month, first.day + k);
    if (settings.daily) {
      final at = DateTime(date.year, date.month, date.day, settings.hour, settings.minute);
      final day = quizDayOf(at);
      if (at.isAfter(now) && !done(day) && day.compareTo(today) >= 0) {
        final streak = streakAlive(day) ? ' Streak ${home.streak} hari.' : '';
        out.add(PlannedReminder(_dailyId + k, at, 'Quiz harian menunggu', '10 soal, sekitar 4 menit.$streak'));
      }
    }
    if (settings.streak) {
      final at = DateTime(date.year, date.month, date.day, streakHour);
      final day = quizDayOf(at);
      if (at.isAfter(now) && !done(day) && streakAlive(day)) {
        out.add(PlannedReminder(
          _streakId + k,
          at,
          'Streak ${home.streak} hari belum aman',
          'Quiz hari ini berakhir pukul 04.00.',
        ));
      }
    }
  }
  return out;
}

class QuizReminders {
  QuizReminders._();

  /// Only the real app talks to Android; tests leave it off.
  static bool active = false;

  /// Set when a reminder is tapped; Home opens today's quiz once it shows
  /// (after the opening animation or login, if those come first).
  static final openRequested = ValueNotifier(false);

  static final _notifications = FlutterLocalNotificationsPlugin();

  static File _file(Directory root) => File('${root.path}/quiz_reminders.json');

  static ReminderSettings load(Directory root) {
    try {
      final f = _file(root);
      if (f.existsSync()) return ReminderSettings.fromJson(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
    } on Object {
      // Back to the defaults.
    }
    return const ReminderSettings();
  }

  static Future<void> save(Directory root, ReminderSettings settings) async {
    await _file(root).writeAsString(jsonEncode(settings.toJson()));
  }

  /// Plans the next 7 days again from [home]; with no [home] (logged out)
  /// every quiz reminder is taken off.
  static Future<void> sync(Directory root, QuizHome? home, {DateTime? now}) async {
    if (!active) return;
    try {
      for (var k = 0; k < _days; k++) {
        await _notifications.cancel(id: _dailyId + k);
        await _notifications.cancel(id: _streakId + k);
      }
      if (home == null) return;
      final plan = planReminders(now ?? DateTime.now(), load(root), home);
      for (final r in plan) {
        await _notifications.zonedSchedule(
          id: r.id,
          title: r.title,
          body: r.body,
          payload: quizPayload,
          // Times are worked out in the phone's own clock, then handed over
          // as UTC, so no time zone table is needed.
          scheduledDate: tz.TZDateTime.from(r.at.toUtc(), tz.UTC),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              'Pengingat quiz',
              channelDescription: 'Pengingat quiz harian dan peringatan streak',
              importance: Importance.high,
              color: Color(0xFF1E3A64),
            ),
          ),
        );
      }
    } on Object catch (e) {
      Diagnostics.log('quiz reminders not planned: $e');
    }
  }
}
