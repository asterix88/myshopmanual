import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymanual/main.dart';
import 'package:mymanual/src/ai.dart';
import 'package:mymanual/src/screens/chat_screen.dart';
import 'package:mymanual/src/screens/search_screen.dart';
import 'package:mymanual/src/store.dart';

import 'store_test.dart' show fixtureServer;

/// Whether [screen]'s tab is the one on screen (the others are kept, off
/// to the side of the tab pages).
bool shown(Type screen) => find.byType(screen).evaluate().isNotEmpty;

void main() {
  testWidgets('the chosen tab shows and the one left goes off screen', (tester) async {
    late AppStore store;
    final root = Directory.systemTemp.createTempSync('shell');
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: fixtureServer());
    });
    await tester.pumpWidget(MyManualApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nyel AI').last);
    await tester.pumpAndSettle();
    expect(shown(ChatScreen), isTrue);

    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    expect(shown(ChatScreen), isFalse);

    await tester.tap(find.text('Cari').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    expect(shown(SearchScreen), isFalse);

    // A sideways swipe does not change the tab; only the bar does.
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 2000);
    await tester.pumpAndSettle();
    expect(shown(SearchScreen), isFalse);
    root.deleteSync(recursive: true);
  });

  testWidgets('the bottom bar hides while scrolling down and comes back on scrolling up', (tester) async {
    late AppStore store;
    final root = Directory.systemTemp.createTempSync('shell');
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: fixtureServer());
    });
    await tester.pumpWidget(MyManualApp(store: store));
    await tester.pumpAndSettle();
    double slide() => tester.widget<AnimatedSlide>(find.byType(AnimatedSlide).last).offset.dy;
    expect(slide(), 0);

    final list = find.byType(Scrollable).first;
    await tester.drag(list, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(slide(), 1);

    await tester.drag(list, const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(slide(), 0);
    root.deleteSync(recursive: true);
  });

  testWidgets('Cari shows one card per file, with every hit in it', (tester) async {
    late AppStore store;
    final root = Directory.systemTemp.createTempSync('shell');
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: fixtureServer());
      await store.setServerUrl('https://example.test');
      await store.download(store.catalog.files.single, unitName: 'TEST1-1');
    });
    await tester.pumpWidget(MyManualApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cari').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'hydraulic oil filter');
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(milliseconds: 300));
    }
    // Pages 2 and 3 match: one card, no row per page.
    expect(find.text('2 halaman ditemukan'), findsOneWidget);
    expect(find.textContaining('hlm'), findsNothing);
    expect(find.textContaining('perlu internet'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    root.deleteSync(recursive: true);
  });

  testWidgets('back goes to Home first, then leaves the app from Home', (tester) async {
    late AppStore store;
    final root = Directory.systemTemp.createTempSync('shell');
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: fixtureServer());
    });
    await tester.pumpWidget(MyManualApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cari').last);
    await tester.pumpAndSettle();
    // Handled in the app: the Home tab shows again.
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(shown(SearchScreen), isFalse);

    // On Home the app no longer holds back, so Android closes it.
    expect(await tester.binding.handlePopRoute(), isFalse);
    expect(find.byType(AlertDialog), findsNothing);
    root.deleteSync(recursive: true);
  });

  testWidgets('Enter on the keyboard starts a new line in Nyel AI', (tester) async {
    late AppStore store;
    final root = Directory.systemTemp.createTempSync('shell');
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: fixtureServer());
    });
    await tester.pumpWidget(MyManualApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nyel AI').last);
    await tester.pumpAndSettle();

    // Questions are sent with the send button, so Enter only adds a line.
    final input = tester.widget<EditableText>(
        find.descendant(of: find.byType(ChatScreen), matching: find.byType(EditableText)));
    expect(input.keyboardType, TextInputType.multiline);
    expect(input.textInputAction, TextInputAction.newline);
    expect(input.onSubmitted, isNull);
    root.deleteSync(recursive: true);
  });

  testWidgets('questions can be copied and the chat can be searched', (tester) async {
    late AppStore store;
    final root = Directory.systemTemp.createTempSync('shell');
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: fixtureServer());
      await File(store.chatHistoryPath).writeAsString(jsonEncode({
        'entries': [
          {'user': true, 'text': 'Apa itu SL1?'},
          {'user': false, 'text': 'SL1 adalah steering clutch spring loaded.'},
          {'user': true, 'text': 'Tekanan pilot PC210?'},
          {'user': false, 'text': 'Lihat manual PC210.'},
        ],
      }));
    });
    await tester.pumpWidget(MyManualApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nyel AI').last);
    await tester.pumpAndSettle();
    // The saved conversation is read from the phone.
    for (var i = 0; i < 20 && find.byType(SelectableText).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    // The user's own question is selectable text, like the answers.
    expect(
        find.byWidgetPredicate((w) => w is SelectableText && w.textSpan?.toPlainText() == 'Apa itu SL1?'),
        findsOneWidget);

    // Cari di obrolan sits in the ⋮ menu, so the subtitle has room.
    await tester.tap(find.byTooltip('Lainnya'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cari di obrolan'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Cari di obrolan…'), 'sl1');
    await tester.pumpAndSettle();
    // Two bubbles hold it; the newest is shown first.
    expect(find.text('1/2'), findsOneWidget);
    await tester.tap(find.byTooltip('Lebih lama'));
    await tester.pumpAndSettle();
    expect(find.text('2/2'), findsOneWidget);

    await tester.tap(find.byTooltip('Tutup pencarian'));
    await tester.pumpAndSettle();
    expect(find.text('Teman diskusi masalah teknismu :)'), findsOneWidget);

    // Mode belajar: a line across the chat and the tutor's opening question.
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Mode belajar'), findsOneWidget);
    expect(find.text('Socratic style tutor aktif'), findsOneWidget);
    expect(find.text(AiChat.openingQuestion), findsOneWidget);
    expect(find.text('Petunjuk'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Tulis jawabanmu…'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Socratic style tutor tidak aktif'), findsOneWidget);
    expect(find.text('Petunjuk'), findsNothing);
    expect(find.text('Teman diskusi masalah teknismu :)'), findsOneWidget);
    root.deleteSync(recursive: true);
  });
}
