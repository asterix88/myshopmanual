import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymanual/main.dart';
import 'package:mymanual/src/screens/chat_screen.dart';
import 'package:mymanual/src/screens/search_screen.dart';
import 'package:mymanual/src/store.dart';

import 'store_test.dart' show fixtureServer;

double shownOpacity(WidgetTester tester, Type screen) => tester
    .renderObject<RenderAnimatedOpacity>(
        find.ancestor(of: find.byType(screen), matching: find.byType(AnimatedOpacity)))
    .opacity
    .value;

void main() {
  testWidgets('leaving a tab fades it out, so the chosen tab shows', (tester) async {
    late AppStore store;
    final root = Directory.systemTemp.createTempSync('shell');
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: fixtureServer());
    });
    await tester.pumpWidget(MyManualApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('nyel AI').last);
    await tester.pumpAndSettle();
    expect(shownOpacity(tester, ChatScreen), 1);

    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    expect(shownOpacity(tester, ChatScreen), 0);

    await tester.tap(find.text('Cari').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    expect(shownOpacity(tester, SearchScreen), 0);
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
    expect(shownOpacity(tester, SearchScreen), 0);

    // On Home the app no longer holds back, so Android closes it.
    expect(await tester.binding.handlePopRoute(), isFalse);
    expect(find.byType(AlertDialog), findsNothing);
    root.deleteSync(recursive: true);
  });

  testWidgets('Enter on the keyboard starts a new line in nyel AI', (tester) async {
    late AppStore store;
    final root = Directory.systemTemp.createTempSync('shell');
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: fixtureServer());
    });
    await tester.pumpWidget(MyManualApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('nyel AI').last);
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
    await tester.tap(find.text('nyel AI').last);
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

    await tester.tap(find.byTooltip('Cari di obrolan'));
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
    root.deleteSync(recursive: true);
  });
}
