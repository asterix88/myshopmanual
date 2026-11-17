/// Quiz reminder settings: daily time and streak warning.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../quiz.dart';
import '../../quiz_reminders.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../shell.dart';

/// "Pengingat" on the Quiz page: each mechanic sets their own reminders.
class QuizReminderSettings extends StatefulWidget {
  const QuizReminderSettings({super.key, required this.home});

  final QuizHome home;

  @override
  State<QuizReminderSettings> createState() => _QuizReminderSettingsState();
}

class _QuizReminderSettingsState extends State<QuizReminderSettings> {
  late ReminderSettings _settings = QuizReminders.load(StoreScope.read(context).root);

  static const _times = [(5, 0), (5, 30), (6, 0), (6, 30), (7, 0), (7, 30), (12, 0), (16, 0)];

  Future<void> _set(ReminderSettings settings) async {
    setState(() => _settings = settings);
    final root = StoreScope.read(context).root;
    await QuizReminders.save(root, settings);
    await QuizReminders.sync(root, QuizApi.lastHome ?? widget.home);
  }

  /// "Jam pengingat": the usual times in equal boxes, or any time.
  Future<void> _chooseTime() async {
    final s = _settings;
    final picked = await showModalBottomSheet<(int, int)>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Jam pengingat', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.9,
                children: [
                  for (final (h, m) in _times)
                    _TimeBox(
                      label: ReminderSettings(hour: h, minute: m).time,
                      selected: s.hour == h && s.minute == m,
                      onTap: () => Navigator.pop(context, (h, m)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, (-1, -1)),
                  child: const Text('Jam lain'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked.$1 >= 0) return _set(_settings.copyWith(hour: picked.$1, minute: picked.$2));
    final other = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: s.hour, minute: s.minute),
      helpText: 'Jam pengingat',
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (other != null) await _set(_settings.copyWith(hour: other.hour, minute: other.minute));
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    final muted = TextStyle(fontSize: 12, color: AppColors.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Caps('Pengingat'),
        AppCard(
          child: Column(
            children: [
              _SwitchRow(
                title: 'Pengingat harian',
                subtitle: Text('Setiap hari', style: muted),
                time: s.daily
                    ? Material(
                        color: AppColors.navySoft,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: _chooseTime,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  s.time,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.navy,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                                Icon(Icons.expand_more, size: 18, color: AppColors.navy),
                              ],
                            ),
                          ),
                        ),
                      )
                    : null,
                value: s.daily,
                onChanged: (v) => _set(s.copyWith(daily: v)),
              ),
              Divider(height: 1, color: AppColors.divider),
              _SwitchRow(
                title: 'Peringatan streak',
                subtitle: Text('20.00 jika belum quiz', style: muted),
                value: s.streak,
                onChanged: (v) => _set(s.copyWith(streak: v)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimeBox extends StatelessWidget {
  const _TimeBox({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.navy : AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: selected ? AppColors.navy : AppColors.line),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Colors.white : null,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    ),
  );
}

class _Caps extends StatelessWidget {
  const _Caps(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.7, color: AppColors.muted),
    ),
  );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.title, required this.subtitle, required this.value, required this.onChanged, this.time});

  final String title;
  final Widget subtitle;
  final Widget? time;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onChanged(!value),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                subtitle,
              ],
            ),
          ),
          if (time != null) ...[time!, const SizedBox(width: 4)],
          Switch(value: value, onChanged: onChanged, activeThumbColor: Colors.white, activeTrackColor: AppColors.navy),
        ],
      ),
    ),
  );
}
