/// Data shapes shared with tools/build_packages.py (catalog.json, schema 1).
library;

enum DocType {
  shopManual('shop_manual', 'Shop Manual'),
  omm('omm', 'OMM'),
  partsbook('partsbook', 'Partsbook'),
  other('other', 'Lainnya');

  const DocType(this.id, this.label);

  final String id;
  final String label;

  static DocType parse(String? id) =>
      values.firstWhere((t) => t.id == id, orElse: () => DocType.other);
}

class RemoteFile {
  const RemoteFile({required this.path, required this.size, required this.sha256});

  factory RemoteFile.fromJson(Map<String, dynamic> json) => RemoteFile(
        path: json['path'] as String,
        size: json['size'] as int,
        sha256: json['sha256'] as String,
      );

  final String path;
  final int size;
  final String sha256;

  Map<String, dynamic> toJson() => {'path': path, 'size': size, 'sha256': sha256};
}

class ManualFile {
  const ManualFile({
    required this.unitId,
    required this.id,
    required this.title,
    required this.type,
    required this.pages,
    required this.searchable,
    required this.pdf,
    required this.index,
    required this.updatedAt,
  });

  factory ManualFile.fromJson(String unitId, Map<String, dynamic> json) => ManualFile(
        unitId: unitId,
        id: json['id'] as String,
        title: json['title'] as String,
        type: DocType.parse(json['type'] as String?),
        pages: json['pages'] as int,
        searchable: json['searchable'] as bool? ?? true,
        pdf: RemoteFile.fromJson(json['pdf'] as Map<String, dynamic>),
        index: RemoteFile.fromJson(json['index'] as Map<String, dynamic>),
        updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
      );

  final String unitId;
  final String id;
  final String title;
  final DocType type;
  final int pages;
  final bool searchable;
  final RemoteFile pdf;
  final RemoteFile index;
  final DateTime? updatedAt;

  /// Unique across the whole catalog.
  String get key => '$unitId/$id';

  int get downloadSize => pdf.size + index.size;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': type.id,
        'pages': pages,
        'searchable': searchable,
        'pdf': pdf.toJson(),
        'index': index.toJson(),
        'updated_at': updatedAt?.toIso8601String(),
      };
}

class Unit {
  const Unit({required this.id, required this.name, required this.kind, required this.files});

  factory Unit.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    return Unit(
      id: id,
      name: json['name'] as String? ?? id,
      kind: json['kind'] as String? ?? '',
      files: [
        for (final f in json['files'] as List) ManualFile.fromJson(id, f as Map<String, dynamic>),
      ],
    );
  }

  final String id;
  final String name;
  final String kind;
  final List<ManualFile> files;

  int get totalSize => files.fold(0, (sum, f) => sum + f.downloadSize);
}

class Catalog {
  const Catalog({required this.generatedAt, required this.units});

  factory Catalog.fromJson(Map<String, dynamic> json) => Catalog(
        generatedAt: DateTime.tryParse(json['generated_at'] as String? ?? ''),
        units: [for (final u in json['units'] as List) Unit.fromJson(u as Map<String, dynamic>)],
      );

  static const empty = Catalog(generatedAt: null, units: []);

  final DateTime? generatedAt;
  final List<Unit> units;

  Iterable<ManualFile> get files => units.expand((u) => u.files);

  ManualFile? file(String key) {
    for (final f in files) {
      if (f.key == key) return f;
    }
    return null;
  }
}

/// A manual stored on the phone, as recorded when it was downloaded.
class LocalManual {
  const LocalManual({required this.file, required this.unitName});

  factory LocalManual.fromJson(Map<String, dynamic> json) => LocalManual(
        file: ManualFile.fromJson(json['unit_id'] as String, json['file'] as Map<String, dynamic>),
        unitName: json['unit_name'] as String,
      );

  final ManualFile file;
  final String unitName;

  Map<String, dynamic> toJson() => {
        'unit_id': file.unitId,
        'unit_name': unitName,
        'file': file.toJson(),
      };
}

class LastRead {
  const LastRead({required this.fileKey, required this.page, this.section});

  factory LastRead.fromJson(Map<String, dynamic> json) => LastRead(
        fileKey: json['file'] as String,
        page: json['page'] as int,
        section: json['section'] as String?,
      );

  final String fileKey;
  final int page;
  final String? section;

  Map<String, dynamic> toJson() => {'file': fileKey, 'page': page, 'section': section};
}

enum UpdateKind { added, newVersion, withdrawn }

/// One entry on the "Update manual" screen.
class ManualUpdate {
  const ManualUpdate({required this.kind, required this.file, required this.unitName});

  final UpdateKind kind;
  final ManualFile file;
  final String unitName;
}

/// Compares the server catalog with what is on the phone.
///
/// [seenKeys] are files the user has already been told about, so a manual
/// that was new last week does not keep the bell lit forever.
List<ManualUpdate> computeUpdates({
  required Catalog remote,
  required Map<String, LocalManual> local,
  required Set<String> seenKeys,
}) {
  final updates = <ManualUpdate>[];
  final remoteKeys = <String>{};
  for (final unit in remote.units) {
    for (final file in unit.files) {
      remoteKeys.add(file.key);
      final mine = local[file.key];
      if (mine == null) {
        if (!seenKeys.contains(file.key)) {
          updates.add(ManualUpdate(kind: UpdateKind.added, file: file, unitName: unit.name));
        }
      } else if (mine.file.pdf.sha256 != file.pdf.sha256 ||
          mine.file.index.sha256 != file.index.sha256) {
        updates.add(ManualUpdate(kind: UpdateKind.newVersion, file: file, unitName: unit.name));
      }
    }
  }
  for (final mine in local.values) {
    if (!remoteKeys.contains(mine.file.key)) {
      updates.add(ManualUpdate(kind: UpdateKind.withdrawn, file: mine.file, unitName: mine.unitName));
    }
  }
  return updates;
}

String formatSize(int bytes) {
  if (bytes >= 1000 * 1000) return '${(bytes / 1e6).toStringAsFixed(bytes >= 1e7 ? 0 : 1)} MB';
  if (bytes >= 1000) return '${(bytes / 1e3).round()} KB';
  return '$bytes B';
}
