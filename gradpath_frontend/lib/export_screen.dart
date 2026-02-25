import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'gradpath_config.dart';
import 'gradpath_theme.dart';

// ────────────────────────────────────────────────────────────
// ExportScreen — Academic Path Summary / Advisor Ready Export
// Used inside GradPathShell (no Scaffold of its own)
// ────────────────────────────────────────────────────────────

class ExportScreen extends StatefulWidget {
  const ExportScreen({
    super.key,
    this.studentId,
    this.planDetail,
    this.studentName,
  });

  final int? studentId;
  final Map<String, dynamic>? planDetail;
  final String? studentName;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  Map<String, dynamic>? _freshPlan;
  int? _resolvedPlanId;
  String _gpa = '—';
  int _completedCredits = 0;
  List<Map<String, dynamic>> _risks = [];
  bool _loading = true;
  String? _schoolStudentId; // school-issued ID e.g. "104778"
  String? _programName; // major / degree program
  // WIP (current in-progress) term from transcript, shown at top of roadmap
  Map<String, dynamic>? _wipTerm;

  static const int _degreeCredits = 124;

  // ── Current season helper (mirrors whatif_screen) ──────────
  static int _currentTermOrder() {
    final m = DateTime.now().month;
    if (m >= 1 && m <= 5) return 1; // spring
    if (m >= 6 && m <= 7) return 2; // summer
    return 3; // fall
  }

  static int _termOrder(String name) {
    final n = name.toLowerCase();
    if (n.contains('spring')) return 1;
    if (n.contains('summer')) return 2;
    return 3; // fall / default
  }

  List<Map<String, dynamic>> _filterFutureTerms(
      List<Map<String, dynamic>> terms) {
    final now = DateTime.now();
    final curYear = now.year;
    final curOrder = _currentTermOrder();
    return terms.where((t) {
      final name = (t['term_name'] as String? ?? '');
      final yearMatch = RegExp(r'\d{4}').firstMatch(name);
      if (yearMatch == null) return true;
      final y = int.tryParse(yearMatch.group(0)!) ?? curYear;
      if (y > curYear) return true;
      if (y < curYear) return false;
      return _termOrder(name) >= curOrder;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    const base = GradPathConfig.backendBaseUrl;
    final sid = widget.studentId ?? (widget.planDetail?['student_id'] as int?);
    Map<String, dynamic>? plan = widget.planDetail;
    int? planId = plan?['id'] as int?;

    // ── Step 1: resolve plan — always fetch fresh from backend ──
    if (sid != null) {
      try {
        final res = await http
            .get(Uri.parse('$base/api/students/$sid'))
            .timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          // Capture school-issued student ID and program name
          _schoolStudentId = body['student_id'] as String?;
          final rawMajor = body['major'] as String?;
          // Strip accidental trailing punctuation from major
          _programName = rawMajor?.replaceAll(RegExp(r'[\.\s]+$'), '').trim();
          final latestId = body['plan_id'] as int?;
          final targetId = latestId ?? planId;
          if (targetId != null) {
            // Always fetch fresh plan to ensure up-to-date data
            final pRes = await http
                .get(Uri.parse('$base/api/plans/$targetId'))
                .timeout(const Duration(seconds: 10));
            if (pRes.statusCode == 200) {
              plan = jsonDecode(pRes.body) as Map<String, dynamic>;
              planId = targetId;
            }
          }
        }
      } catch (_) {}
    }

    // ── Step 2: GPA ─────────────────────────────────────────────
    if (sid != null) {
      try {
        final res = await http
            .get(Uri.parse('$base/api/students/$sid/gpa'))
            .timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body);
          final raw = body['gpa'] ?? body['cumulative_gpa'];
          if (raw != null && raw.toString() != 'null') {
            final d = double.tryParse(raw.toString());
            if (d != null && d > 0) {
              _gpa = d.toStringAsFixed(2);
            }
          }
        }
      } catch (_) {}
    }

    // ── Step 3: completed credits + WIP term from transcript ────
    if (sid != null) {
      try {
        final res = await http
            .get(Uri.parse('$base/api/transcripts/$sid'))
            .timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          final courses = (body['courses'] as List?) ?? [];
          int sum = 0;
          final Map<String, List<Map<String, dynamic>>> wipGrouped = {};
          for (final c in courses) {
            if (c is! Map) continue;
            final grade = (c['grade'] as String?)?.toUpperCase();
            final term = c['term'] as String?;
            if (grade != null && grade != 'WIP') {
              sum += ((c['credits'] as num?)?.toInt() ?? 3);
            } else if (grade == 'WIP' && term != null) {
              wipGrouped.putIfAbsent(term, () => []).add({
                'course_code': c['course_code'],
                'course_title': c['course_title'],
                'credits': c['credits'],
              });
            }
          }
          _completedCredits = sum;
          // Build WIP pseudo-term for roadmap display
          if (wipGrouped.isNotEmpty) {
            // Use the last WIP term chronologically
            int termKey(String t) {
              final p = t.trim().split(RegExp(r'\s+'));
              if (p.length < 2) return 0;
              final y = int.tryParse(p.last) ?? 0;
              final s = switch (p.first.toLowerCase()) {
                'spring' => 1,
                'summer' => 2,
                'fall' => 3,
                _ => 0
              };
              return y * 10 + s;
            }

            final wipName = wipGrouped.keys
                .reduce((a, b) => termKey(a) >= termKey(b) ? a : b);
            final wipItems = wipGrouped[wipName]!;
            _wipTerm = {
              'term_name': wipName,
              'credits': wipItems.fold<int>(
                  0, (s, c) => s + ((c['credits'] as num?)?.toInt() ?? 3)),
              'items': wipItems,
              'status': 'wip',
            };
          }
        }
      } catch (_) {}
    }

    // ── Step 4: risks ────────────────────────────────────────────
    if (planId != null) {
      try {
        final res = await http
            .get(Uri.parse('$base/api/plans/$planId/risks'))
            .timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final raw = jsonDecode(res.body);
          if (raw is List) {
            _risks = raw.whereType<Map<String, dynamic>>().toList();
          }
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _freshPlan = plan;
        _resolvedPlanId = planId;
        _loading = false;
      });
    }
  }

  /// All roadmap terms: current WIP semester first, then future planned terms.
  List<Map<String, dynamic>> _buildRoadmapTerms(
      List<Map<String, dynamic>> plannedTerms) {
    return [
      if (_wipTerm != null) _wipTerm!,
      ...plannedTerms,
    ];
  }

  // ── PDF builder ───────────────────────────────────────────────
  Future<void> _downloadPdf() async {
    final plan = _freshPlan ?? widget.planDetail;
    final allTerms = ((plan?['terms'] as List?) ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final futureTerms = _filterFutureTerms(allTerms);
    final studentName = widget.studentName ?? 'Student';
    final projectedGrad = futureTerms.isNotEmpty
        ? (futureTerms.last['term_name'] ?? 'TBD')
        : (_wipTerm?['term_name'] ?? 'TBD');
    // Show school-issued student ID in PDF too
    final displayId = _schoolStudentId ??
        widget.studentId?.toString() ??
        _resolvedPlanId?.toString() ??
        '—';
    final planProgram = _programName ??
        plan?['program_name'] as String? ??
        plan?['program'] as String? ??
        plan?['degree'] as String? ??
        'Degree Program';

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(36),
        build: (ctx) => [
          pw.Header(
            level: 0,
            child: pw.Text('Academic Path Summary',
                style:
                    pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 4),
          pw.Text('Official Graduation Forecast & Planning Document',
              style: const pw.TextStyle(fontSize: 12)),
          pw.SizedBox(height: 10),
          pw.Row(children: [
            pw.Text('Student: '),
            pw.Text(studentName,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(width: 24),
            pw.Text('Program: '),
            pw.Text(planProgram,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(width: 24),
            pw.Text('Student ID: $displayId'),
          ]),
          pw.SizedBox(height: 4),
          pw.Row(children: [
            pw.Text('Expected Graduation: '),
            pw.Text(projectedGrad.toString(),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(width: 24),
            pw.Text('GPA: $_gpa'),
            pw.SizedBox(width: 24),
            pw.Text('Completed Credits: $_completedCredits / $_degreeCredits'),
          ]),
          pw.Divider(),
          pw.Header(level: 1, text: 'Course Roadmap'),
          pw.SizedBox(height: 6),
          ..._buildRoadmapTerms(futureTerms).map((t) {
            final items = ((t['items'] as List?) ?? [])
                .whereType<Map<String, dynamic>>()
                .toList();
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(t['term_name']?.toString() ?? '',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Table.fromTextArray(
                  headers: ['Course', 'Title', 'Credits'],
                  data: items
                      .map((i) => [
                            i['course_code'] ?? '',
                            i['course_title'] ??
                                i['course_name'] ??
                                i['title'] ??
                                '',
                            (i['credits'] ?? 3).toString(),
                          ])
                      .toList(),
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  cellAlignment: pw.Alignment.centerLeft,
                  columnWidths: {
                    0: const pw.FixedColumnWidth(80),
                    1: const pw.FlexColumnWidth(),
                    2: const pw.FixedColumnWidth(50),
                  },
                ),
                pw.SizedBox(height: 12),
              ],
            );
          }),
          if (_risks.isNotEmpty) ...[
            pw.Divider(),
            pw.Header(level: 1, text: 'Risk Assessment Summary'),
            pw.SizedBox(height: 6),
            ..._risks.map((r) => pw.Bullet(
                text: r['message']?.toString() ?? r['kind']?.toString() ?? '')),
          ],
          pw.Divider(),
          pw.SizedBox(height: 20),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('ADVISOR APPROVAL SIGNATURE',
                      style: const pw.TextStyle(fontSize: 9)),
                  pw.SizedBox(height: 30),
                  pw.Divider(thickness: 0.5),
                  pw.Text('Signature', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('STUDENT CONFIRMATION',
                      style: const pw.TextStyle(fontSize: 9)),
                  pw.SizedBox(height: 30),
                  pw.Divider(thickness: 0.5),
                  pw.Text('Signature', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: GPColors.green));
    }

    final plan = _freshPlan ?? widget.planDetail;
    final allTerms = ((plan?['terms'] as List?) ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final terms = _filterFutureTerms(allTerms);
    final studentName = widget.studentName ?? 'Student';
    // Show school-issued student ID (e.g. "104778"), fall back to DB id
    final displayId = _schoolStudentId ??
        widget.studentId?.toString() ??
        (_resolvedPlanId ?? plan?['id'])?.toString() ??
        '—';
    // Program name: from student record > plan fields > fallback
    final program = _programName ??
        plan?['program_name'] as String? ??
        plan?['program'] as String? ??
        plan?['degree'] as String? ??
        'Degree Program';
    final projectedGrad = terms.isNotEmpty
        ? (terms.last['term_name'] as String? ?? 'TBD')
        : (_wipTerm?['term_name'] as String? ?? 'TBD');
    final plannedCr = terms.fold<int>(
        0, (s, t) => s + ((t['credits'] as num?)?.toInt() ?? 0));
    final progressPct = (_completedCredits / _degreeCredits).clamp(0.0, 1.0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Main document preview ──────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                // Top bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GradPath',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: GPColors.text,
                          ),
                        ),
                        Text(
                          'ADVISOR READY EXPORT',
                          style: TextStyle(
                              fontSize: 9,
                              color: GPColors.subtext,
                              letterSpacing: 1),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: GPColors.border),
                            foregroundColor: GPColors.subtext,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {},
                          icon: const Icon(Icons.settings_outlined, size: 16),
                          label: const Text('Format Settings'),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: GPColors.green,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _downloadPdf,
                          icon: const Icon(Icons.download, size: 16),
                          label: const Text('Download PDF'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Breadcrumb
                Row(
                  children: [
                    const Text('My Plans',
                        style:
                            TextStyle(color: GPColors.subtext, fontSize: 12)),
                    const Icon(Icons.chevron_right,
                        size: 14, color: GPColors.subtext),
                    Text(
                      program,
                      style: const TextStyle(
                          color: GPColors.subtext, fontSize: 12),
                    ),
                    const Icon(Icons.chevron_right,
                        size: 14, color: GPColors.subtext),
                    const Text(
                      'Export Preview',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: GPColors.text,
                          fontSize: 12),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: GPColors.greenSoft,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: GPColors.springBorder),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.circle, size: 8, color: GPColors.green),
                          SizedBox(width: 5),
                          Text(
                            'Ready for Review',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: GPColors.green),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Document preview ──────────────────────────────
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: GPColors.border),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x0A000000),
                          blurRadius: 20,
                          offset: Offset(0, 6)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Document header
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Academic Path Summary',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: GPColors.text,
                                  ),
                                ),
                                Text(
                                  'Official Graduation Forecast & Planning Document',
                                  style: TextStyle(
                                      color: GPColors.subtext, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'GRADPATH ID: $displayId',
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: GPColors.green),
                              ),
                              Text(
                                'Generated on: ${DateTime.now().month}/${DateTime.now().day}/${DateTime.now().year}',
                                style: const TextStyle(
                                    fontSize: 10, color: GPColors.subtext),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Divider(height: 28, color: GPColors.border),

                      // Student info
                      Row(
                        children: [
                          _DocField(label: 'STUDENT NAME', value: studentName),
                          const SizedBox(width: 32),
                          _DocField(label: 'DEGREE PROGRAM', value: program),
                          const SizedBox(width: 32),
                          _DocField(
                            label: 'EXPECTED GRADUATION',
                            value: projectedGrad,
                            highlight: true,
                          ),
                        ],
                      ),
                      const Divider(height: 28, color: GPColors.border),

                      // Graduation forecast section
                      const _DocSectionHeader(
                          icon: Icons.bar_chart, label: 'GRADUATION FORECAST'),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Total Degree Progress',
                                      style: TextStyle(
                                          fontSize: 12, color: GPColors.text),
                                    ),
                                    Text(
                                      _completedCredits > 0
                                          ? '${(progressPct * 100).round()}%'
                                          : '—',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: GPColors.green),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: progressPct,
                                    minHeight: 8,
                                    backgroundColor: const Color(0xFFE2E8F0),
                                    color: GPColors.green,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    _StatMini(
                                        label: 'Current GPA', value: _gpa),
                                    const SizedBox(width: 24),
                                    _StatMini(
                                        label: 'Completed Credits',
                                        value:
                                            '$_completedCredits / $_degreeCredits'),
                                    const SizedBox(width: 24),
                                    _StatMini(
                                        label: 'Planned Credits',
                                        value: '$plannedCr'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 32),
                          // Risk summary
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: GPColors.amberSoft,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: GPColors.amber.withOpacity(0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'RISK ASSESSMENT SUMMARY',
                                    style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: GPColors.subtext,
                                        letterSpacing: 0.5),
                                  ),
                                  const SizedBox(height: 8),
                                  if (_risks.isEmpty)
                                    const _RiskItem(
                                      icon: Icons.check_circle_outline,
                                      color: GPColors.green,
                                      text: 'No risks detected in your plan.',
                                    )
                                  else
                                    ..._risks.take(4).map((r) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 8),
                                          child: _RiskItem(
                                            icon: Icons.warning_amber_rounded,
                                            color: GPColors.amber,
                                            text: r['message']?.toString() ??
                                                r['kind']?.toString() ??
                                                'Risk detected.',
                                          ),
                                        )),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 30, color: GPColors.border),

                      // Academic Course Roadmap
                      const _DocSectionHeader(
                          icon: Icons.map_outlined,
                          label: 'ACADEMIC COURSE ROADMAP'),
                      const SizedBox(height: 14),
                      if (_buildRoadmapTerms(terms).isEmpty)
                        const Text('No terms found.',
                            style: TextStyle(color: GPColors.subtext))
                      else
                        ..._buildRoadmapTerms(terms)
                            .map((t) => _TermSection(term: t)),

                      const Divider(height: 30, color: GPColors.border),

                      // Planning notes
                      const _DocSectionHeader(
                          icon: Icons.notes,
                          label: 'PLANNING NOTES & ADVISOR COMMENTS'),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: GPColors.border),
                        ),
                        child: const Text(
                          '"This academic plan has been generated by GradPath AI based on your transcript, degree requirements, and career goals. Please review with your academic advisor before making enrollment decisions."',
                          style: TextStyle(
                              fontSize: 12,
                              color: GPColors.subtext,
                              height: 1.6),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Signature area
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'ADVISOR APPROVAL SIGNATURE',
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: GPColors.subtext,
                                      letterSpacing: 0.5),
                                ),
                                const SizedBox(height: 30),
                                Container(
                                  height: 1,
                                  color: GPColors.border,
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Signature Field',
                                  style: TextStyle(
                                      fontSize: 12, color: GPColors.subtext),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 40),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'STUDENT CONFIRMATION',
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: GPColors.subtext,
                                      letterSpacing: 0.5),
                                ),
                                const SizedBox(height: 30),
                                Container(
                                  height: 1,
                                  color: GPColors.border,
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Student Signature',
                                  style: TextStyle(
                                      fontSize: 12, color: GPColors.subtext),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Bottom actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: GPColors.text,
                        side: const BorderSide(color: GPColors.border),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {},
                      child: const Text('Back to Editor'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: GPColors.green,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _downloadPdf,
                      child: const Text('Finalize & Share with Student',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Doc widgets ───────────────────────────────────────────────────────────

class _DocField extends StatelessWidget {
  const _DocField(
      {required this.label, required this.value, this.highlight = false});
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: GPColors.subtext,
              letterSpacing: 0.5),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: highlight ? GPColors.green : GPColors.text,
          ),
        ),
      ],
    );
  }
}

class _DocSectionHeader extends StatelessWidget {
  const _DocSectionHeader({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: GPColors.subtext),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: GPColors.subtext,
              letterSpacing: 0.5),
        ),
      ],
    );
  }
}

class _StatMini extends StatelessWidget {
  const _StatMini({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 10, color: GPColors.subtext)),
        Text(
          value,
          style: const TextStyle(
              fontSize: 22, fontWeight: FontWeight.w900, color: GPColors.text),
        ),
      ],
    );
  }
}

class _RiskItem extends StatelessWidget {
  const _RiskItem(
      {required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
                fontSize: 11, color: GPColors.text, height: 1.4),
          ),
        ),
      ],
    );
  }
}

class _TermSection extends StatelessWidget {
  const _TermSection({required this.term});
  final Map<String, dynamic> term;

  @override
  Widget build(BuildContext context) {
    final name = term['term_name'] as String? ?? 'Term';
    final credits = (term['credits'] as num?)?.toInt() ?? 0;
    final items =
        ((term['items'] as List?) ?? []).whereType<Map<String, dynamic>>();
    final season = name.toLowerCase();
    final Color accentColor;
    if (season.contains('fall')) {
      accentColor = GPColors.fallAccent;
    } else if (season.contains('spring')) {
      accentColor = GPColors.springAccent;
    } else if (season.contains('summer')) {
      accentColor = GPColors.summerAccent;
    } else {
      accentColor = GPColors.blue;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline, size: 16, color: accentColor),
              const SizedBox(width: 8),
              Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                term['status'] == 'wip' ? '(In Progress)' : '(Planned)',
                style: TextStyle(
                  color: term['status'] == 'wip'
                      ? GPColors.amber
                      : GPColors.subtext,
                  fontSize: 12,
                  fontWeight: term['status'] == 'wip'
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
              const Spacer(),
              Text(
                '$credits Credits',
                style: const TextStyle(fontSize: 12, color: GPColors.subtext),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            const Text('No courses assigned.',
                style: TextStyle(color: GPColors.subtext, fontSize: 12))
          else
            Table(
              columnWidths: const {
                0: FlexColumnWidth(1),
                1: FlexColumnWidth(3),
                2: FlexColumnWidth(1),
                3: FlexColumnWidth(1),
              },
              children: [
                const TableRow(
                  decoration: BoxDecoration(color: GPColors.bg),
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Text('CODE',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: GPColors.subtext)),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Text('COURSE NAME',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: GPColors.subtext)),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Text('CREDITS',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: GPColors.subtext)),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Text('STATUS',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: GPColors.subtext)),
                    ),
                  ],
                ),
                ...items.map(
                  (item) => TableRow(
                    decoration: const BoxDecoration(
                      border:
                          Border(bottom: BorderSide(color: GPColors.border)),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        child: Text(
                          item['course_code'] as String? ?? '—',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: accentColor),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        child: Text(
                          item['course_title'] as String? ?? '—',
                          style: const TextStyle(
                              fontSize: 12, color: GPColors.text),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        child: Text(
                          '${(item['credits'] as num?)?.toInt() ?? 3}',
                          style: const TextStyle(
                              fontSize: 12, color: GPColors.subtext),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: accentColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'SCHEDULED',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: accentColor),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
