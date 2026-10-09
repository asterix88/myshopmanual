import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'diagnostics.dart';

/// Copies of downloaded manuals in the phone's Download/MyManual folder, so
/// File Manager and WhatsApp can see them (Anas, 9 Oct 2026). The app's own
/// copy stays where it is.
class PublicDownloads extends ChangeNotifier with WidgetsBindingObserver {
  PublicDownloads._() {
    WidgetsBinding.instance.addObserver(this);
  }

  static final instance = PublicDownloads._();
  static const _channel = MethodChannel('mymanual/downloads');

  /// Saved or not, per file name; missing = not checked yet.
  final _exists = <String, bool>{};
  final _checking = <String>{};

  /// File names being copied right now.
  final saving = <String>{};

  /// "SM PC2000-11R SN30019 UP.pdf": the manual's title, safe as a file name.
  static String fileName(String title) =>
      '${title.replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim()}.pdf';

  /// Whether to offer "Simpan ke Download" for [name]: false while unknown,
  /// on phones without support (and in tests), or when the copy is there.
  bool canSave(String name) {
    final exists = _exists[name];
    if (exists == null) _check(name);
    return exists == false && !saving.contains(name);
  }

  Future<void> _check(String name) async {
    if (!_checking.add(name)) return;
    try {
      final exists = await _channel.invokeMethod<bool>('exists', {'name': name});
      // A phone without support says nothing exists but can't save either.
      final supported = await _channel.invokeMethod<bool>('supported') ?? false;
      _exists[name] = !supported || (exists ?? true);
    } on MissingPluginException {
      _exists[name] = true;
    } catch (e) {
      Diagnostics.log('downloads exists: $e');
      _exists[name] = true;
    } finally {
      _checking.remove(name);
    }
    notifyListeners();
  }

  /// Copies [path] to Download/MyManual/[name]; throws with a readable
  /// message when it fails.
  Future<void> save(String path, String name) async {
    saving.add(name);
    notifyListeners();
    try {
      await _channel.invokeMethod<void>('save', {'path': path, 'name': name});
      _exists[name] = true;
    } on PlatformException catch (e) {
      throw Exception('Gagal menyimpan ke Download: ${e.message ?? e.code}');
    } finally {
      saving.remove(name);
      notifyListeners();
    }
  }

  /// Free space on the phone's shared storage in bytes, or null if unknown.
  Future<int?> freeSpace() async {
    try {
      return await _channel.invokeMethod<int>('free');
    } catch (_) {
      return null;
    }
  }

  /// Opens the saved copy in a PDF app; false when there is none to open it.
  Future<bool> open(String name) async {
    try {
      return await _channel.invokeMethod<bool>('open', {'name': name}) ?? false;
    } catch (e) {
      Diagnostics.log('downloads open: $e');
      return false;
    }
  }

  // The user may delete the copy in File Manager: check again on return.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _exists.isNotEmpty) {
      _exists.clear();
      notifyListeners();
    }
  }
}
