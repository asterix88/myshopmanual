import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth.dart';
import '../diagnostics.dart';
import '../theme.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import 'home_screen.dart' show titleCase;

/// Saweria page for supporting the app (from Anas, 28 Nov 2026).
const saweriaUrl = 'https://saweria.co/mymanual';

/// Up to two initials of [name] for the round profile badge.
String initials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
  return (words[0][0] + words[1][0]).toUpperCase();
}

enum BadgeLook { ring, white, person, soft, orange }

/// Round badge with the employee's initials, used in the Home header and here.
class ProfileBadge extends StatelessWidget {
  const ProfileBadge({super.key, required this.name, this.size = 32, this.onDark = true});

  final String name;
  final double size;

  /// On the navy header; navy fill on light cards.
  final bool onDark;

  static BadgeLook look = BadgeLook.ring;

  @override
  Widget build(BuildContext context) {
    if (!onDark) return _circle(AppColors.navyFill, Colors.white, null);
    return switch (look) {
      BadgeLook.ring => _circle(Colors.white.withValues(alpha: .14), Colors.white,
          Border.all(color: Colors.white.withValues(alpha: .7), width: 1.5)),
      BadgeLook.white => _circle(Colors.white, AppColors.header, null),
      BadgeLook.person => AppIcon(AppGlyph.person, color: Colors.white, size: size * .87),
      BadgeLook.soft => _circle(const Color(0xFF34507A), Colors.white, null),
      BadgeLook.orange => _circle(const Color(0xFFF08A1C), Colors.white, null),
    };
  }

  Widget _circle(Color fill, Color text, Border? border) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: fill, border: border),
      child: Text(
        initials(name),
        style: TextStyle(fontSize: size * .4, fontWeight: FontWeight.w600, color: text, height: 1),
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.session, required this.onLogout});

  final Session session;
  final VoidCallback onLogout;

  Future<void> _openSaweria(BuildContext context) async {
    final ok = await launchUrl(Uri.parse(saweriaUrl), mode: LaunchMode.externalApplication)
        .catchError((_) => false);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saweria tidak bisa dibuka')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = session.admin
        ? 'Admin'
        : session.quizAdmin
            ? 'Admin kuis'
            : 'Mekanik';
    final meta = <(String, String)>[
      ('NRP', session.nrp),
      if (session.sections.isNotEmpty) ('Section', session.sections.map(titleCase).join(', ')),
      if (session.department.isNotEmpty) ('Departemen', titleCase(session.department)),
      ('Peran', role),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ProfileBadge(name: session.name, size: 56, onDark: false),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        session.name,
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.ink),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Divider(height: 1, color: AppColors.divider),
                for (final (label, value) in meta)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 96,
                          child: Text(label, style: TextStyle(fontSize: 13, color: AppColors.muted)),
                        ),
                        Expanded(
                          child: Text(value, style: TextStyle(fontSize: 13, color: AppColors.ink)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionLabel('Dukung MyManual'),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppColors.orangeSoft, borderRadius: BorderRadius.circular(12)),
                      child: const AppIcon(AppGlyph.heart),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Dukungan dipakai untuk biaya server dan nyel AI',
                        style: TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.45),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FilledButton(
                  key: const Key('saweria'),
                  onPressed: () => _openSaweria(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Dukung lewat Saweria', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      SizedBox(width: 8),
                      AppIcon(AppGlyph.external, size: 18, color: Colors.white),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppCard(
            onTap: onLogout,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                AppIcon(AppGlyph.logout, size: 22, color: AppColors.danger, accent: AppColors.danger),
                const SizedBox(width: 12),
                Text('Keluar', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.danger)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Center(child: Text(versionLabel, style: TextStyle(fontSize: 12, color: AppColors.faint))),
        ],
      ),
    );
  }
}
