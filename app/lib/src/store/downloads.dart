part of '../store.dart';

/// Downloading manuals: one or many, pause, cancel, resume, retry,
/// delete, and reading byte ranges of a manual that is read online.
extension AppStoreDownloads on AppStore {
  /// Bytes [start] to [end] (exclusive) of [f]'s PDF from the server, for a
  /// manual that is not on the phone.
  Future<Uint8List> fetchPdfRange(ManualFile f, int start, int end) async {
    final response = await _client
        // v (the file's version) lets the server answer from its cache
        // without first checking the bucket.
        .get(
          _url(f.pdf.path).replace(queryParameters: {'v': f.pdf.sha256.substring(0, 12)}),
          headers: {'Range': 'bytes=$start-${end - 1}'},
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 206 && response.bodyBytes.length == end - start) return response.bodyBytes;
    throw HttpException('HTTP ${response.statusCode} untuk ${f.pdf.path}');
  }

  int get usedBytes => local.values.fold(0, (sum, m) => sum + m.file.downloadSize);

  Future<void> download(ManualFile file, {required String unitName}) async {
    if (downloads.containsKey(file.key)) return;
    final progress = DownloadProgress(file.downloadSize);
    downloads[file.key] = progress;
    _changed();
    final targets = {file.index: indexPath(file), file.pdf: pdfPath(file)};
    // Keeps the app alive with a notification while it downloads, so moving
    // to another app does not stop it.
    if (downloads.length == 1) unawaited(KeepAlive.start('Mengunduh manual'));
    try {
      var done = 0;
      for (final e in targets.entries) {
        await _fetchRetrying(e.key, e.value, progress, done);
        done += e.key.size;
      }
      // Swap both in only once both arrived intact, so an update that fails
      // halfway leaves the old version usable.
      for (final target in targets.values) {
        await File('$target.part').rename(target);
        await _deleteIfExists(File('$target.part.sha'));
      }
      local[file.key] = LocalManual(file: file, unitName: unitName);
      seenKeys.add(file.key);
      usage.downloaded(file);
      await _save();
    } on DownloadCancelled {
      // Cancelled on purpose: free the space. Paused keeps the parts.
      if (!progress.paused) {
        for (final target in targets.values) {
          await _deleteIfExists(File('$target.part'));
          await _deleteIfExists(File('$target.part.sha'));
        }
      }
    } on SocketException {
      throw DownloadInterrupted();
    } on HandshakeException {
      throw DownloadInterrupted();
    } on TimeoutException {
      throw DownloadInterrupted();
    } on http.ClientException {
      throw DownloadInterrupted();
    } finally {
      downloads.remove(file.key);
      if (downloads.isEmpty) unawaited(KeepAlive.stop());
      _changed();
    }
  }

  /// Downloads [files] one after another. Stops at the first one that does
  /// not finish (paused, cancelled or failed), so the rest wait for the
  /// mechanic instead of filling the phone on a bad signal.
  Future<void> downloadAll(List<ManualFile> files, {required String unitName}) async {
    final todo = [for (final f in files) if (!isDownloaded(f.key) && !downloadQueue.contains(f.key)) f];
    if (todo.isEmpty) return;
    downloadQueue.addAll(todo.map((f) => f.key));
    _changed();
    try {
      for (final f in todo) {
        if (!downloadQueue.contains(f.key)) break;
        // Its own Unduh button may have started it already.
        while (downloads.containsKey(f.key)) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
        if (isDownloaded(f.key)) {
          downloadQueue.remove(f.key);
          continue;
        }
        await download(catalog.file(f.key) ?? f, unitName: unitName);
        if (!isDownloaded(f.key)) break;
        downloadQueue.remove(f.key);
        _changed();
      }
    } finally {
      downloadQueue.removeAll(todo.map((f) => f.key));
      _changed();
    }
  }

  /// [_fetch], continuing from what arrived when the connection drops (a
  /// phone switching networks or waking up), before giving up.
  Future<void> _fetchRetrying(RemoteFile remote, String target, DownloadProgress progress, int done) async {
    for (var attempt = 0;; attempt++) {
      progress.received = done;
      try {
        return await _fetch(remote, target, progress);
      } on Exception catch (e) {
        final network = e is SocketException ||
            e is HandshakeException ||
            e is TimeoutException ||
            e is http.ClientException;
        if (!network || attempt >= AppStore.retryDelays.length) rethrow;
        Diagnostics.log('download ${remote.path}: $e, retry ${attempt + 1}');
        final until = DateTime.now().add(AppStore.retryDelays[attempt]);
        while (DateTime.now().isBefore(until)) {
          if (progress.cancelled) throw DownloadCancelled();
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
    }
  }

  /// Stops a download but keeps what arrived, to continue later.
  void pauseDownload(String key) {
    final progress = downloads[key];
    if (progress == null) return;
    progress
      ..paused = true
      ..cancelled = true;
    _changed();
  }

  void cancelDownload(String key) {
    downloads[key]?.cancelled = true;
    _changed();
  }

  /// Bytes already downloaded for [file] by an interrupted download.
  int partialBytes(ManualFile file) {
    var total = 0;
    for (final (remote, target) in [(file.index, indexPath(file)), (file.pdf, pdfPath(file))]) {
      final part = File('$target.part');
      final tag = File('$target.part.sha');
      if (part.existsSync() && tag.existsSync() && tag.readAsStringSync() == remote.sha256) {
        total += part.lengthSync();
      }
    }
    return total;
  }

  /// Downloads [remote] to `<target>.part` and checks its sha256. A `.part`
  /// left by an interrupted try of the same version (recorded in
  /// `<target>.part.sha`) is continued with an HTTP Range request.
  Future<void> _fetch(RemoteFile remote, String target, DownloadProgress progress) async {
    await Directory(p.dirname(target)).create(recursive: true);
    final part = File('$target.part');
    final tag = File('$target.part.sha');
    var have = 0;
    if (await part.exists()) {
      final sameVersion = await tag.exists() && await tag.readAsString() == remote.sha256;
      have = sameVersion ? await part.length() : 0;
      if (!sameVersion || have > remote.size) {
        await part.delete();
        have = 0;
      }
    }
    await tag.writeAsString(remote.sha256);
    progress.received += have;
    _changed();

    if (have < remote.size) {
      final request = http.Request('GET', _url(remote.path));
      if (have > 0) request.headers['Range'] = 'bytes=$have-';
      final response = await _client.send(request).timeout(const Duration(seconds: 30));
      final IOSink sink;
      if (have > 0 && response.statusCode == 206) {
        sink = part.openWrite(mode: FileMode.append);
      } else if (response.statusCode == 200) {
        // The server sent the whole file: start over.
        progress.received -= have;
        sink = part.openWrite();
      } else {
        throw HttpException('HTTP ${response.statusCode} untuk ${remote.path}');
      }
      var lastNotify = DateTime.now();
      try {
        // A dropped connection can stall without an error; treat 30 s of
        // silence as an interruption.
        await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
          if (progress.cancelled) throw DownloadCancelled();
          sink.add(chunk);
          progress.received += chunk.length;
          if (DateTime.now().difference(lastNotify) > const Duration(milliseconds: 150)) {
            lastNotify = DateTime.now();
            _changed();
          }
        }
      } finally {
        await sink.close().catchError((_) {});
      }
    }

    final path = part.path;
    final digest = await Isolate.run(() => sha256.bind(File(path).openRead()).first);
    if (digest.toString() != remote.sha256) {
      await _deleteIfExists(part);
      await _deleteIfExists(tag);
      throw const FileSystemException('File rusak saat diunduh, coba lagi');
    }
  }

  Future<void> deleteManuals(Iterable<String> keys) async {
    for (final key in keys.toList()) {
      final m = local.remove(key);
      if (m == null) continue;
      for (final path in [pdfPath(m.file), indexPath(m.file)]) {
        final f = File(path);
        if (await f.exists()) await f.delete();
      }
      bookmarks.remove(key);
      if (lastRead?.fileKey == key) lastRead = null;
    }
    await _save();
    _changed();
  }
}
