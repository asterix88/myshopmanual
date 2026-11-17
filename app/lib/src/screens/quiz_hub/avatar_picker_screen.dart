/// Choosing the avatar shown on the Leaderboard.
library;

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/quiz_widgets.dart';
import '../quiz_hub_screen.dart';
import '../quiz_screen.dart';
import '../shell.dart';

/// "Ganti avatar": the 10 avatars; Simpan returns the chosen one.
class AvatarPickerScreen extends StatefulWidget {
  const AvatarPickerScreen({super.key, required this.current});

  final int current;

  @override
  State<AvatarPickerScreen> createState() => _AvatarPickerScreenState();
}

class _AvatarPickerScreenState extends State<AvatarPickerScreen> {
  late int _picked = widget.current;

  @override
  Widget build(BuildContext context) {
    final session = StoreScope.of(context).session;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const QuizBar(title: 'Ganti avatar'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(child: QuizAvatar(_picked, size: 96)),
          const SizedBox(height: 6),
          Text(titleCaseWords(session?.name ?? ''), textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          if (session != null && session.sections.isNotEmpty)
            Text(session.sections.join(', '), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 16),
          const SectionLabel('Pilih avatar'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: GridView.count(
              crossAxisCount: 5,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              children: [
                for (final k in avatarOrder)
                  Semantics(
                    button: true,
                    selected: k == _picked,
                    label: avatarNames[k],
                    child: GestureDetector(
                      onTap: () => setState(() => _picked = k),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: k == _picked ? AppColors.navy : Colors.transparent, width: 2.5),
                          ),
                          child: QuizAvatar(k, size: 52),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton(onPressed: () => Navigator.pop(context, _picked), child: const Text('Simpan')),
          ),
        ],
      ),
    );
  }
}
