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

  /// The catalog's type, except that a title starting with "PB" is a
  /// partsbook even in catalogs built before the pipeline knew that.
  static DocType of(String? id, String title) {
    final type = parse(id);
    if (type == DocType.other && RegExp(r'^PB\b', caseSensitive: false).hasMatch(title.trim())) {
      return DocType.partsbook;
    }
    return type;
  }

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
    this.group = '',
  });

  factory ManualFile.fromJson(String unitId, Map<String, dynamic> json) => ManualFile(
        unitId: unitId,
        id: json['id'] as String,
        title: json['title'] as String,
        type: DocType.of(json['type'] as String?, json['title'] as String),
        pages: json['pages'] as int,
        searchable: json['searchable'] as bool? ?? true,
        pdf: RemoteFile.fromJson(json['pdf'] as Map<String, dynamic>),
        index: RemoteFile.fromJson(json['index'] as Map<String, dynamic>),
        updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
        group: json['group'] as String? ?? '',
      );

  /// Order of files on a unit page: subfolders first, then the files placed
  /// directly in the unit folder; inside each, Shop Manual, OMM, Partsbook,
  /// then the rest, by title.
  static int pageOrder(ManualFile a, ManualFile b) {
    if (a.group.isEmpty != b.group.isEmpty) return a.group.isEmpty ? 1 : -1;
    final byGroup = a.group.toLowerCase().compareTo(b.group.toLowerCase());
    if (byGroup != 0) return byGroup;
    final byType = a.type.index.compareTo(b.type.index);
    if (byType != 0) return byType;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  final String unitId;
  final String id;
  final String title;
  final DocType type;
  final int pages;
  final bool searchable;
  final RemoteFile pdf;
  final RemoteFile index;
  final DateTime? updatedAt;

  /// The subfolder of the unit folder the PDF came from (e.g. "System
  /// Diagram"), shown as a heading on the unit page; empty for files placed
  /// directly in the unit folder.
  final String group;

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
        if (group.isNotEmpty) 'group': group,
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

  /// Rough machine size from the model code, used to list the biggest
  /// machines first: PC2000, PC1250, CAT395, PC500, PC210; D375, D155, D85.
  /// Komatsu-style excavator codes are tonnes x 10 (PC1250 = 125 t), CAT 3xx
  /// ends in the tonnes (CAT395 = 95 t); dozer numbers already grow with size.
  double get sizeClass {
    final code = id.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final cat = RegExp(r'^CAT3(\d\d)').firstMatch(code);
    if (cat != null) return double.parse(cat[1]!);
    final digits = RegExp(r'\d+').firstMatch(code);
    if (digits == null) return 0;
    final n = double.parse(digits[0]!);
    return code.startsWith('D') ? n : n / 10;
  }

  int get totalSize => files.fold(0, (sum, f) => sum + f.downloadSize);

  Machine get machine => Machine.of(this);
}

/// The kind of machine a unit is, shown as a folder on the home screen.
enum Machine {
  excavator('EXCAVATOR'),
  bulldozer('BULLDOZER'),
  other('LAINNYA');

  const Machine(this.label);

  final String label;

  /// Uses the unit's `kind` from unit.json when set, otherwise guesses from
  /// the model code: PC, CAT, ZX, EX are excavators; D85, D155 are dozers.
  static Machine of(Unit unit) {
    final kind = unit.kind.toLowerCase();
    if (kind.contains('excavator')) return Machine.excavator;
    if (kind.contains('dozer')) return Machine.bulldozer;
    final code = unit.id.toUpperCase();
    if (RegExp(r'^(PC|CAT|ZX|EX)').hasMatch(code)) return Machine.excavator;
    if (RegExp(r'^D\d').hasMatch(code)) return Machine.bulldozer;
    return Machine.other;
  }
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

  /// Remembered once the user has opened the update list, so the bell only
  /// counts changes they have not looked at yet.
  String get seenKey => switch (kind) {
        UpdateKind.added => file.key,
        UpdateKind.newVersion => '${file.key}@${file.pdf.sha256}/${file.index.sha256}',
        UpdateKind.withdrawn => 'withdrawn:${file.key}',
      };
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
