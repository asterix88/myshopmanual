import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mymanual/src/models.dart';
import 'package:mymanual/src/page_image.dart';
import 'package:mymanual/src/quiz.dart';
import 'package:mymanual/src/quiz_edit.dart';
import 'package:mymanual/src/quiz_reminders.dart';
import 'package:mymanual/src/screens/quiz_admin_screen.dart';
import 'package:mymanual/src/screens/quiz_crop_screen.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:mymanual/src/screens/quiz_hub_screen.dart';
import 'package:mymanual/src/screens/quiz_screen.dart';
import 'package:mymanual/src/screens/shell.dart';
import 'package:mymanual/src/search.dart' show pageHeading;
import 'package:mymanual/src/store.dart';

import 'store_test.dart' show fixtureCatalog, fixtureServer, testSession;

Map<String, dynamic> homeJson({int questions = 30, String daily = 'belum', int streak = 3}) => {
      'daily': daily,
      'session_id': null,
      'streak': streak,
      'best_streak': 5,
      'xp_week': 120,
      'xp_total': 900,
      'rank_week': 2,
      'avatar': 3,
      'questions': questions,
      'mastered': 4,
      'last_daily': '2026-11-05',
      'day': '2026-11-06',
      'freeze_week': null,
    };

Map<String, dynamic> question(String id) => {
      'id': id,
      'unit': 'TEST1-1',
      'topic': 'hidrolik',
      'type': 'pg',
      'prompt': 'Soal $id: fungsi main relief valve?',
      'choices': ['Membatasi tekanan', 'Menambah debit', 'Mendinginkan oli', 'Menyaring oli'],
      'answer': 0,
      'explain': 'Relief valve membuka saat tekanan melewati setelan.',
      'manual_id': 'TEST1-1/sm',
      'page': 12,
    };

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('quiz');
    AppStore.retryDelays = const [];
    QuizApi.lastHome = null;
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('an answer without signal is kept and sent with the next call', () async {
    var up = false;
    final sent = <String>[];
    final client = MockClient((request) async {
      if (request.url.path.startsWith('/quiz')) {
        if (!up) throw const SocketException('offline');
        if (request.url.path == '/quiz/answer') {
          sent.add((jsonDecode(request.body) as Map)['question_id'] as String);
          return http.Response(jsonEncode({'correct': true, 'xp': 10, 'level': 1, 'next_days': 1}), 200);
        }
        return http.Response(jsonEncode(homeJson()), 200);
      }
      return fixtureServer().send(http.Request(request.method, request.url)).then(http.Response.fromStream);
    });
    final store = await AppStore.open(root: root, client: client);
    await store.signIn(testSession(), refreshNow: false);
    final api = QuizApi(store, client);

    final result = await api.answer(QuizAnswer(sessionId: 's1', questionId: 'q1', chosen: 0, ms: 5000));
    expect(result, isNull);
    expect(File('${root.path}/quiz_pending.json').existsSync(), isTrue);

    up = true;
    final home = await api.home();
    expect(sent, ['q1']);
    expect(home.questions, 30);
    expect(home.streak, 3);
    expect(QuizApi.lastHome, same(home));
    expect(File('${root.path}/quiz_pending.json').existsSync(), isFalse);
    store.dispose();
  });

  Future<AppStore> openStore(WidgetTester tester, http.Client client, {bool admin = false}) async {
    late AppStore store;
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: client);
      await store.signIn(testSession(admin: admin), refreshNow: false);
    });
    return store;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the Home card shows the streak and hides with no questions', (tester) async {
    var questions = 30;
    final client = MockClient((request) async => http.Response(jsonEncode(homeJson(questions: questions)), 200));
    final store = await openStore(tester, client);
    await tester.pumpWidget(StoreScope(
      store: store,
      child: MaterialApp(home: Scaffold(body: QuizHomeCard(key: const ValueKey(1), client: client))),
    ));
    await settle(tester);
    expect(find.text('Quiz harian').evaluate().isNotEmpty || find.text('Jaga streakmu').evaluate().isNotEmpty, isTrue);
    expect(find.text('3'), findsOneWidget);

    // No published question yet: a mechanic sees nothing.
    questions = 0;
    QuizApi.lastHome = null;
    await tester.pumpWidget(StoreScope(
      store: store,
      child: MaterialApp(home: Scaffold(body: QuizHomeCard(key: const ValueKey(2), client: client))),
    ));
    await settle(tester);
    expect(find.byType(Text), findsNothing);
    await tester.runAsync(() async => store.dispose());
  });

  testWidgets('a set: choose, Periksa, a wrong answer comes back, then the summary', (tester) async {
    final answers = <(String, int)>[];
    final client = MockClient((request) async {
      final body = request.body.isEmpty ? <String, dynamic>{} : jsonDecode(request.body) as Map<String, dynamic>;
      return switch (request.url.path) {
        '/quiz/session' => http.Response(
            jsonEncode({'id': 's1', 'unit': null, 'questions': [question('q1'), question('q2')], 'answered': []}),
            200,
          ),
        '/quiz/answer' => () {
            answers.add((body['question_id'] as String, body['chosen'] as int));
            final right = body['chosen'] == 0;
            return http.Response(jsonEncode({'correct': right, 'xp': right ? 10 : 2, 'level': right ? 1 : 0, 'next_days': 1}), 200);
          }(),
        '/quiz/finish' => http.Response(
            jsonEncode({'score': 1, 'total': 2, 'xp_session': 22, 'streak': 4, 'freeze_used': false, 'rank': 2}),
            200,
          ),
        _ => http.Response(jsonEncode(homeJson()), 200),
      };
    });
    final store = await openStore(tester, client);
    await tester.pumpWidget(StoreScope(store: store, child: MaterialApp(home: QuizPlayScreen(client: client))));
    await settle(tester);

    expect(find.text('Soal q1: fungsi main relief valve?'), findsOneWidget);
    await tester.tap(find.text('Membatasi tekanan'));
    await tester.pump();
    await tester.tap(find.text('Periksa'));
    await settle(tester);
    expect(find.text('Benar'), findsOneWidget);
    await tester.tap(find.text('Lanjut'));
    await settle(tester);

    // q2 wrong: it comes back at the end.
    await tester.tap(find.text('Menambah debit'));
    await tester.pump();
    await tester.tap(find.text('Periksa'));
    await settle(tester);
    expect(find.text('Belum tepat'), findsOneWidget);
    await tester.tap(find.text('Lanjut'));
    await settle(tester);
    expect(find.text('Soal q2: fungsi main relief valve?'), findsOneWidget);
    await tester.tap(find.text('Membatasi tekanan'));
    await tester.pump();
    await tester.tap(find.text('Periksa'));
    await settle(tester);
    await tester.tap(find.text('Lanjut'));
    await settle(tester);

    expect(answers, [('q1', 0), ('q2', 1), ('q2', 0)]);
    expect(find.text('Selesai'), findsOneWidget);
    await tester.runAsync(() async => store.dispose());
  });

  test('a page without bookmarks is named by its title line', () {
    expect(pageHeading('12\nHYDRAULIC SYSTEM OVERVIEW\nMain pump supplies oil to...'), 'HYDRAULIC SYSTEM OVERVIEW');
    expect(pageHeading('Page 3 of 220\n© Komatsu 2020\nEngine cooling'), 'Engine cooling');
    expect(pageHeading('1\n2\n'), isNull);
  });

  test('an explanation starts with the fact', () {
    expect(cleanExplain('Halaman menyatakan bahwa OLSS mengurangi kerugian.'), 'OLSS mengurangi kerugian.');
    expect(cleanExplain('Menurut manual, relief valve membuka.'), 'Relief valve membuka.');
    expect(cleanExplain('Relief valve membatasi tekanan.'), 'Relief valve membatasi tekanan.');
  });

  test('a quiz picture covers words and the legend but keeps callout numbers', () {
    const text = '3. Main relief valve\n12\n(35)';
    final rects = [for (var i = 0; i < text.length; i++) PdfRect(i * 10.0, 100, i * 10.0 + 9, 90)];
    final parts = quizPageText(text, rects);
    // "3." (legend line), "Main", "relief", "valve"; not "12" and not "(35)".
    expect(parts.cover.length, 4);
    expect(parts.cover[1].left, 30);
    expect(parts.cover[1].right, 69);
    expect([for (final n in parts.numbers) n.text], ['12', '35']);
    expect(calloutOf('Pada gambar Pilot manifold, komponen nomor 33 adalah?'), '33');
    expect(calloutOf('Komponen (26) adalah?'), '26');
    expect(calloutOf('Komponen ini adalah?'), isNull);
  });

  test('a two-line label is one label (PM PC1250 page 153)', () {
    // Word boxes as pdfium reads them (left, bottom, right, top).
    const words = [
      ('Main', 228.6, 17.2, 252.3, 25.4), ('Pump', 256.7, 15.1, 286.1, 25.3), ('1', 290.3, 17.4, 293.7, 25.2),
      ('TVC', 91.5, 112.4, 112.8, 120.7), ('Valve', 116.6, 112.4, 144.7, 120.5),
      ('PTO', 700.1, 61.1, 721.3, 69.2), ('lubrication', 683.1, 48.0, 738.0, 56.1),
      ('Pump', 442.0, 28.9, 471.4, 39.1), ('for', 474.8, 31.0, 489.3, 39.2), ('Aftercooler', 436.2, 17.8, 494.3, 26.0),
      ('Control', 482.7, 164.7, 520.8, 173.1), ('pump', 487.6, 149.5, 516.6, 157.8),
      ('Pump', 344.0, 478.8, 373.5, 489.0), ('for', 376.9, 480.9, 391.3, 489.1), ('Radiator', 398.4, 480.9, 442.1, 489.1),
      ('/', 444.7, 480.8, 448.5, 489.2), ('Oil', 369.9, 467.6, 383.5, 475.8), ('Cooler', 387.4, 467.6, 421.7, 475.9),
    ];
    final text = StringBuffer();
    final rects = <PdfRect>[];
    for (final (w, l, b, r, t) in words) {
      for (var i = 0; i < w.length; i++) {
        final x = l + (r - l) * i / w.length;
        text.write(w[i]);
        rects.add(PdfRect(x, t, x + (r - l) / w.length, b));
      }
      text.write(' ');
      rects.add(PdfRect(r, t, r, t));
    }
    final labels = {for (final l in quizLabels(text.toString(), rects)) l.text};
    expect(labels, {
      'Main Pump 1', 'TVC Valve', 'PTO lubrication', 'Pump for Aftercooler', 'Control pump',
      'Pump for Radiator / Oil Cooler',
    });
  });

  test('a quiz picture keeps only the drawing that holds the asked number', () {
    // A 200x300 white page: text-like bar at top, drawing A (left, middle),
    // drawing B (right, middle), a bar at the bottom.
    const w = 200, h = 300;
    final rgba = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 255);
    void fill(int l, int t, int r, int b) {
      for (var y = t; y < b; y++) {
        for (var x = l; x < r; x++) {
          final i = (y * w + x) * 4;
          rgba[i] = rgba[i + 1] = rgba[i + 2] = 0;
        }
      }
    }

    fill(10, 10, 190, 20);
    fill(20, 100, 80, 180);
    fill(120, 110, 180, 170);
    fill(10, 280, 190, 290);
    final a = autoCrop(rgba, w, h, [const Rect.fromLTWH(50, 120, 6, 6)]);
    expect(a.left, lessThan(20));
    expect(a.right, lessThan(100));
    expect(a.top, greaterThan(80));
    expect(a.bottom, lessThan(200));
    final b = autoCrop(rgba, w, h, [const Rect.fromLTWH(150, 140, 6, 6)]);
    expect(b.left, greaterThan(100));
    // No number found: the biggest drawing.
    expect(autoCrop(rgba, w, h, const []).right, lessThan(100));
  });

  testWidgets('Draf: job progress, curator score, approve all that passed', (tester) async {
    final approved = <String>[];
    Map<String, dynamic> draft(String id, {bool passed = true, int score = 8}) => {
          ...question(id),
          'section': 'TRACK',
          'status': 'draf',
          'source': 'ai',
          'check_note': 'Angka di jawaban ada di halaman sumber.',
          'reports': 0,
          'answered': 0,
          'curator_score': score,
          'curator_note': 'Jelas.',
          'passed': passed,
        };
    final client = MockClient((request) async {
      final body = request.body.isEmpty ? <String, dynamic>{} : jsonDecode(request.body) as Map<String, dynamic>;
      return switch (request.url.path) {
        '/admin/quiz/questions' => http.Response(
            jsonEncode({
              'questions': body['status'] == 'draf' ? [draft('q1'), draft('q2'), draft('q3', passed: false, score: 5)] : [],
            }),
            200),
        '/admin/quiz/jobs' => http.Response(
            jsonEncode({
              'jobs': [
                {'id': 'j1', 'unit': 'TEST1-1', 'title': 'Shop Manual', 'count': 30, 'status': 'jalan', 'pages': 10, 'pages_done': 4, 'passed': 9, 'flagged': 2, 'dropped': 1, 'created_at': DateTime.now().millisecondsSinceEpoch},
              ],
            }),
            200),
        '/admin/quiz/approve' => () {
            approved.addAll([for (final id in body['ids'] as List) '$id']);
            return http.Response(jsonEncode({'ok': true, 'published': 2, 'left': []}), 200);
          }(),
        _ => http.Response(jsonEncode({'reports': []}), 200),
      };
    });
    final store = await openStore(tester, client, admin: true);
    await tester.pumpWidget(StoreScope(store: store, child: MaterialApp(home: QuizAdminScreen(client: client))));
    await settle(tester);
    expect(find.text('Sedang dibuat'), findsOneWidget);
    expect(find.text('Halaman 4 dari 10 · 11 soal jadi'), findsOneWidget);
    expect(find.text('Kurator 8/10'), findsWidgets);
    expect(find.text('2 soal lolos kurator'), findsOneWidget);
    await tester.tap(find.text('Setujui 2'));
    await settle(tester);
    await tester.tap(find.text('Setujui').last);
    await settle(tester);
    expect(approved, ['q1', 'q2']);
    expect(find.text('2 soal diterbitkan'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async => store.dispose());
  });

  testWidgets('a quiz picture from a real page: legend covered, only the asked drawing, drawn sharp', (tester) async {
    Pdfrx.pdfiumModulePath ??= File('build/native_assets/linux/libpdfium.so').absolute.path;
    Pdfrx.cacheDirectoryPath ??= Directory.systemTemp.createTempSync('pdfcache').path;
    final client = MockClient((request) async => http.Response('{}', 200));
    final store = await openStore(tester, client);
    final file = Catalog.fromJson(fixtureCatalog()).units.single.files.single;
    late QuizPage page;
    late ui.Rect crop;
    late ui.Image cut;
    await tester.runAsync(() async {
      // A 596 x 843 pt page: legend at the top, title, a drawing with
      // callouts 32 and 35, a paragraph at the bottom.
      page = await renderQuizPage(store, file, 1,
          open: () => PdfDocument.openFile(File('test/fixtures/quiz_page.pdf').absolute.path));
      crop = page.autoCropFor('35');
      cut = (await (await ui.instantiateImageCodec(await page.png(crop))).getNextFrame()).image;
    });
    final scale = page.height / 842.88;
    bool inkAt(double x, double y) {
      final i = ((y * scale).round() * page.width + (x * scale).round()) * 4;
      return page.rgba[i] < 200;
    }

    // The page is drawn full size (not in a corner at 1 px per point).
    expect(page.height, 1600);
    // "(17) Swing brake solenoid" at x 45-120 pt, 800 pt from the bottom: covered.
    expect([for (var x = 45.0; x < 120; x += 1) inkAt(x, 842.88 - 801)].contains(true), isFalse);
    // The grey drawing stays.
    expect(inkAt(150, 842.88 - 400), isTrue);
    // The crop holds the drawing and callout 35, not the legend or the paragraph.
    expect(crop.top / scale, greaterThan(842.88 - 520));
    expect(crop.bottom / scale, lessThan(842.88 - 270));
    expect(crop.left / scale, lessThan(110));
    expect(crop.right / scale, greaterThan(248));
    // Drawn again from the PDF: sharper than the page picture's own pixels.
    expect(math.max(cut.width, cut.height), greaterThan(math.max(crop.width, crop.height) * 1.5));
    page.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async => store.dispose());
  });

  testWidgets('a labelled photo: labels become letters A, B, C, the asked one sent with its letter', (tester) async {
    Pdfrx.pdfiumModulePath ??= File('build/native_assets/linux/libpdfium.so').absolute.path;
    Pdfrx.cacheDirectoryPath ??= Directory.systemTemp.createTempSync('pdfcache').path;
    final sent = <Uri>[];
    final client = MockClient((request) async {
      if (request.method == 'PUT') sent.add(request.url);
      return http.Response('{"ok":true}', 200);
    });
    final store = await openStore(tester, client, admin: true);
    final file = Catalog.fromJson(fixtureCatalog()).units.single.files.single;
    late QuizPage page;
    await tester.runAsync(() async {
      // A training slide: a photo with 8 part names on it, two of them on two lines.
      page = await renderQuizPage(store, file, 1,
          open: () => PdfDocument.openFile(File('test/fixtures/quiz_labels.pdf').absolute.path));
    });
    expect([for (final l in page.labels) l.text], [
      'PSV', 'CO NC Valve', 'PD', 'TVC output pressure', 'Servo valve', 'PT', 'TVC valve', 'Pressure reducing valve',
    ]);
    final marks = page.marksFor('tvc OUTPUT  pressure');
    expect([for (final m in marks) m.letter].join(), 'ABCDEFGH');
    expect(marks.singleWhere((m) => m.asked).letter, 'D');
    // A numbered drawing's callout is not a label: no letters.
    expect(page.marksFor('35'), isEmpty);
    expect(page.marksFor('Main relief valve'), isEmpty);

    final q = QuizQuestion({
      ...question('L1'), 'type': 'gambar', 'prompt': 'Pada foto pompa, komponen bertanda [X] adalah?',
      'choices': ['Servo valve', 'PT', 'PD', 'PSV'], 'answer': 0,
    });
    expect(q.pictureTarget, 'Servo valve');
    await tester.runAsync(() async {
      await sendQuizPicture(store, QuizApi(store, client), file, 1, {'L1': q.pictureTarget},
          open: () => PdfDocument.openFile(File('test/fixtures/quiz_labels.pdf').absolute.path));
    });
    expect(sent.single.path, '/admin/quiz/image/L1');
    expect(sent.single.queryParameters['letter'], 'E');
    page.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async => store.dispose());
  });

  testWidgets('Atur gambar opens on the drawing of the asked number and sends the chosen part', (tester) async {
    final sent = <String, Uint8List>{};
    final client = MockClient((request) async {
      if (request.method == 'PUT') sent[request.url.path] = request.bodyBytes;
      return http.Response('{"ok":true}', 200);
    });
    final store = await openStore(tester, client, admin: true);
    // A white 200x300 page with two drawings; the number 7 sits on the right one.
    late QuizPage page;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..drawRect(const Rect.fromLTWH(0, 0, 200, 300), Paint()..color = Colors.white);
      canvas.drawRect(const Rect.fromLTRB(20, 100, 80, 180), Paint()..color = Colors.black);
      canvas.drawRect(const Rect.fromLTRB(120, 110, 180, 170), Paint()..color = Colors.black);
      final image = await recorder.endRecording().toImage(200, 300);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      page = QuizPage(image, data!.buffer.asUint8List(), [(text: '7', box: const Rect.fromLTWH(150, 140, 6, 6))]);
    });
    final file = Catalog.fromJson(fixtureCatalog()).units.single.files.single;
    final q = QuizQuestion({...question('q9'), 'type': 'gambar', 'prompt': 'Pada gambar valve, komponen nomor 7 adalah?'});
    await tester.pumpWidget(StoreScope(
      store: store,
      child: MaterialApp(home: QuizCropScreen(api: QuizApi(store, client), file: file, question: q, page: () async => page)),
    ));
    await settle(tester);
    expect(find.text('Atur gambar'), findsOneWidget);
    // Already the automatic choice: nothing to reset to.
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Otomatis')).onPressed, isNull);
    await tester.tap(find.text('Simpan'));
    await settle(tester);
    final png = sent['/admin/quiz/image/q9'];
    expect(png, isNotNull);
    late ui.Image cut;
    await tester.runAsync(() async => cut = (await (await ui.instantiateImageCodec(png!)).getNextFrame()).image);
    // Only the right drawing (60 px) and its margin, not the whole page.
    expect(cut.width, lessThan(90));
    expect(cut.height, lessThan(110));
    expect(QuizApi.imageVersion('q9'), 1);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async => store.dispose());
  });

  test('QuizEdit: letters in reading order, merge, split, delete, saved in points', () {
    const a = Rect.fromLTRB(10, 10, 60, 30); // top left
    const b = Rect.fromLTRB(200, 12, 260, 30); // top right
    const c1 = Rect.fromLTRB(100, 200, 160, 215); // "Control"
    const c2 = Rect.fromLTRB(104, 220, 150, 235); // "pump", under it
    final edit = QuizEdit(
      crop: const Rect.fromLTRB(0, 0, 400, 300),
      labels: [
        const QuizLabel(c1, 'Control', [(text: 'Control', box: c1)]),
        const QuizLabel(b, 'PSV'),
        const QuizLabel(c2, 'pump', [(text: 'pump', box: c2)]),
        const QuizLabel(a, 'PD'),
      ],
      ask: 1,
    );
    expect([for (final m in edit.marks) m.letter], ['A', 'B', 'C', 'D']);
    expect(edit.letterOf(3), 'A'); // PD, top left
    expect(edit.letter, 'B'); // PSV
    // Every letter the same size.
    expect(edit.markBox(1).height, edit.markBox(3).height);

    final merged = edit.merge(2, 0);
    expect(merged.labels.length, 3);
    expect(merged.labels[0].text, 'Control pump');
    expect(merged.labels[0].box, c1.expandToInclude(c2));
    expect(merged.ask, 1);
    expect(merged.letter, 'B');

    final split = merged.split(0, 'pump');
    expect([for (final l in split.labels) l.text], ['Control', 'pump', 'PSV', 'PD']);
    expect(split.ask, 2);

    final gone = split.removeLabel(2);
    expect(gone.ask, isNull);
    expect(gone.letter, isNull);

    // Saved in PDF points: a page drawn at another size gets the same edit.
    final json = jsonDecode(jsonEncode(merged.copyWith(turns: 1, size: 1.4).toJson(2))) as Map<String, dynamic>;
    expect(json['crop'], [0, 0, 200, 150]);
    final back = QuizEdit.fromJson(json, 2)!;
    expect(back.same(merged.copyWith(turns: 1, size: 1.4)), isTrue);
    expect(back.labels[0].words.length, 2);
    expect(QuizEdit.fromJson({'v': 2}, 1), isNull);
    expect(QuizEdit.fromJson(null, 1), isNull);
  });

  testWidgets('Atur gambar v2: pick the answer label, undo, save the edit with its letter', (tester) async {
    Pdfrx.pdfiumModulePath ??= File('build/native_assets/linux/libpdfium.so').absolute.path;
    Pdfrx.cacheDirectoryPath ??= Directory.systemTemp.createTempSync('pdfcache').path;
    final sent = <String, http.Request>{};
    final client = MockClient((request) async {
      if (request.method == 'PUT') sent[request.url.path] = request;
      return http.Response('{"ok":true}', 200);
    });
    final store = await openStore(tester, client, admin: true);
    final file = Catalog.fromJson(fixtureCatalog()).units.single.files.single;
    late QuizPage page;
    await tester.runAsync(() async {
      page = await renderQuizPage(store, file, 1,
          open: () => PdfDocument.openFile(File('test/fixtures/quiz_labels.pdf').absolute.path));
    });
    final q = QuizQuestion({
      ...question('L2'), 'type': 'gambar', 'prompt': 'Pada foto pompa, komponen bertanda [X] adalah?',
      'choices': ['Servo valve', 'PT', 'PD', 'PSV'], 'answer': 0,
    });
    await tester.pumpWidget(StoreScope(
      store: store,
      child: MaterialApp(home: QuizCropScreen(api: QuizApi(store, client), file: file, question: q, page: () async => page)),
    ));
    await settle(tester);
    await tester.tap(find.text('Label'));
    await settle(tester);
    // Servo valve is the fifth label: E.
    expect(find.text('E'), findsOneWidget);
    expect(find.text('Servo valve'), findsOneWidget);

    // "Ganti", then tap the PSV label (A) on the picture.
    await tester.tap(find.text('Ganti'));
    await settle(tester);
    expect(find.textContaining('Ketuk label untuk'), findsOneWidget);
    final psv = page.labels.indexWhere((l) => l.text == 'PSV');
    final stage = tester.getRect(find.byWidgetPredicate((w) => w is CustomPaint && '${w.painter.runtimeType}' == '_EditPainter'));
    final fit = math.min((stage.width - 24) / page.width, (stage.height - 24) / page.height);
    final landscape = tester.view.physicalSize.width > tester.view.physicalSize.height;
    final origin = stage.topLeft +
        Offset((stage.width - page.width * fit) / 2, landscape ? (stage.height - page.height * fit) / 2 : 12);
    final psvLetter = QuizEdit.auto(page, 'Servo valve').letterOf(psv)!;
    await tester.tapAt(origin + page.labels[psv].box.center * fit);
    await settle(tester);
    expect(find.text(psvLetter), findsOneWidget);
    expect(find.textContaining('Ketuk label untuk'), findsNothing);

    // Undo puts E back; redo takes A again.
    await tester.tap(find.byIcon(Icons.undo));
    await settle(tester);
    expect(find.text('E'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.redo));
    await settle(tester);

    // Pratinjau: the question with its letter.
    await tester.tap(find.text('Pratinjau'));
    await settle(tester);
    expect(find.text('Pada foto pompa, komponen bertanda $psvLetter adalah?'), findsOneWidget);

    await tester.tap(find.text('Simpan'));
    for (var i = 0; i < 50 && !sent.containsKey('/admin/quiz/image/L2'); i++) {
      await settle(tester);
    }
    expect(sent['/admin/quiz/image/L2']!.url.queryParameters['letter'], psvLetter);
    final edit = (jsonDecode(sent['/admin/quiz/image-edit/L2']!.body) as Map)['edit'] as Map<String, dynamic>;
    expect(edit['ask'], psv);
    expect((edit['labels'] as List).length, 8);
    // Opened again: on the saved edit, not the automatic one.
    final again = QuizEdit.fromJson(QuizApi.savedEdit('L2'), page.scale)!;
    expect(again.letter, psvLetter);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async => store.dispose());
  });

  testWidgets('a big photo is drawn smaller until its PNG fits the server (2 MB)', (tester) async {
    late Uint8List png;
    late ui.Image back;
    await tester.runAsync(() async {
      // 1600 x 900 of noise: as a PNG far over 2 MB.
      final random = math.Random(1);
      final pixels = Uint8List(1600 * 900 * 4);
      for (var i = 0; i < pixels.length; i++) {
        pixels[i] = i % 4 == 3 ? 255 : random.nextInt(256);
      }
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(pixels, 1600, 900, ui.PixelFormat.rgba8888, done.complete);
      final page = QuizPage(await done.future, pixels, const []);
      png = await page.png(const Rect.fromLTWH(0, 0, 1600, 900));
      back = (await (await ui.instantiateImageCodec(png)).getNextFrame()).image;
      page.dispose();
    });
    expect(png.length, lessThanOrEqualTo(1500000));
    expect(back.width, lessThan(1600));
    expect(back.width / back.height, closeTo(16 / 9, 0.01));
  });

  testWidgets('Atur gambar v2: leaving with changes asks first', (tester) async {
    final client = MockClient((request) async => http.Response('{"ok":true}', 200));
    final store = await openStore(tester, client, admin: true);
    late QuizPage page;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 200, 300), Paint()..color = Colors.white);
      final image = await recorder.endRecording().toImage(200, 300);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      page = QuizPage(image, data!.buffer.asUint8List(), const []);
    });
    final file = Catalog.fromJson(fixtureCatalog()).units.single.files.single;
    final q = QuizQuestion({...question('q8'), 'type': 'gambar', 'prompt': 'Pada gambar valve, komponen nomor 7 adalah?'});
    await tester.pumpWidget(StoreScope(
      store: store,
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<bool>(
              builder: (_) => QuizCropScreen(api: QuizApi(store, client), file: file, question: q, page: () async => page),
            )),
            child: const Text('buka'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('buka'));
    await settle(tester);
    // Turn the picture: a change.
    await tester.tap(find.text('Putar 90°'));
    await settle(tester);
    await tester.pageBack();
    await settle(tester);
    expect(find.text('Buang perubahan?'), findsOneWidget);
    await tester.tap(find.text('Lanjut edit'));
    await settle(tester);
    expect(find.text('Atur gambar'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);
    await tester.tap(find.text('Buang'));
    await settle(tester);
    expect(find.text('buka'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async => store.dispose());
  });

  testWidgets('a picture question shows its picture from the server', (tester) async {
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
    final asked = <String>[];
    final client = MockClient((request) async {
      asked.add(request.url.path);
      return switch (request.url.path) {
        '/quiz/session' => http.Response(
            jsonEncode({
              'id': 's1',
              'questions': [
                {...question('g1'), 'type': 'gambar', 'prompt': 'Komponen nomor 3 adalah?', 'image': 'quiz/img/g1.png'},
              ],
              'answered': [],
            }),
            200),
        '/quiz/image/g1' => http.Response.bytes(png, 200, headers: {'content-type': 'image/png'}),
        _ => http.Response(jsonEncode(homeJson()), 200),
      };
    });
    final store = await openStore(tester, client);
    await tester.pumpWidget(StoreScope(store: store, child: MaterialApp(home: QuizPlayScreen(client: client))));
    await settle(tester);
    expect(find.text('Komponen nomor 3 adalah?'), findsOneWidget);
    expect(asked, contains('/quiz/image/g1'));
    expect(find.text('Ketuk untuk perbesar'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async => store.dispose());
  });

  testWidgets('a pg question with a picture shows it to the mechanic too', (tester) async {
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
    final asked = <String>[];
    final client = MockClient((request) async {
      asked.add(request.url.path);
      return switch (request.url.path) {
        '/quiz/session' => http.Response(
            jsonEncode({
              'id': 's1',
              'questions': [
                {...question('p1'), 'prompt': 'Set pressure safety valve travel motor?', 'image': 'quiz/img/p1.png'},
              ],
              'answered': [],
            }),
            200),
        '/quiz/image/p1' => http.Response.bytes(png, 200, headers: {'content-type': 'image/png'}),
        _ => http.Response(jsonEncode(homeJson()), 200),
      };
    });
    final store = await openStore(tester, client);
    await tester.pumpWidget(StoreScope(store: store, child: MaterialApp(home: QuizPlayScreen(client: client))));
    await settle(tester);
    expect(asked, contains('/quiz/image/p1'));
    expect(find.text('Ketuk untuk perbesar'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async => store.dispose());
  });

  testWidgets('Kelola soal: Tambah gambar on a pg question, Hapus gambar once it has one', (tester) async {
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
    final deleted = <String>[];
    Map<String, dynamic> draft(String id, {String? image}) => {
          ...question(id),
          'section': 'TRACK',
          'status': 'draf',
          'source': 'ai',
          'reports': 0,
          'answered': 0,
          'passed': true,
          'image': ?image,
        };
    final client = MockClient((request) async {
      if (request.method == 'DELETE') {
        deleted.add(request.url.path);
        return http.Response('{"ok":true}', 200);
      }
      final body = request.body.isEmpty ? <String, dynamic>{} : jsonDecode(request.body) as Map<String, dynamic>;
      return switch (request.url.path) {
        '/admin/quiz/questions' => http.Response(
            jsonEncode({
              'questions': body['status'] == 'draf' ? [draft('a1'), draft('a2', image: 'quiz/img/a2.png')] : [],
            }),
            200),
        '/admin/quiz/jobs' => http.Response(jsonEncode({'jobs': []}), 200),
        '/quiz/image/a2' => http.Response.bytes(png, 200, headers: {'content-type': 'image/png'}),
        _ => http.Response(jsonEncode({'reports': []}), 200),
      };
    });
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = await openStore(tester, client, admin: true);
    await tester.pumpWidget(StoreScope(store: store, child: MaterialApp(home: QuizAdminScreen(client: client))));
    await settle(tester);
    expect(find.text('Tambah gambar'), findsOneWidget);
    expect(find.text('Atur gambar'), findsOneWidget);
    await tester.tap(find.text('Hapus gambar'));
    await settle(tester);
    expect(find.text('Hapus gambar?'), findsOneWidget);
    await tester.tap(find.text('Hapus'));
    await settle(tester);
    expect(deleted, ['/admin/quiz/image/a2']);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async => store.dispose());
  });

  group('quiz reminders', () {
    QuizHome h({String daily = 'belum', int streak = 3, int questions = 30}) =>
        QuizHome(homeJson(daily: daily, streak: streak, questions: questions));
    final morning = DateTime(2026, 11, 6, 6, 0);

    test('not done yet: today 07.00 with the streak, 20.00 warning, then each day at 07.00', () {
      final plan = planReminders(morning, const ReminderSettings(), h());
      expect(plan.first.at, DateTime(2026, 11, 6, 7));
      expect(plan.first.body, '10 soal, sekitar 4 menit. Streak 3 hari.');
      final warnings = plan.where((r) => r.title.startsWith('Streak')).toList();
      expect(warnings.single.at, DateTime(2026, 11, 6, 20));
      expect(warnings.single.title, 'Streak 3 hari belum aman');
      final daily = plan.where((r) => r.title == 'Quiz harian menunggu').toList();
      expect(daily.length, 7);
      // Tomorrow the streak is only safe if today's quiz gets done.
      expect(daily[1].body, '10 soal, sekitar 4 menit.');
    });

    test('done today: nothing today, tomorrow keeps the streak', () {
      final plan = planReminders(DateTime(2026, 11, 6, 9), const ReminderSettings(), h(daily: 'selesai'));
      expect(plan.every((r) => r.at.isAfter(DateTime(2026, 11, 7, 4))), isTrue);
      expect(plan.first.at, DateTime(2026, 11, 7, 7));
      expect(plan.first.body, endsWith('Streak 3 hari.'));
      expect(plan.where((r) => r.title.startsWith('Streak')).single.at, DateTime(2026, 11, 7, 20));
    });

    test('settings: off, another time, no streak, no questions', () {
      expect(planReminders(morning, const ReminderSettings(daily: false, streak: false), h()), isEmpty);
      expect(planReminders(morning, const ReminderSettings(), h(questions: 0)), isEmpty);
      final noStreak = planReminders(morning, const ReminderSettings(hour: 5, minute: 30), h(streak: 0));
      expect(noStreak.any((r) => r.title.startsWith('Streak')), isFalse);
      // 05.30 today has passed: the first one is tomorrow.
      expect(noStreak.first.at, DateTime(2026, 11, 7, 5, 30));
      expect(quizDayOf(DateTime(2026, 11, 7, 3, 59)), '2026-11-06');
    });

    testWidgets('the Quiz page saves the reminder time', (tester) async {
      final client = MockClient((request) async => request.url.path == '/quiz/home'
          ? http.Response(jsonEncode(homeJson()), 200)
          : http.Response(jsonEncode({'rows': [], 'me': null}), 200));
      tester.view.physicalSize = const Size(1080, 2400);
      addTearDown(tester.view.resetPhysicalSize);
      final store = await openStore(tester, client);
      await tester.pumpWidget(StoreScope(store: store, child: MaterialApp(home: QuizHubScreen(client: client))));
      await settle(tester);
      expect(find.text('Pengingat harian'), findsOneWidget);
      await tester.ensureVisible(find.text('07.00'));
      await tester.pump();
      await tester.tap(find.text('07.00'));
      await settle(tester);
      expect(find.text('Jam pengingat'), findsOneWidget);
      await tester.tap(find.text('12.00'));
      await settle(tester);
      expect(QuizReminders.load(root).hour, 12);
      expect(find.text('12.00'), findsOneWidget);
      await tester.tap(find.text('Pengingat harian'));
      await settle(tester);
      expect(QuizReminders.load(root).daily, isFalse);
      expect(find.text('12.00'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async => store.dispose());
    });
  });
}
