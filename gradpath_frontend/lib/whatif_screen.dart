import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'gradpath_config.dart';
import 'gradpath_theme.dart';

// ────────────────────────────────────────────────────────────
// WhatIfScreen — What-If Academic Simulator
// Used inside GradPathShell (no Scaffold of its own)
// ────────────────────────────────────────────────────────────

class WhatIfScreen extends StatefulWidget {
  const WhatIfScreen({super.key, this.studentId, this.planDetail});

  final int? studentId;
  final Map<String, dynamic>? planDetail;

  @override
  State<WhatIfScreen> createState() => _WhatIfScreenState();
}

class _WhatIfScreenState extends State<WhatIfScreen> {
  double _maxCredits = 18;
  bool _summerTerms = true;
  bool _includeInternships = false;
  bool _simulating = false;
  bool _loadingPlan = true;

  Map<String, dynamic>? _simResult;
  Map<String, dynamic>?
      _wipTerm; // Current in-progress semester from transcript

  // Fresh plan loaded on mount (always up-to-date with transcript)
  Map<String, dynamic>? _currentPlanDetail;
  int? _currentPlanId;

  int _initialRiskScore = 0;
  int _baseTermCount = 0;

  int? get _effectiveStudentId {
    final fromWidget = widget.studentId;
    if (fromWidget != null) return fromWidget;
    final fromCurrentPlan = _currentPlanDetail?['student_id'] as int?;
    if (fromCurrentPlan != null) return fromCurrentPlan;
    return widget.planDetail?['student_id'] as int?;
  }

  @override
  void initState() {
    super.initState();
    final sid = _effectiveStudentId;
    if (sid != null) {
      _fetchCurrentPlan(sid);
    } else {
      _initFromProp();
    }
  }

  void _initFromProp() {
    final allTerms = ((widget.planDetail?['terms'] as List?) ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final future = _filterFutureTerms(allTerms);
    final planId = widget.planDetail?['id'] as int?;
    setState(() {
      _currentPlanDetail = widget.planDetail;
      _currentPlanId = planId;
      _baseTermCount = future.length;
      _loadingPlan = false;
    });
    if (planId != null) _loadInitialRisk(planId);
    final sid = _effectiveStudentId;
    if (sid != null) _fetchWipTerm(sid);
  }

  Future<void> _fetchCurrentPlan(int studentId) async {
    // ── Fast path: planDetail already provided (returning student flow) ──────
    // The returning_student_screen fetches a fresh plan before navigating here,
    // so if we have it, use it immediately and avoid a redundant round-trip.
    if (widget.planDetail != null) {
      _initFromProp();
      // Still silently check for a newer plan in the background.
      _refreshLatestPlan(studentId);
      return;
    }

    // ── Slow path: no planDetail passed in, look it up ───────────────────────
    try {
      final stuResp = await http.get(Uri.parse(
          '${GradPathConfig.backendBaseUrl}/api/students/$studentId'));
      if (!mounted) return;
      int? planId;
      if (stuResp.statusCode == 200) {
        final stuData = jsonDecode(stuResp.body) as Map<String, dynamic>;
        planId = stuData['plan_id'] as int?;
      }
      if (planId == null) {
        if (mounted) setState(() => _loadingPlan = false);
        return;
      }
      await _applyPlanFromId(planId);
    } catch (_) {
      if (mounted) setState(() => _loadingPlan = false);
    }
  }

  /// Silently re-fetches the student's latest plan and updates state if
  /// the plan ID differs from what _initFromProp already loaded.
  Future<void> _refreshLatestPlan(int studentId) async {
    try {
      final stuResp = await http.get(Uri.parse(
          '${GradPathConfig.backendBaseUrl}/api/students/$studentId'));
      if (!mounted || stuResp.statusCode != 200) return;
      final stuData = jsonDecode(stuResp.body) as Map<String, dynamic>;
      final latestId = stuData['plan_id'] as int?;
      if (latestId != null && latestId != _currentPlanId) {
        await _applyPlanFromId(latestId);
      }
    } catch (_) {}
  }

  Future<void> _applyPlanFromId(int planId) async {
    try {
      final planResp = await http
          .get(Uri.parse('${GradPathConfig.backendBaseUrl}/api/plans/$planId'));
      if (!mounted || planResp.statusCode != 200) return;
      final detail = jsonDecode(planResp.body) as Map<String, dynamic>;
      final allTerms = ((detail['terms'] as List?) ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      final future = _filterFutureTerms(allTerms);
      setState(() {
        _currentPlanDetail = detail;
        _currentPlanId = planId;
        _baseTermCount = future.length;
        _loadingPlan = false;
      });
      _loadInitialRisk(planId);
      final sid = _effectiveStudentId;
      if (sid != null) _fetchWipTerm(sid);
    } catch (_) {
      if (mounted) setState(() => _loadingPlan = false);
    }
  }

  /// Keep only semesters starting from the current term onwards.
  /// Terms are named "Fall 2022", "Spring 2026", "Summer 2027", etc.
  List<Map<String, dynamic>> _filterFutureTerms(
      List<Map<String, dynamic>> terms) {
    final now = DateTime.now();
    final currentYear = now.year;
    // Spring = Jan–May, Summer = Jun–Jul, Fall = Aug–Dec
    final currentSeason =
        now.month <= 5 ? 'spring' : (now.month <= 7 ? 'summer' : 'fall');
    final seasonOrder = {'spring': 0, 'summer': 1, 'fall': 2};
    final currentSeasonOrd = seasonOrder[currentSeason]!;

    return terms.where((t) {
      final name = (t['term_name'] as String? ?? '').trim().toLowerCase();
      final parts = name.split(' ');
      if (parts.length < 2) return true;
      final season = parts.first;
      final year = int.tryParse(parts.last) ?? 0;

      if (year > currentYear) return true;
      if (year == currentYear) {
        final termOrd = seasonOrder[season] ?? 0;
        return termOrd >= currentSeasonOrd;
      }
      return false; // past year
    }).toList();
  }

  Future<void> _loadInitialRisk(int planId) async {
    try {
      final uri =
          Uri.parse('${GradPathConfig.backendBaseUrl}/api/plans/$planId/risks');
      final resp = await http.get(uri);
      if (resp.statusCode == 200 && mounted) {
        final risks = (jsonDecode(resp.body) as List);
        setState(() => _initialRiskScore = (risks.length * 15).clamp(0, 100));
      }
    } catch (_) {}
  }

  Future<void> _fetchWipTerm(int studentId) async {
    try {
      final txResp = await http.get(Uri.parse(
          '${GradPathConfig.backendBaseUrl}/api/transcripts/$studentId'));
      if (!mounted || txResp.statusCode != 200) return;
      final txData = jsonDecode(txResp.body) as Map<String, dynamic>;
      final courses = (txData['courses'] as List?) ?? [];
      final wipMap = <String, List<Map<String, dynamic>>>{};
      for (final c in courses.whereType<Map<String, dynamic>>()) {
        if ((c['grade'] as String?)?.toUpperCase() == 'WIP') {
          final term = c['term'] as String?;
          if (term != null) wipMap.putIfAbsent(term, () => []).add(c);
        }
      }
      if (wipMap.isEmpty) return;
      int sortKey(String t) {
        final p = t.trim().split(RegExp(r'\s+'));
        if (p.length < 2) return 0;
        final y = int.tryParse(p.last) ?? 0;
        final s = switch (p.first.toLowerCase()) {
          'spring' => 1,
          'summer' => 2,
          'fall' => 3,
          _ => 0,
        };
        return y * 10 + s;
      }

      final name =
          wipMap.keys.reduce((a, b) => sortKey(a) >= sortKey(b) ? a : b);
      final items = wipMap[name]!;
      if (mounted) {
        setState(() => _wipTerm = {
              'term_name': name,
              'credits': items.fold<int>(
                  0, (s, c) => s + ((c['credits'] as num?)?.toInt() ?? 3)),
              'items': items,
              'status': 'wip',
            });
      }
    } catch (_) {}
  }

  /// Terms shown in the UI — simulation result takes priority, then fresh plan
  /// filtered to future-only, then fallback to passed prop.
  List<Map<String, dynamic>> get _terms {
    if (_simResult != null) {
      final simTerms = ((_simResult!['terms'] as List?) ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      return [
        if (_wipTerm != null) _wipTerm!,
        ...simTerms,
      ];
    }
    final allTerms = ((_currentPlanDetail?['terms'] as List?) ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final future = _filterFutureTerms(allTerms);
    return [
      if (_wipTerm != null) _wipTerm!,
      ...future,
    ];
  }

  String get _expectedGrad {
    if (_simResult != null) {
      return _simResult!['projected_graduation'] as String? ?? _baseProjGrad;
    }
    return _baseProjGrad;
  }

  String get _baseProjGrad {
    final ft = _filterFutureTerms(
        ((_currentPlanDetail?['terms'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .toList());
    if (ft.isNotEmpty) return ft.last['term_name'] as String? ?? 'TBD';
    // If no plan terms remain, the student graduates in their current WIP semester
    if (_wipTerm != null) return _wipTerm!['term_name'] as String? ?? 'TBD';
    return 'TBD';
  }

  double get _avgLoad {
    final t = _terms;
    if (t.isEmpty) return 0;
    final total = t.fold<int>(
        0, (s, term) => s + ((term['credits'] as num?)?.toInt() ?? 0));
    return total / t.length;
  }

  Future<void> _simulate() async {
    final planId = _currentPlanId ?? widget.planDetail?['id'] as int?;
    if (planId == null) return;

    setState(() => _simulating = true);
    try {
      final uri =
          Uri.parse('${GradPathConfig.backendBaseUrl}/api/plans/simulate');
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'plan_id': planId,
          'max_credits': _maxCredits.round(),
          'summer_ok': _summerTerms,
        }),
      );
      if (resp.statusCode == 200 && mounted) {
        setState(
            () => _simResult = jsonDecode(resp.body) as Map<String, dynamic>);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _simulating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingPlan) {
      return const Center(
        child: CircularProgressIndicator(color: GPColors.green),
      );
    }

    final riskScore = _simResult != null
        ? ((_simResult!['risk_score'] as num?)?.toInt() ?? _initialRiskScore)
        : _initialRiskScore;
    final simTerms = (_simResult != null
        ? ((_simResult!['terms'] as List?)?.length ?? 0)
        : 0);
    final termDiff = _baseTermCount - simTerms;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Left panel ─────────────────────────────────────────
        Container(
          width: 300,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(right: BorderSide(color: GPColors.border)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: GPColors.greenSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.tune_rounded, size: 18, color: GPColors.green),
                      SizedBox(width: 8),
                      Text(
                        'Simulation Engine',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: GPColors.green,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Max credits label + value
                const Text(
                  'MAX CREDITS / SEMESTER',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: GPColors.subtext,
                      letterSpacing: 0.8),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${_maxCredits.round()}',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: GPColors.green,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 4),
                      child: Text(
                        'credits',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: GPColors.subtext,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _maxCredits > 18
                            ? GPColors.riskCriticalSoft
                            : _maxCredits < 12
                                ? GPColors.amberSoft
                                : GPColors.greenSoft,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _maxCredits > 18
                            ? 'Overload'
                            : _maxCredits < 12
                                ? 'Part-time'
                                : 'Full-time',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _maxCredits > 18
                              ? GPColors.riskCritical
                              : _maxCredits < 12
                                  ? GPColors.amber
                                  : GPColors.green,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 5,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                    activeTrackColor: GPColors.green,
                    inactiveTrackColor: GPColors.border,
                    thumbColor: GPColors.green,
                    overlayColor: GPColors.green.withValues(alpha: 0.12),
                  ),
                  child: Slider(
                    value: _maxCredits,
                    min: 9,
                    max: 22,
                    divisions: 13,
                    onChanged: (v) => setState(() => _maxCredits = v),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _SliderLabel('9 cr', _maxCredits < 12),
                      _SliderLabel('15 cr', _maxCredits >= 12 && _maxCredits <= 18),
                      _SliderLabel('22 cr', _maxCredits > 18),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Divider(color: GPColors.border, height: 1),
                const SizedBox(height: 20),

                // Toggles
                _ToggleRow(
                  label: 'Enroll in Summer Terms',
                  value: _summerTerms,
                  onChanged: (v) => setState(() => _summerTerms = v),
                ),
                const SizedBox(height: 4),
                _ToggleRow(
                  label: 'Include Internships',
                  value: _includeInternships,
                  onChanged: (v) => setState(() => _includeInternships = v),
                ),
                const SizedBox(height: 24),
                const Divider(color: GPColors.border, height: 1),
                const SizedBox(height: 20),

                // Academic performance section
                if (_currentPlanDetail != null) ...[
                  const Text(
                    'UPCOMING COURSES',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: GPColors.subtext,
                        letterSpacing: 0.8),
                  ),
                  const SizedBox(height: 12),
                  ..._buildCoursePerformanceList(),
                  const SizedBox(height: 20),
                ],

                // Run simulation button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GPColors.green,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _simulating ? null : _simulate,
                    icon: _simulating
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow_rounded, size: 18),
                    label: Text(
                      _simulating ? 'Simulating…' : 'Run Simulation',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Main content ───────────────────────────────────────
        Expanded(
          child: ColoredBox(
            color: GPColors.bg,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'GradPath Simulator',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: GPColors.text,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'WHAT-IF ACADEMIC HUB',
                            style: TextStyle(
                                fontSize: 10,
                                color: GPColors.subtext,
                                letterSpacing: 1.2,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const Spacer(),
                      // Circular risk gauge
                      _RiskGauge(score: riskScore),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: GPColors.accentInk,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {},
                        icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                        label: const Text('Save Scenario',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // KPI cards
                  Row(
                    children: [
                      Expanded(
                        child: _KpiCard(
                          label: 'EXPECTED GRADUATION',
                          value: _expectedGrad,
                          icon: Icons.school_rounded,
                          accentColor: GPColors.green,
                          badge: (_simResult != null && simTerms > 0)
                              ? (termDiff > 0
                                  ? '$termDiff Semester${termDiff > 1 ? "s" : ""} Earlier'
                                  : termDiff < 0
                                      ? '${-termDiff} Semester${-termDiff > 1 ? "s" : ""} Longer'
                                      : 'Same Duration')
                              : null,
                          badgePosOrNeg: termDiff >= 0,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _KpiCard(
                          label: 'AVG. LOAD PER SEMESTER',
                          value: '${_avgLoad.toStringAsFixed(1)} Credits',
                          icon: Icons.bar_chart_rounded,
                          accentColor: GPColors.blue,
                          badge: _avgLoad <= 18
                              ? 'Sustainable Pace'
                              : 'Heavy Load',
                          badgePosOrNeg: _avgLoad <= 18,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Dynamic Roadmap
                  _DynamicRoadmap(terms: _terms),
                  const SizedBox(height: 20),

                  // Optimization hint — shown when no simulation has run yet
                  if (_simResult == null) const _OptimizationBanner(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildCoursePerformanceList() {
    // Use future-only terms from the fresh plan so we show upcoming courses
    final allTerms = ((_currentPlanDetail?['terms'] as List?) ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final futureTerms = _filterFutureTerms(allTerms);
    final courses = <Map<String, dynamic>>[];
    for (final t in futureTerms) {
      final items = (t['items'] as List?) ?? [];
      for (final item in items.take(2)) {
        if (item is Map<String, dynamic>) courses.add(item);
      }
      if (courses.length >= 3) break;
    }
    if (courses.isEmpty) {
      return [
        const Text('No courses loaded.',
            style: TextStyle(color: GPColors.subtext, fontSize: 12))
      ];
    }
    return courses.take(3).map((c) {
      final code = c['course_code'] as String? ?? 'N/A';
      final title = c['course_title'] as String? ?? '';
      final credits = (c['credits'] as num?)?.toInt() ?? 3;
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: GPColors.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: GPColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(code,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: GPColors.green)),
                  Text(title,
                      style: const TextStyle(
                          fontSize: 10, color: GPColors.subtext),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: GPColors.greenSoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$credits cr',
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: GPColors.green),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}

// ── Slider label ──────────────────────────────────────────────────────────

class _SliderLabel extends StatelessWidget {
  const _SliderLabel(this.text, this.active);
  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        color: active ? GPColors.green : GPColors.subtext,
      ),
    );
  }
}

// ── Toggle row ────────────────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  const _ToggleRow(
      {required this.label, required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13,
                color: GPColors.text,
                fontWeight: FontWeight.w500)),
        Switch(
          value: value,
          onChanged: onChanged,
          thumbColor: WidgetStateProperty.all(Colors.white),
          trackColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? GPColors.green
                  : const Color(0xFFCBD5E1)),
        ),
      ],
    );
  }
}


// ── Risk gauge ────────────────────────────────────────────────────────────

class _RiskGauge extends StatelessWidget {
  const _RiskGauge({required this.score});
  final int score;

  Color get _color => score > 60
      ? GPColors.riskCritical
      : score > 30
          ? GPColors.amber
          : GPColors.green;

  String get _label => score > 60 ? 'High' : score > 30 ? 'Medium' : 'Low';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GPColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: score / 100,
                  strokeWidth: 5.5,
                  backgroundColor: const Color(0xFFE2E8F0),
                  valueColor: AlwaysStoppedAnimation(_color),
                  strokeCap: StrokeCap.round,
                ),
                Center(
                  child: Text(
                    '$score%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: _color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'RISK SCORE',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: GPColors.subtext,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── KPI card ─────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
    this.badge,
    this.badgePosOrNeg = true,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;
  final String? badge;
  final bool badgePosOrNeg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: GPColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accentColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                      fontSize: 10,
                      color: GPColors.subtext,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: accentColor,
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: badgePosOrNeg
                          ? GPColors.greenSoft
                          : GPColors.riskCriticalSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: badgePosOrNeg
                            ? GPColors.green
                            : GPColors.riskCritical,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dynamic roadmap ───────────────────────────────────────────────────────

class _DynamicRoadmap extends StatelessWidget {
  const _DynamicRoadmap({required this.terms});
  final List<Map<String, dynamic>> terms;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: GPColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dynamic Roadmap View',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: GPColors.text),
          ),
          const SizedBox(height: 18),
          if (terms.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: GPColors.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                children: [
                  Icon(Icons.route_outlined, size: 32, color: GPColors.subtext),
                  SizedBox(height: 8),
                  Text(
                    'Run a simulation to see your dynamic roadmap.',
                    style: TextStyle(color: GPColors.subtext, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < terms.length; i++) ...[
                    _RoadmapTermNode(
                      name: terms[i]['term_name'] as String? ?? 'Term',
                      credits: (terms[i]['credits'] as num?)?.toInt() ?? 0,
                      courseCount: ((terms[i]['items'] as List?) ?? []).length,
                      isWip: terms[i]['status'] == 'wip',
                    ),
                    if (i < terms.length - 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 32),
                        child: Row(
                          children: [
                            Container(width: 20, height: 2, color: GPColors.border),
                            const Icon(Icons.arrow_forward_ios_rounded,
                                size: 10, color: GPColors.subtext),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RoadmapTermNode extends StatelessWidget {
  const _RoadmapTermNode({
    required this.name,
    required this.credits,
    required this.courseCount,
    this.isWip = false,
  });
  final String name;
  final int credits;
  final int courseCount;
  final bool isWip;

  Color _seasonBg(String season) => switch (season) {
        'FALL' => GPColors.fallBg,
        'SUMMER' => GPColors.summerBg,
        'WINTER' => GPColors.winterBg,
        _ => GPColors.springBg,
      };

  Color _seasonBorder(String season) => switch (season) {
        'FALL' => GPColors.fallBorder,
        'SUMMER' => GPColors.summerBorder,
        'WINTER' => GPColors.winterBorder,
        _ => GPColors.springBorder,
      };

  Color _seasonAccent(String season) => switch (season) {
        'FALL' => GPColors.fallAccent,
        'SUMMER' => GPColors.summerAccent,
        'WINTER' => GPColors.winterAccent,
        _ => GPColors.springAccent,
      };

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(' ');
    final season = parts.isNotEmpty ? parts.first.toUpperCase() : 'TERM';
    final year = parts.length > 1 ? parts.last : '';

    final Color bgColor = isWip
        ? const Color(0xFFFFFBEB)
        : _seasonBg(season);
    final Color borderColor = isWip
        ? const Color(0xFFFCD34D)
        : _seasonBorder(season);
    final Color accentColor = isWip
        ? const Color(0xFFD97706)
        : _seasonAccent(season);

    return Column(
      children: [
        Container(
          width: 100,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isWip ? Icons.sync_rounded : Icons.check_circle_rounded,
                  color: accentColor,
                  size: 20,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                season,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: accentColor,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                year,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: GPColors.text,
                ),
              ),
              const SizedBox(height: 6),
              if (isWip)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'In Progress',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
                ),
              if (credits > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '$credits cr',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
              ],
              if (courseCount > 0) ...[
                const SizedBox(height: 2),
                Text(
                  '$courseCount courses',
                  style: const TextStyle(
                    fontSize: 9,
                    color: GPColors.subtext,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Optimization banner ───────────────────────────────────────────────────

class _OptimizationBanner extends StatelessWidget {
  const _OptimizationBanner();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: GPColors.accentInk,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome,
                color: GPColors.green2, size: 22),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Run a Simulation',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Adjust the Max Credits and Summer toggles on the left, then tap Run Simulation to explore different graduation paths.',
                  style: TextStyle(
                      color: Color(0xFF86EFAC), fontSize: 12, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}
