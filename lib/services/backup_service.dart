part of '../main.dart';

// Backup and restore.

// ---------------------------------------------------------------------------
// Backup & restore
// Backup: reads every Firestore document into one JSON file (saved on the phone
// or downloaded on web). Restore: writes each document back to its path. It never
// deletes anything, and running it twice is harmless.
// ---------------------------------------------------------------------------
const String kBackupFormat = 'attendance_backup_v1';
const List<String> _kBackupRoots = ['departments', 'teachers', 'settings', 'meta'];
const List<String> _kBackupGroups = [
  'sections',
  'semesters',
  'students',
  'subjects',
  'overrides',
  'dates',
  'claims',
];

dynamic _bkEncode(dynamic v) {
  if (v is Timestamp) {
    return {'__t': 'ts', 's': v.seconds, 'n': v.nanoseconds};
  }
  if (v is GeoPoint) {
    return {'__t': 'geo', 'lat': v.latitude, 'lng': v.longitude};
  }
  if (v is DocumentReference) return {'__t': 'ref', 'p': v.path};
  if (v is Blob) return {'__t': 'bytes', 'b': base64Encode(v.bytes)};
  if (v is Map) {
    return v.map((k, val) => MapEntry(k.toString(), _bkEncode(val)));
  }
  if (v is Iterable) return v.map(_bkEncode).toList();
  return v;
}

dynamic _bkDecode(dynamic v) {
  if (v is Map) {
    final t = v['__t'];
    if (t == 'ts') return Timestamp(v['s'] as int, v['n'] as int);
    if (t == 'geo') {
      return GeoPoint((v['lat'] as num).toDouble(), (v['lng'] as num).toDouble());
    }
    if (t == 'ref') return FirebaseFirestore.instance.doc(v['p'] as String);
    if (t == 'bytes') return Blob(base64Decode(v['b'] as String));
    return v.map((k, val) => MapEntry(k.toString(), _bkDecode(val)));
  }
  if (v is List) return v.map(_bkDecode).toList();
  return v;
}

Future<Map<String, dynamic>> _collectBackup() async {
  final fs = FirebaseFirestore.instance;
  const t = Duration(seconds: 60);
  final docs = <String, dynamic>{};
  void addAll(QuerySnapshot<Map<String, dynamic>> snap) {
    // A cached answer would give an incomplete backup, so refuse it.
    if (snap.metadata.isFromCache) throw Exception('Server not reachable');
    for (final d in snap.docs) {
      docs[d.reference.path] = _bkEncode(d.data());
    }
  }

  for (final c in _kBackupRoots) {
    addAll(await fs.collection(c).get().timeout(t));
  }
  for (final g in _kBackupGroups) {
    addAll(await fs.collectionGroup(g).get().timeout(t));
  }
  return {
    'format': kBackupFormat,
    'created': DateTime.now().toIso8601String(),
    'count': docs.length,
    'docs': docs,
  };
}

// Creates the backup file and saves/shares it. Returns the number of records.
Future<int> createBackupFile() async {
  final data = await _collectBackup();
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
  final name =
      'attendance_backup_${DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now())}.json';
  if (kIsWeb) {
    downloadBytes(bytes, name);
    return data['count'] as int;
  }
  final dir = await getApplicationDocumentsDirectory();
  final path = '${dir.path}/$name';
  await File(path).writeAsBytes(bytes);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(path)],
    text: 'Attendance backup',
  ));
  return data['count'] as int;
}

Future<void> runBackupWithUi(BuildContext context) async {
  if ((await _netState()) != _Net.reachable) {
    if (!context.mounted) return;
    showSnack(context, 'Internet is required to take a backup.',
        color: kAbsent);
    return;
  }
  if (context.mounted) showSnack(context, 'Preparing backup...');
  try {
    final n = await createBackupFile();
    if (context.mounted) showSnack(context, 'Backup ready ($n records)');
  } catch (e) {
    debugPrint('Backup error: $e');
    if (context.mounted) {
      showSnack(context, 'Backup failed. Check your internet and try again.',
          color: kAbsent);
    }
  }
}

bool _bkPathOk(String path) {
  final parts = path.split('/');
  return parts.length.isEven &&
      parts.every((p) => p.isNotEmpty) &&
      _kBackupRoots.contains(parts.first);
}

Future<void> restoreFromBackupUi(BuildContext context) async {
  PlatformFile? f;
  try {
    f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
  } catch (e) {
    debugPrint('File picker error: $e');
    if (context.mounted) {
      showSnack(context, 'Could not open the file picker.', color: kAbsent);
    }
    return;
  }
  if (f == null) return;

  Map<String, dynamic> docs;
  String created = '';
  try {
    final bytes = await f.readAsBytes();
    final m = jsonDecode(utf8.decode(bytes));
    if (m is! Map || m['format'] != kBackupFormat || m['docs'] is! Map) {
      throw const FormatException('not a backup');
    }
    docs = Map<String, dynamic>.from(m['docs'] as Map);
    created = (m['created'] ?? '').toString();
    if (docs.keys.any((p) => !_bkPathOk(p))) {
      throw const FormatException('bad path');
    }
  } catch (_) {
    if (context.mounted) {
      showSnack(context, 'This is not a valid backup file.', color: kAbsent);
    }
    return;
  }
  if (!context.mounted) return;

  String when = created;
  try {
    when = DateFormat('d MMM yyyy, h:mm a').format(DateTime.parse(created));
  } catch (_) {}

  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Restore this backup?'),
      content: Text(
        'Backup taken: $when\nRecords in file: ${docs.length}\n\n'
        'Every record in the file is written back to the server and replaces the current version of that record. '
        'Records that are not in the file are not deleted. Internet is required.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Restore'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  if ((await _netState()) != _Net.reachable) {
    if (context.mounted) {
      showSnack(context, 'Internet is required to restore.', color: kAbsent);
    }
    return;
  }
  if (!context.mounted) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(
        children: [
          SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 16),
          Text('Restoring...'),
        ],
      ),
    ),
  );

  bool success = false;
  try {
    final fs = FirebaseFirestore.instance;
    final entries = docs.entries.toList();
    for (int i = 0; i < entries.length; i += 400) {
      final batch = fs.batch();
      for (final e in entries.skip(i).take(400)) {
        batch.set(fs.doc(e.key),
            Map<String, dynamic>.from(_bkDecode(e.value) as Map));
      }
      await batch.commit().timeout(const Duration(seconds: 30));
    }
    success = true;
    await syncLocalDbIfStale(force: true);
  } catch (e) {
    debugPrint('Restore error: $e');
  }

  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
  showSnack(
    context,
    success
        ? 'Restore complete'
        : 'Restore did not finish. Check your internet and run it again.',
    color: success ? null : kAbsent,
  );
}
