part of 'main.dart';

// ---- PDF: student login cards and a class list ----
// The built-in PDF fonts only know basic Latin letters, so any other
// character is printed as '?' instead of leaving a blank box.
String _pdfSafe(String s) {
  final fixed = s
      .replaceAll('‘', "'")
      .replaceAll('’', "'")
      .replaceAll('–', '-')
      .replaceAll('—', '-');
  final b = StringBuffer();
  for (final r in fixed.runes) {
    b.writeCharCode(r <= 255 ? r : 63);
  }
  return b.toString();
}

// One card per student, two cards per row (about 10 cards on an A4 page).
Future<Uint8List> buildStudentCardsPdf({
  required String className,
  required List<StudentCred> creds,
}) async {
  final navy = pdf_lib.PdfColor.fromHex('#1F3864');
  final grey = pdf_lib.PdfColor.fromHex('#5A6478');
  final mono = pw.Font.courierBold();

  pw.Widget line(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 3),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 58,
            child: pw.Text(label,
                style: pw.TextStyle(fontSize: 9, color: grey)),
          ),
          pw.Text(value, style: pw.TextStyle(fontSize: 11.5, font: mono)),
        ],
      ),
    );
  }

  pw.Widget card(StudentCred c) {
    return pw.Container(
      width: 260,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: navy, width: 1),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('University of Swabi',
              style: pw.TextStyle(
                  fontSize: 12, fontWeight: pw.FontWeight.bold, color: navy)),
          pw.Text('SAM - Smart Attendance',
              style: pw.TextStyle(fontSize: 8, color: grey)),
          pw.SizedBox(height: 4),
          pw.Divider(color: navy, thickness: 0.6, height: 6),
          pw.Text(_pdfSafe(c.name),
              maxLines: 2,
              style:
                  pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.Text('Roll ${rollOf(c.roll)}',
              style: pw.TextStyle(fontSize: 9, color: grey)),
          pw.Text(className, style: pw.TextStyle(fontSize: 8, color: grey)),
          pw.SizedBox(height: 4),
          line('Username', c.username),
          line('Password', c.password),
          pw.SizedBox(height: 6),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Expanded(
                child: pw.Text(
                    'Open the SAM app and tap Student Login. Enter these details, or tap Scan QR code and scan the code on the right.',
                    style: pw.TextStyle(fontSize: 7.5, color: grey)),
              ),
              pw.SizedBox(width: 8),
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: studentQrPayload(c.username, c.password),
                width: 70,
                height: 70,
                padding: const pw.EdgeInsets.all(3),
                backgroundColor: pdf_lib.PdfColors.white,
                drawText: false,
              ),
            ],
          ),
        ],
      ),
    );
  }

  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: pdf_lib.PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    build: (ctx) => [
      pw.Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [for (final c in creds) card(c)],
      ),
    ],
  ));
  return doc.save();
}

// One table for the whole class (roll, name, username, password).
Future<Uint8List> buildStudentListPdf({
  required String className,
  required List<StudentCred> creds,
}) async {
  final navy = pdf_lib.PdfColor.fromHex('#1F3864');
  final grey = pdf_lib.PdfColor.fromHex('#5A6478');
  final mono = pw.Font.courierBold();

  pw.Widget cell(String t,
      {bool head = false, pw.Font? font, pw.TextAlign? align}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: pw.Text(
        t,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: head ? 9.5 : 10,
          font: font,
          fontWeight: (head && font == null) ? pw.FontWeight.bold : null,
          color: head ? pdf_lib.PdfColors.white : pdf_lib.PdfColors.black,
        ),
      ),
    );
  }

  final rows = <pw.TableRow>[
    pw.TableRow(
      repeat: true,
      decoration: pw.BoxDecoration(color: navy),
      children: [
        cell('Roll', head: true, align: pw.TextAlign.center),
        cell('Name', head: true),
        cell('Username', head: true),
        cell('Password', head: true),
      ],
    ),
    for (final c in creds)
      pw.TableRow(
        children: [
          cell(rollOf(c.roll), align: pw.TextAlign.center),
          cell(_pdfSafe(c.name)),
          cell(c.username, font: mono),
          cell(c.password, font: mono),
        ],
      ),
  ];

  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: pdf_lib.PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    build: (ctx) => [
      pw.Text('University of Swabi',
          style: pw.TextStyle(
              fontSize: 16, fontWeight: pw.FontWeight.bold, color: navy)),
      pw.SizedBox(height: 2),
      pw.Text('Student logins  |  $className',
          style: pw.TextStyle(fontSize: 10, color: grey)),
      pw.SizedBox(height: 10),
      pw.Table(
        border: pw.TableBorder.all(color: pdf_lib.PdfColors.grey500, width: 0.5),
        columnWidths: {
          0: const pw.FixedColumnWidth(36),
          1: const pw.FlexColumnWidth(3),
          2: const pw.FlexColumnWidth(2.4),
          3: const pw.FlexColumnWidth(1.6),
        },
        children: rows,
      ),
    ],
    footer: (ctx) => pw.Center(
      child: pw.Text('Keep this list private  -  page ${ctx.pageNumber}/${ctx.pagesCount}',
          style: pw.TextStyle(fontSize: 8, color: grey)),
    ),
  ));
  return doc.save();
}

// ---- Admin: create / reset student logins for one class ----
class StudentLoginsScreen extends StatefulWidget {
  final SemRef sem;
  final String semLabel;
  final String deptName;
  const StudentLoginsScreen(
      {super.key,
      required this.sem,
      required this.semLabel,
      this.deptName = ''});

  @override
  State<StudentLoginsScreen> createState() => _StudentLoginsScreenState();
}

class _StudentLoginsScreenState extends State<StudentLoginsScreen> {
  bool _loading = true;
  bool _busy = false;
  bool _autoSynced = false;
  String? _error;
  List<Map<String, String>> _students = [];
  Map<String, String> _logins = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final st = await loadSemesterStudents(widget.sem);
      var lg = await loadStudentLoginNames(widget.sem);
      // Auto sync (this section only): if some students have no login here,
      // look for their old login in another semester and move it. Quiet, once
      // per opening of this screen.
      if (!_autoSynced && st.any((x) => !lg.containsKey(x['roll']))) {
        _autoSynced = true;
        try {
          if (await adoptStudentLoginsAllSemesters(widget.sem) > 0) {
            lg = await loadStudentLoginNames(widget.sem);
          }
        } catch (e) {
          debugPrint('auto sync failed: $e');
        }
      }
      if (!mounted) return;
      setState(() {
        _students = st;
        _logins = lg;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      debugPrint('student logins load failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Could not load student logins. Internet is required. Please try again.';
      });
    }
  }

  // Builds one of the two PDFs and opens the share sheet (or downloads it on web).
  Future<void> _sharePdf(BuildContext ctx, Future<Uint8List> Function() build,
      String fileName) async {
    try {
      final bytes = await build();
      if (!ctx.mounted) return;
      const caption = 'Student logins - keep private';
      if (kIsWeb) {
        await webShareOrDownload(ctx, bytes, fileName, text: caption);
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/$fileName';
      await File(path).writeAsBytes(bytes);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(path)],
        text: caption,
      ));
    } catch (e) {
      debugPrint('student logins pdf failed: $e');
      if (ctx.mounted) {
        showSnack(ctx, 'Could not create the PDF. Please try again.',
            color: kAbsent);
      }
    }
  }

  Future<void> _showCreds(List<StudentCred> creds, {String? title}) async {
    final className =
        _pdfSafe('${widget.deptName.isNotEmpty ? widget.deptName : widget.sem.deptId} | Section ${widget.sem.section} | ${widget.semLabel}');
    final fileBase = exportFileBase(
        widget.sem, widget.semLabel, 'Student_Logins',
        deptName: widget.deptName);
    final text = StringBuffer()
      ..writeln('${widget.semLabel} • Section ${widget.sem.section}');
    for (final c in creds) {
      text.writeln(
          'Roll ${rollOf(c.roll)} | ${c.name} | Username: ${c.username} | Password: ${c.password}');
    }
    final all = text.toString();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title ??
            '${creds.length} login${creds.length == 1 ? '' : 's'} created'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'Passwords are saved on this phone. You can export the PDF again any time from the three-dot menu (top right) of this screen. To change one password, use the key icon.',
                    style: TextStyle(color: kAbsent, fontSize: 13)),
                const SizedBox(height: 12),
                SelectableText(all, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: all));
              if (ctx.mounted) showSnack(ctx, 'Copied');
            },
            child: const Text('Copy all'),
          ),
          TextButton(
            onPressed: () => _sharePdf(
                ctx,
                () => buildStudentCardsPdf(
                    className: className, creds: creds),
                '${fileBase}_Cards.pdf'),
            child: const Text('Cards PDF'),
          ),
          TextButton(
            onPressed: () => _sharePdf(
                ctx,
                () =>
                    buildStudentListPdf(className: className, creds: creds),
                '${fileBase}_List.pdf'),
            child: const Text('List PDF'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _create({Set<String>? only, bool replaceAll = false}) async {
    setState(() => _busy = true);
    try {
      final creds = await generateStudentLogins(widget.sem, onlyRolls: only);
      if (!mounted) return;
      await saveStudentPws(creds);
      if (!mounted) return;
      if (creds.isEmpty) {
        showSnack(context, 'Every student already has a login.');
      } else {
        await _showCreds(creds,
            title: replaceAll
                ? '${creds.length} password${creds.length == 1 ? '' : 's'} reset'
                : null);
      }
      await _load();
    } catch (e) {
      debugPrint('create student logins failed: $e');
      if (mounted) {
        showSnack(context,
            'Could not create logins (${e is FirebaseException ? e.code : e.runtimeType}). Check your internet and try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Brings logins of the same students from another semester to this one.
  Future<void> _adopt() async {
    setState(() => _busy = true);
    try {
      final n = await adoptStudentLoginsEverywhere();
      if (!mounted) return;
      showSnack(
          context,
          n == 0
              ? 'Everything is already synced.'
              : '$n login${n == 1 ? '' : 's'} synced everywhere.');
      await _load();
    } catch (e) {
      debugPrint('adopt student logins failed: $e');
      if (mounted) {
        showSnack(context, 'Could not sync logins. Check your internet and try again.',
            color: kAbsent);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmResetAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset all passwords?'),
        content: Text(
            'New passwords will be made for all ${_students.length} students of this class. Every old password will stop working. Students without a login will get one.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reset all')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _create(
        only: {for (final st in _students) st['roll']!}, replaceAll: true);
  }

  // One menu behind the existing header icon: sync, reset all, export PDF.
  Future<void> _openMenu() async {
    if (_busy) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.sync, color: kAccent),
              title: const Text('Sync logins (all departments)'),
              onTap: () => Navigator.pop(ctx, 'sync'),
            ),
            ListTile(
              leading: const Icon(Icons.lock_reset, color: kAccent),
              title: const Text('Reset all passwords'),
              onTap: () => Navigator.pop(ctx, 'reset'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined, color: kAccent),
              title: const Text('Export passwords PDF'),
              subtitle: const Text('Download again for this class and semester'),
              onTap: () => Navigator.pop(ctx, 'pdf'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'sync') {
      await _adopt();
    } else if (choice == 'reset') {
      if (_students.isEmpty) {
        showSnack(context, 'Add students first.');
      } else {
        await _confirmResetAll();
      }
    } else if (choice == 'pdf') {
      final saved = await loadSavedStudentPws();
      if (!mounted) return;
      final creds = <StudentCred>[];
      for (final st in _students) {
        final roll = st['roll']!;
        final username = _logins[roll];
        final pw = username == null ? null : saved[username];
        if (username != null && pw != null) {
          creds.add(StudentCred(roll, st['name'] ?? '', username, pw));
        }
      }
      if (creds.isEmpty) {
        showSnack(context,
            'No saved passwords for this class on this phone. Reset the passwords once and they will be saved here.');
      } else {
        await _showCreds(creds,
            title: '${creds.length} saved password${creds.length == 1 ? '' : 's'}');
      }
    }
  }

  Future<void> _confirmReset(String roll, String name, bool hasLogin) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(hasLogin ? 'Set a new password?' : 'Create login?'),
        content: Text(hasLogin
            ? "$name's old password will stop working."
            : 'A login will be created for $name.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue')),
        ],
      ),
    );
    if (ok == true) await _create(only: {roll});
  }

  @override
  Widget build(BuildContext context) {
    final missing =
        _students.where((st) => !_logins.containsKey(st['roll'])).length;
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: kAbsent)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  setState(() => _loading = true);
                  _load();
                },
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    } else if (_students.isEmpty) {
      body = const EmptyState(
          icon: Icons.groups_outlined, text: 'Add students first.');
    } else {
      body = ListView(
        padding: const EdgeInsets.only(top: 6, bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: GradientButton(
              label: missing == 0
                  ? 'All students have logins'
                  : 'Create $missing missing login${missing == 1 ? '' : 's'}',
              loading: _busy,
              onPressed: (_busy || missing == 0) ? null : () => _create(),
            ),
          ),
          for (final st in _students)
            AppCard(
              float: false,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              child: Row(
                children: [
                  RollBadge(roll: st['roll']!),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StudentNameBlock(
                      name: st['name'] ?? '',
                      extra: _logins[st['roll']] ?? 'No login yet',
                      extraColor:
                          _logins.containsKey(st['roll']) ? kAccent : kAbsent,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.vpn_key_outlined, color: kAccent),
                    tooltip: _logins.containsKey(st['roll'])
                        ? 'Set a new password'
                        : 'Create login',
                    onPressed: _busy
                        ? null
                        : () => _confirmReset(st['roll']!, st['name'] ?? '',
                            _logins.containsKey(st['roll'])),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    return Scaffold(
      appBar: headerAppBar(
        title: 'Student logins',
        subtitle: '${widget.semLabel} • Section ${widget.sem.section}',
        actions: [
          HeaderTile(
            icon: Icons.more_vert,
            tooltip: 'Sync, reset all passwords, export PDF',
            onTap: _openMenu,
          ),
        ],
      ),
      body: body,
    );
  }
}
