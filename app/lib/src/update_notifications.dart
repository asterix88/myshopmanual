import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:workmanager/workmanager.dart';

import 'diagnostics.dart';
import 'models.dart';
import 'store.dart';

/// Every few hours, with internet, the phone asks the server for its catalog
/// and shows a notification when manuals were added or got a new version,
/// even while the app is closed. Each change is announced once.
const _task = 'manual-updates';
const _channelId = 'manual-updates';
const updatesPayload = 'updates';

final _notifications = FlutterLocalNotificationsPlugin();

/// Called once when the app starts: sets up notifications, asks for
/// permission (Android 13+) and schedules the background check.
/// [onOpenUpdates] runs when the user taps the notification.
Future<void> startUpdateNotifications({required void Function() onOpenUpdates}) async {
  try {
    await _notifications.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_notification')),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload == updatesPayload) onOpenUpdates();
      },
    );
    final launch = await _notifications.getNotificationAppLaunchDetails();
    if ((launch?.didNotificationLaunchApp ?? false) &&
        launch?.notificationResponse?.payload == updatesPayload) {
      onOpenUpdates();
    }
    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await Workmanager().initialize(updateCheckDispatcher);
    await Workmanager().registerPeriodicTask(
      _task,
      _task,
      frequency: const Duration(hours: 3),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  } on Object catch (e) {
    // The app works without notifications.
    Diagnostics.log('update notifications not started: $e');
  }
}

/// Runs in the background, without the app's screens.
@pragma('vm:entry-point')
void updateCheckDispatcher() {
  Workmanager().executeTask((task, input) async {
    DartPluginRegistrant.ensureInitialized();
    try {
      final news = await updatesToAnnounce();
      if (news.isNotEmpty) await _show(news);
    } on Object {
      // No signal or server trouble: the next check tries again.
    }
    return true;
  });
}

/// Added or updated manuals on the server that the user has neither looked
/// at in the app (bell) nor been notified about. Remembers them as notified.
/// Reads the app's state but never writes it, so it can't clash with the
/// app if both run at once.
Future<List<ManualUpdate>> updatesToAnnounce({Directory? root, http.Client? client}) async {
  final store = await AppStore.open(root: root, client: client);
  try {
    if (!store.seenInitialized) return const [];
    final remote = await store.fetchCatalog();
    final notifiedFile = File(p.join(store.root.path, 'notified.json'));
    final notified = <String>{};
    if (await notifiedFile.exists()) {
      try {
        notified.addAll((jsonDecode(await notifiedFile.readAsString()) as List).cast<String>());
      } on FormatException {
        // Start over; at worst a change is announced twice.
      }
    }
    final news = [
      for (final u in computeUpdates(remote: remote, local: store.local, seenKeys: store.seenKeys))
        if (u.kind != UpdateKind.withdrawn && !store.seenKeys.contains(u.seenKey) && !notified.contains(u.seenKey)) u,
    ];
    if (news.isNotEmpty) {
      final keep = [...notified, ...news.map((u) => u.seenKey)];
      await notifiedFile.writeAsString(jsonEncode(keep.skip(keep.length > 1000 ? keep.length - 1000 : 0).toList()));
    }
    return news;
  } finally {
    store.dispose();
  }
}

/// The notification's title and text for [news].
(String, String) updateMessage(List<ManualUpdate> news) {
  String line(ManualUpdate u) =>
      '${u.kind == UpdateKind.newVersion ? 'Versi baru' : 'Baru'}: ${u.file.title} (${u.unitName})';
  if (news.length == 1) return ('Ada update manual', line(news.single));
  final shown = news.take(5).map(line).join('\n');
  final more = news.length > 5 ? '\n+${news.length - 5} lainnya' : '';
  return ('${news.length} update manual', '$shown$more');
}

Future<void> _show(List<ManualUpdate> news) async {
  await _notifications.initialize(
    settings: const InitializationSettings(android: AndroidInitializationSettings('ic_notification')),
  );
  final (title, body) = updateMessage(news);
  await _notifications.show(
    id: 1,
    title: title,
    body: body,
    payload: updatesPayload,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Update manual',
        channelDescription: 'Manual baru atau versi baru di server',
        importance: Importance.defaultImportance,
        styleInformation: BigTextStyleInformation(body),
        color: const Color(0xFF1E3A64),
      ),
    ),
  );
}
