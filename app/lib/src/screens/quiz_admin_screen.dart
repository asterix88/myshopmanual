/// Kelola soal kuis (admins). This file holds the screen with its two tabs
/// and helpers shared by them; the rest are part files under `quiz_admin/`:
///
/// - `questions_tab.dart`   tab Soal: list, drafts, jobs, bulk approval
/// - `reports_tab.dart`     tab Laporan: questions reported as wrong
/// - `edit_screen.dart`     editing one question
/// - `generate_sheet.dart`  "Buat draf kuis" with nyel AI
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdfrx/pdfrx.dart' show PdfDocument;

import '../models.dart';
import '../page_image.dart';
import '../quiz.dart';
import '../quiz_edit.dart';
import '../search.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import 'quiz_crop_screen.dart';
import 'quiz_job_screen.dart';
import 'quiz_screen.dart';
import 'shell.dart';
import 'viewer_screen.dart';

part 'quiz_admin/edit_screen.dart';
part 'quiz_admin/generate_sheet.dart';
part 'quiz_admin/questions_tab.dart';
part 'quiz_admin/reports_tab.dart';

/// Admins: the questions nyel AI drafted wait here until an admin approves
/// them (Anas's decision in the Quiz PRD), plus questions pulled by reports
/// or by too many wrong answers.
class QuizAdminScreen extends StatefulWidget {
  const QuizAdminScreen({super.key, this.client});

  final http.Client? client;

  @override
  State<QuizAdminScreen> createState() => _QuizAdminScreenState();
}

class _QuizAdminScreenState extends State<QuizAdminScreen> {
  late final http.Client _client = widget.client ?? http.Client();
  late final QuizApi _api = QuizApi(StoreScope.read(context), _client);

  static const _tabs = [
    ('draf', 'Draf'),
    ('perlu_cek', 'Perlu cek'),
    ('ditarik', 'Ditarik'),
    ('terbit', 'Terbit'),
    ('laporan', 'Laporan'),
  ];

  @override
  void dispose() {
    if (widget.client == null) _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: QuizBar(
          title: 'Kelola soal quiz',
          trailing: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => QuizJobScreen(client: widget.client))),
            icon: const AppIcon(AppGlyph.sparkle, color: Colors.white, size: 18),
            label: const Text('Buat draf kuis', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Colors.white,
            unselectedLabelColor: const Color(0xB3FFFFFF),
            indicatorColor: AppColors.orange,
            labelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600),
            tabs: [for (final t in _tabs) Tab(text: t.$2)],
          ),
        ),
        body: TabBarView(
          children: [
            for (final t in _tabs)
              t.$1 == 'laporan' ? _ReportsTab(api: _api) : _QuestionsTab(api: _api, status: t.$1),
          ],
        ),
      ),
    );
  }
}

/// Question types with their names on screen.
const quizTypes = {'pg': 'Pilihan ganda', 'bs': 'Benar/Salah', 'gambar': 'Gambar', 'kartu': 'Kartu'};

/// Draws [page] of [file] once and sends each question of that page its
/// picture: [edits] maps a question id to how its picture is made from the
/// drawn page (usually [QuizQuestion.autoEdit]).
Future<void> sendQuizPicture(
    AppStore store, QuizApi api, ManualFile file, int page, Map<String, QuizEdit Function(QuizPage)> edits,
    {Future<PdfDocument> Function()? open}) async {
  final drawn = await renderQuizPage(store, file, page, open: open);
  try {
    for (final MapEntry(key: id, value: makeEdit) in edits.entries) {
      final edit = makeEdit(drawn);
      final Uint8List png = await edit.png(drawn);
      await api.uploadImage(id, png, letter: edit.letter);
    }
  } finally {
    drawn.dispose();
  }
}

