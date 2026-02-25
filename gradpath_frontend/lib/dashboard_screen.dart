import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'gradpath_config.dart';
import 'gradpath_theme.dart';

// ────────────────────────────────────────────────────────────
// DashboardScreen — Academic Overview
// Used inside GradPathShell (no Scaffold / sidebar of its own)
// ────────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.studentId,
    this.planDetail,
    this.studentName,
  });

  final int? studentId;
  final Map<String, dynamic>? planDetail;
  final String? studentName;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const int _creditsRequired = 124;

  double? _gpa;
  // Credits from completed (graded) terms only
  int _completedCredits = 0;
  // Credits enrolled in the current WIP term
  int _wipCredits = 0;
  // Name of the WIP (in-progress) term, e.g. "Spring 2026"
  String? _wipTermName;
  // Total transcript term count (completed + WIP)
  int _transcriptTermCount = 0;
  String? _projectedGrad;
  List<Map<String, dynamic>> _risks = [];
  bool _loading = true;
  DateTime? _lastSynced;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      await Future.wait([
        _loadGpa(),
        _loadTranscript(),
        _loadPlanData(),
      ]);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _lastSynced = DateTime.now();
        });
      }
    }
  }

  /// Fetches the latest plan for this student, resolving the plan ID
  /// from the student endpoint, then loads risks and
  /// fills in projected graduation from the plan when transcript is empty.
  Future<void> _loadPlanData() async {
    final id = widget.studentId;
    if (id == null) return;

    // Always fetch the latest plan_id from student endpoint for freshness
    int? planId;
    try {
      final uri =
          Uri.parse('${GradPathConfig.backendBaseUrl}/api/students/$id');
      final resp = await http.get(uri);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        planId = data['plan_id'] as int?;
      }
    } catch (_) {}
    // Fall back to widget prop if student fetch failed
    planId ??= widget.planDetail?['id'] as int?;
    if (planId == null) return;

    // Load risks
    try {
      final uri =
          Uri.parse('${GradPathConfig.backendBaseUrl}/api/plans/$planId/risks');
      final resp = await http.get(uri);
      if (resp.statusCode == 200 && mounted) {
        final raw = jsonDecode(resp.body);
        final items = raw is List
            ? raw.whereType<Map<String, dynamic>>().toList()
            : ((raw as Map)['risks'] as List? ?? [])
                .whereType<Map<String, dynamic>>()
                .toList();
        setState(() {
          _risks = items;
        });
      }
    } catch (_) {}

    // Load plan to derive projected grad when transcript is empty
    try {
      final uri =
          Uri.parse('${GradPathConfig.backendBaseUrl}/api/plans/$planId');
      final resp = await http.get(uri);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final terms = (data['terms'] as List?) ?? [];
        if (terms.isNotEmpty) {
          // Last term in the plan is the projected graduation term
          final lastTerm = terms.last as Map<String, dynamic>?;
          final termName = lastTerm?['term_name'] as String?;
          if (termName != null && mounted) {
            setState(() {
              // Only set from plan if transcript didn't already set it
              _projectedGrad ??= termName;
            });
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _loadGpa() async {
    final id = widget.studentId;
    if (id == null) return;
    try {
      final uri =
          Uri.parse('${GradPathConfig.backendBaseUrl}/api/students/$id/gpa');
      final resp = await http.get(uri);
      if (resp.statusCode != 200) return;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _gpa = (data['gpa'] as num?)?.toDouble();
      });
    } catch (_) {}
  }

  /// Loads transcript courses and derives:
  ///  - completed credits (graded terms)
  ///  - WIP credits & term name (current in-progress semester)
  ///  - transcript term count
  ///  - projected graduation term
  Future<void> _loadTranscript() async {
    final id = widget.studentId;
    if (id == null) return;
    try {
      final uri =
          Uri.parse('${GradPathConfig.backendBaseUrl}/api/transcripts/$id');
      final resp = await http.get(uri);
      if (resp.statusCode != 200) return;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final courses = (data['courses'] as List?) ?? [];
      if (courses.isEmpty) return;

      // Group courses by term
      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final c in courses.whereType<Map<String, dynamic>>()) {
        final term = (c['term'] as String?) ?? 'Unknown';
        grouped.putIfAbsent(term, () => []).add(c);
      }

      // Sort chronologically
      int termSortKey(String t) {
        final parts = t.trim().split(RegExp(r'\s+'));
        if (parts.length < 2) return 0;
        final year = int.tryParse(parts.last) ?? 0;
        final sv = switch (parts.first.toLowerCase()) {
          'spring' => 1,
          'summer' => 2,
          'fall' => 3,
          _ => 0,
        };
        return year * 10 + sv;
      }

      final sortedTerms = grouped.keys.toList()
        ..sort((a, b) => termSortKey(a).compareTo(termSortKey(b)));

      int completedCr = 0;
      int wipCr = 0;
      String? wipTerm;
      String? lastTerm;

      for (final term in sortedTerms) {
        final termCourses = grouped[term]!;
        final isWip = termCourses.any((c) => (c['grade'] as String?) == 'WIP');
        final termCr = termCourses.fold<int>(
            0, (s, c) => s + ((c['credits'] as num?)?.toInt() ?? 3));
        if (isWip) {
          wipCr = termCr;
          wipTerm = term;
        } else {
          completedCr += termCr;
        }
        lastTerm = term;
      }

      final totalTxCr = completedCr + wipCr;
      final isLastSemester = totalTxCr >= _creditsRequired;

      String? nextTerm(String t) {
        final parts = t.trim().split(RegExp(r'\s+'));
        if (parts.length < 2) return null;
        final year = int.tryParse(parts.last) ?? DateTime.now().year;
        final season = parts.first.toLowerCase();
        if (season == 'fall') return 'Spring ${year + 1}';
        return 'Fall $year';
      }

      final grad = isLastSemester
          ? (wipTerm ?? lastTerm)
          : (lastTerm != null ? nextTerm(lastTerm) : null);

      if (!mounted) return;
      setState(() {
        _completedCredits = completedCr;
        _wipCredits = wipCr;
        _wipTermName = wipTerm;
        _transcriptTermCount = sortedTerms.length;
        _projectedGrad = grad;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.studentName ?? 'there';
    final firstName = name.split(' ').first;
    // Total credits the student has (completed + current WIP)
    final earnedCr = _completedCredits + _wipCredits;
    const totalCr = _creditsRequired;
    final creditPct = (earnedCr / totalCr).clamp(0.0, 1.0);
    final creditPctLabel = '${(creditPct * 100).round()}%';

    final criticalCount = _risks.where((r) {
      final sev = (r['severity'] as String? ?? '').toLowerCase();
      return sev == 'critical' || sev == 'high';
    }).length;
    final moderateCount = _risks.where((r) {
      final sev = (r['severity'] as String? ?? '').toLowerCase();
      return sev == 'moderate' || sev == 'medium';
    }).length;
    final overallRisk = criticalCount > 0
        ? 'High Risk'
        : moderateCount > 0
            ? 'Moderate Risk'
            : 'On Track';
    final riskColor = criticalCount > 0
        ? GPColors.riskCritical
        : moderateCount > 0
            ? GPColors.riskModerate
            : GPColors.riskLow;
    final riskBg = criticalCount > 0
        ? GPColors.riskCriticalSoft
        : moderateCount > 0
            ? GPColors.riskModerateSoft
            : GPColors.riskLowSoft;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Academic Overview',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: GPColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Welcome back, $firstName. Here is your graduation trajectory.',
                      style: const TextStyle(
                          color: GPColors.subtext, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _SyncChip(syncedAt: _lastSynced),
            ],
          ),
          const SizedBox(height: 24),

          // ── Forecast Status card ───────────────────────────────
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: GPColors.border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'FORECAST STATUS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: GPColors.subtext,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: riskBg,
                              borderRadius: BorderRadius.circular(999),
                              border:
                                  Border.all(color: riskColor.withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.warning_amber_rounded,
                                    size: 12, color: riskColor),
                                const SizedBox(width: 4),
                                Text(
                                  overallRisk,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: riskColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _loading
                            ? 'Earliest Graduation: Loading…'
                            : 'Earliest Graduation: ${_projectedGrad ?? 'TBD'}',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: GPColors.green,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        criticalCount > 0
                            ? 'Your plan has $criticalCount critical issue(s) that may delay graduation.'
                            : moderateCount > 0
                                ? 'Your plan has $moderateCount moderate risk(s). Review to stay on track.'
                                : 'Your plan looks great! You are projected to graduate on schedule.',
                        style: const TextStyle(
                          color: GPColors.subtext,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                      if (_risks.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: GPColors.greenSoft,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.tips_and_updates,
                                  size: 14, color: GPColors.green),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Optimization suggested: ${(_risks.first['description'] as String? ?? 'Review your plan for improvements.')}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: GPColors.accentInk,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Review Plan →',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: GPColors.green,
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                // Credit progress
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Credit Progress',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: GPColors.subtext,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _loading ? '…' : creditPctLabel,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: GPColors.text,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: creditPct.toDouble(),
                          minHeight: 10,
                          backgroundColor: const Color(0xFFE2E8F0),
                          color: GPColors.green,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(
                                '$_completedCredits Completed',
                                style: const TextStyle(
                                    fontSize: 11, color: GPColors.subtext),
                              ),
                              if (_wipCredits > 0) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF7ED),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: const Color(0xFFFED7AA)),
                                  ),
                                  child: Text(
                                    '+$_wipCredits In Progress',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFB45309),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const Text(
                            '$totalCr Required',
                            style: TextStyle(
                                fontSize: 11, color: GPColors.subtext),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── Active Bottleneck Alerts ───────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Active Bottleneck Alerts',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: GPColors.text,
                ),
              ),
              TextButton(
                onPressed: () {},
                child: const Text(
                  'View All Analysis',
                  style: TextStyle(
                      color: GPColors.green, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _loading
              ? const Center(
                  child: CircularProgressIndicator(color: GPColors.green))
              : _risks.isEmpty
                  ? _EmptyAlertCard()
                  : _AlertCardsRow(risks: _risks.take(3).toList()),
          const SizedBox(height: 28),

          // ── Stats row ─────────────────────────────────────────
          _StatsRow(
            gpa: _gpa,
            transcriptTermCount: _transcriptTermCount,
            wipCredits: _wipCredits,
            wipTermName: _wipTermName,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Sync chip ─────────────────────────────────────────────────────────────

class _SyncChip extends StatelessWidget {
  const _SyncChip({this.syncedAt});
  final DateTime? syncedAt;

  String get _label {
    if (syncedAt == null) return 'Syncing…';
    final now = DateTime.now();
    final diff = now.difference(syncedAt!);
    if (diff.inSeconds < 60) return 'Last synced: just now';
    if (diff.inMinutes < 60) return 'Last synced: ${diff.inMinutes}m ago';
    return 'Last synced: ${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GPColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sync, size: 14, color: GPColors.subtext),
          const SizedBox(width: 6),
          Text(
            _label,
            style: const TextStyle(fontSize: 12, color: GPColors.subtext),
          ),
        ],
      ),
    );
  }
}

// ── Alert cards ───────────────────────────────────────────────────────────

class _EmptyAlertCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: GPColors.riskLowSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GPColors.springBorder),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle, color: GPColors.green, size: 22),
          SizedBox(width: 12),
          Text(
            'No active bottleneck alerts. Your plan looks great!',
            style: TextStyle(
                color: GPColors.accentInk, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _AlertCardsRow extends StatelessWidget {
  const _AlertCardsRow({required this.risks});
  final List<Map<String, dynamic>> risks;

  @override
  Widget build(BuildContext context) {
    final colors = [
      (GPColors.riskCritical, GPColors.riskCriticalSoft, Icons.link_off),
      (GPColors.riskModerate, GPColors.riskModerateSoft, Icons.event_busy),
      (GPColors.green, GPColors.riskLowSoft, Icons.bolt),
    ];
    final labels = ['Fix Schedule', 'Quick Enroll', 'Add to Plan'];

    return LayoutBuilder(
      builder: (context, constraints) {
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: List.generate(risks.length, (i) {
            final risk = risks[i];
            final (color, bg, icon) = colors[i % colors.length];
            final sev = (risk['severity'] as String? ?? 'Low').toUpperCase();
            return SizedBox(
              width: (constraints.maxWidth - 32) / 3,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border(
                    left: BorderSide(color: color, width: 4),
                    top: const BorderSide(color: GPColors.border),
                    right: const BorderSide(color: GPColors.border),
                    bottom: const BorderSide(color: GPColors.border),
                  ),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x06000000),
                        blurRadius: 10,
                        offset: Offset(0, 3)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            risk['title'] as String? ??
                                risk['risk_type'] as String? ??
                                'Risk Alert',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: GPColors.text,
                            ),
                          ),
                        ),
                        Icon(icon, size: 16, color: color),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        sev,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      risk['description'] as String? ?? '',
                      style: const TextStyle(
                          color: GPColors.subtext, fontSize: 12, height: 1.5),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () {},
                        child: Text(
                          labels[i % labels.length],
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// ── Stats row ─────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    this.gpa,
    this.transcriptTermCount = 0,
    this.wipCredits = 0,
    this.wipTermName,
  });

  final double? gpa;
  final int transcriptTermCount;
  final int wipCredits;
  final String? wipTermName;

  @override
  Widget build(BuildContext context) {
    // Path stability: excellent ≥3.5, good ≥3.0, moderate ≥2.5, at-risk <2.5
    String stabilityLabel;
    String stabilityBadge = '';
    if (gpa == null) {
      stabilityLabel = '--';
    } else if (gpa! >= 3.5) {
      stabilityLabel = '98%';
      stabilityBadge = 'Strong';
    } else if (gpa! >= 3.0) {
      stabilityLabel = '88%';
      stabilityBadge = 'Good';
    } else if (gpa! >= 2.5) {
      stabilityLabel = '72%';
      stabilityBadge = 'Watch';
    } else {
      stabilityLabel = '55%';
      stabilityBadge = 'At Risk';
    }

    final creditsThisTermLabel = wipCredits > 0 ? '$wipCredits' : '--';
    final creditsThisTermBadge =
        wipCredits > 0 ? (wipCredits <= 18 ? 'On Track' : 'Heavy Load') : '';

    final stats = [
      ('GPA (CURRENT)', gpa != null ? gpa!.toStringAsFixed(2) : '--', ''),
      (
        'TOTAL SEMESTERS',
        transcriptTermCount > 0 ? '$transcriptTermCount' : '--',
        ''
      ),
      ('CREDITS THIS TERM', creditsThisTermLabel, creditsThisTermBadge),
      ('PATH STABILITY', stabilityLabel, stabilityBadge),
    ];

    return Row(
      children: List.generate(stats.length, (i) {
        final (label, value, badge) = stats[i];
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i < stats.length - 1 ? 14 : 0),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: GPColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: GPColors.subtext,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: GPColors.text,
                      ),
                    ),
                    if (badge.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: GPColors.greenSoft,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badge,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: GPColors.green,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
