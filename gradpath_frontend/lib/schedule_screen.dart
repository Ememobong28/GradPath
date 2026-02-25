import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'gradpath_config.dart';
import 'gradpath_theme.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({
    super.key,
    this.planDetail,
    this.studentId,
    this.inShell = false,
  });

  final Map<String, dynamic>? planDetail;
  final int? studentId;
  // When true the widget is embedded in GradPathShell and should not
  // render its own Scaffold or top nav bar.
  final bool inShell;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  Map<String, List<_ScheduledCourse>> _terms = {};
  Map<String, _TermStatus> _termStatuses = {};
  int _completedCredits = 0;
  int _totalCredits = 0;
  bool _transcriptLoading = false;
  // Credits required to graduate – used to detect when the WIP semester
  // is the student's final semester so no future planned terms are appended.
  final int _creditsRequired = 124;

  String? _hoveredTerm;
  final Map<String, int> _termCreditOverrides = {};
  String? _projectedGradTerm;
  double? _gpa;
  int? _gpaCredits;
  bool _reoptimizing = false;

  @override
  void initState() {
    super.initState();
    final plan = widget.planDetail;
    // Resolve studentId from widget param OR from the embedded plan field.
    final studentId =
        widget.studentId ?? (plan?['student_id'] as num?)?.toInt();
    if (plan != null) {
      _loadGpa(plan);
    }
    if (studentId != null) {
      // Show loading immediately so the raw plan never flashes before
      // the transcript-aware view is ready.
      _transcriptLoading = true;
      _loadTranscriptData(studentId);
    } else if (plan != null) {
      // No studentId — fall back to rendering the passed plan directly.
      _loadPlanDetail(plan);
    }
  }

  Future<void> _loadGpa(Map<String, dynamic> plan) async {
    final studentId = plan["student_id"] as int?;
    if (studentId == null) return;
    final uri = Uri.parse(
        "${GradPathConfig.backendBaseUrl}/api/students/$studentId/gpa");
    try {
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _gpa = (data["gpa"] as num?)?.toDouble();
        _gpaCredits = (data["credits"] as num?)?.toInt();
      });
    } catch (_) {
      // Ignore GPA lookup failures.
    }
  }

  Future<void> _reoptimize() async {
    final studentId =
        widget.studentId ?? (widget.planDetail?['student_id'] as num?)?.toInt();
    if (studentId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('No student profile found. Please restart the app.')),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _reoptimizing = true);

    try {
      // ── 1. Generate new plan ───────────────────────────────────────────────
      final genResp = await http.post(
        Uri.parse('${GradPathConfig.backendBaseUrl}/api/plans/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'student_id': studentId}),
      );
      if (genResp.statusCode < 200 || genResp.statusCode >= 300) {
        throw Exception('Re-optimization failed (${genResp.statusCode}).');
      }
      final planId =
          (jsonDecode(genResp.body) as Map<String, dynamic>)['plan_id'] as int?;
      if (planId == null) throw Exception('No plan ID returned.');

      // ── 2. Fetch plan detail ───────────────────────────────────────────────
      final planResp = await http
          .get(Uri.parse('${GradPathConfig.backendBaseUrl}/api/plans/$planId'));
      if (planResp.statusCode < 200 || planResp.statusCode >= 300) {
        throw Exception('Unable to load updated plan.');
      }
      final planDetail = jsonDecode(planResp.body) as Map<String, dynamic>;

      // ── 3. Fetch transcript ────────────────────────────────────────────────
      final transcriptResp = await http.get(Uri.parse(
          '${GradPathConfig.backendBaseUrl}/api/transcripts/$studentId'));
      final transcriptCourses = transcriptResp.statusCode == 200
          ? ((jsonDecode(transcriptResp.body)
                  as Map<String, dynamic>)['courses'] as List? ??
              [])
          : <dynamic>[];

      // ── 4. Fetch GPA ───────────────────────────────────────────────────────
      double? newGpa;
      int? newGpaCredits;
      try {
        final gpaResp = await http.get(Uri.parse(
            '${GradPathConfig.backendBaseUrl}/api/students/$studentId/gpa'));
        if (gpaResp.statusCode == 200) {
          final g = jsonDecode(gpaResp.body) as Map<String, dynamic>;
          newGpa = (g['gpa'] as num?)?.toDouble();
          newGpaCredits = (g['credits'] as num?)?.toInt();
        }
      } catch (_) {}

      if (!mounted) return;

      // ── 5. Build plan terms ────────────────────────────────────────────────
      final Map<String, List<_ScheduledCourse>> newTerms = {};
      final Map<String, int> newOverrides = {};
      String? newGradTerm;

      final planTermsList = (planDetail['terms'] as List?) ?? [];
      for (final t in planTermsList.whereType<Map<String, dynamic>>()) {
        final name = t['term_name'] as String?;
        if (name == null || name.trim().isEmpty) continue;
        final credits = (t['credits'] as num?)?.toInt();
        final items = (t['items'] as List?) ?? [];
        final fallback = credits != null && credits > 0
            ? (credits / items.length.clamp(1, 99)).round()
            : 3;
        newTerms[name] = items.whereType<Map<String, dynamic>>().map((item) {
          final code = item['course_code'] as String? ?? 'TBD';
          return _ScheduledCourse(
            code: code,
            title: item['course_title'] as String? ?? code,
            credits: (item['credits'] as num?)?.toInt() ?? fallback,
            explanation: item['explanation'] as String?,
          );
        }).toList();
        if (credits != null) newOverrides[name] = credits;
      }
      if (newTerms.isNotEmpty) newGradTerm = newTerms.keys.last;

      // ── 6. Merge transcript terms ──────────────────────────────────────────
      final Map<String, List<_ScheduledCourse>> built = {};
      final Map<String, _TermStatus> statuses = {};
      int completedCr = 0;
      int totalCr = 0;
      String? lastTx;

      if (transcriptCourses.isNotEmpty) {
        final grouped = <String, List<Map<String, dynamic>>>{};
        for (final c in transcriptCourses.whereType<Map<String, dynamic>>()) {
          final term = (c['term'] as String?) ?? 'Unknown';
          grouped.putIfAbsent(term, () => []).add(c);
        }
        final sorted = grouped.keys.toList()
          ..sort((a, b) => _termSortKey(a).compareTo(_termSortKey(b)));

        for (final term in sorted) {
          final tc = grouped[term]!;
          final isWip = tc.any((c) => (c['grade'] as String?) == 'WIP');
          final status = isWip ? _TermStatus.wip : _TermStatus.completed;
          final scheduled = tc
              .map((c) => _ScheduledCourse(
                    code: (c['course_code'] as String?) ?? 'TBD',
                    title: (c['course_title'] as String?) ?? 'Course',
                    credits: (c['credits'] as num?)?.toInt() ?? 3,
                  ))
              .toList();
          final termCr = scheduled.fold(0, (s, c) => s + c.credits);
          totalCr += termCr;
          if (status == _TermStatus.completed) completedCr += termCr;
          built[term] = scheduled;
          statuses[term] = status;
          lastTx = term;
        }
        // Detect if the WIP semester is the final semester
        final txOnlyCr = totalCr;
        final isGradSemester = txOnlyCr >= _creditsRequired;

        if (!isGradSemester) {
          // Merge future plan terms only when more credits are still needed
          for (final entry in newTerms.entries) {
            if (!built.containsKey(entry.key)) {
              built[entry.key] = entry.value;
              statuses[entry.key] = _TermStatus.planned;
              totalCr += entry.value.fold(0, (s, c) => s + c.credits);
            }
          }
        }
        // Remove overrides for transcript terms
        for (final t in built.keys) {
          if (statuses[t] == _TermStatus.completed ||
              statuses[t] == _TermStatus.wip) {
            newOverrides.remove(t);
          }
        }
        // Add next planned shell term only if more credits are needed
        if (!isGradSemester &&
            statuses.values.contains(_TermStatus.wip) &&
            lastTx != null) {
          final next = _nextTerm(lastTx);
          if (!built.containsKey(next)) {
            built[next] = [];
            statuses[next] = _TermStatus.planned;
          }
        }
        // Graduation term: the WIP semester itself when credits are met
        if (isGradSemester && lastTx != null) {
          newGradTerm = lastTx;
        } else if (lastTx != null) {
          newGradTerm = _nextTerm(lastTx);
        }
      } else {
        built.addAll(newTerms);
        for (final k in newTerms.keys) {
          statuses[k] = _TermStatus.planned;
          totalCr += newTerms[k]!.fold(0, (s, c) => s + c.credits);
        }
      }

      // ── 7. Single setState with all new data ───────────────────────────────
      setState(() {
        _terms = built.isNotEmpty ? built : newTerms;
        _termStatuses = statuses;
        _termCreditOverrides
          ..clear()
          ..addAll(newOverrides);
        _completedCredits = completedCr;
        _totalCredits = totalCr;
        _projectedGradTerm = newGradTerm;
        _gpa = newGpa;
        _gpaCredits = newGpaCredits;
        _reoptimizing = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _reoptimizing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  void _loadPlanDetail(Map<String, dynamic> plan) {
    final terms = (plan["terms"] as List?) ?? [];
    if (terms.isEmpty) return;

    final Map<String, List<_ScheduledCourse>> mapped = {};
    for (final term in terms) {
      if (term is! Map<String, dynamic>) continue;
      final name = term["term_name"] as String?;
      if (name == null || name.trim().isEmpty) continue;
      final credits = (term["credits"] as num?)?.toInt();
      final items = (term["items"] as List?) ?? [];
      final count = items.isEmpty ? 1 : items.length;
      final termFallbackCredits =
          credits != null && credits > 0 ? (credits / count).round() : 3;
      final courses = items.whereType<Map<String, dynamic>>().map((item) {
        final code = item["course_code"] as String? ?? "TBD";
        final title = item["course_title"] as String? ?? code;
        final explanation = item["explanation"] as String?;
        // Use per-item credits from the API; fall back to dividing the term total
        final itemCredits =
            (item["credits"] as num?)?.toInt() ?? termFallbackCredits;
        return _ScheduledCourse(
          code: code,
          title: title,
          credits: itemCredits,
          explanation: explanation,
        );
      }).toList();
      mapped[name] = courses;
      if (credits != null) {
        _termCreditOverrides[name] = credits;
      }
    }

    if (mapped.isNotEmpty) {
      _terms = mapped;
      _projectedGradTerm = mapped.keys.isNotEmpty ? mapped.keys.last : null;
    }
  }

  // ── Transcript loading ────────────────────────────────────────────────────

  Future<void> _loadTranscriptData(int studentId) async {
    if (!mounted) return;
    setState(() => _transcriptLoading = true);
    try {
      // Fetch transcript and fresh plan concurrently
      final transcriptFuture = http.get(Uri.parse(
          '${GradPathConfig.backendBaseUrl}/api/transcripts/$studentId'));
      final studentFuture = http.get(Uri.parse(
          '${GradPathConfig.backendBaseUrl}/api/students/$studentId'));

      final results = await Future.wait([transcriptFuture, studentFuture]);
      final txResp = results[0];
      final stResp = results[1];

      List<dynamic> courses = [];
      if (txResp.statusCode == 200) {
        final data = jsonDecode(txResp.body) as Map<String, dynamic>;
        courses = (data['courses'] as List?) ?? [];
      }

      // Fetch fresh plan detail so future terms are always up-to-date
      Map<String, dynamic>? freshPlan;
      if (stResp.statusCode == 200) {
        final stData = jsonDecode(stResp.body) as Map<String, dynamic>;
        final planId = stData['plan_id'] as int?;
        if (planId != null) {
          try {
            final planResp = await http.get(Uri.parse(
                '${GradPathConfig.backendBaseUrl}/api/plans/$planId'));
            if (planResp.statusCode == 200) {
              freshPlan = jsonDecode(planResp.body) as Map<String, dynamic>;
            }
          } catch (_) {}
        }
      }

      // Populate _terms from the fresh plan before building transcript view
      if (freshPlan != null && mounted) {
        _loadPlanDetail(freshPlan);
        // Also load GPA if the prop didn't have a plan to load it from
        if (widget.planDetail == null) _loadGpa(freshPlan);
      } else if (widget.planDetail != null && mounted) {
        _loadPlanDetail(widget.planDetail!);
      }

      if (courses.isNotEmpty && mounted) {
        _buildTermsFromTranscript(courses);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _transcriptLoading = false);
    }
  }

  void _buildTermsFromTranscript(List<dynamic> rawCourses) {
    // Group by term
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final c in rawCourses.whereType<Map<String, dynamic>>()) {
      final term = (c['term'] as String?) ?? 'Unknown';
      grouped.putIfAbsent(term, () => []).add(c);
    }

    // Sort chronologically
    final sortedTerms = grouped.keys.toList()
      ..sort((a, b) => _termSortKey(a).compareTo(_termSortKey(b)));

    final Map<String, List<_ScheduledCourse>> built = {};
    final Map<String, _TermStatus> statuses = {};
    int completedCr = 0;
    int totalCr = 0;
    String? lastTerm;

    for (final term in sortedTerms) {
      final termCourses = grouped[term]!;
      final isWip = termCourses.any((c) => (c['grade'] as String?) == 'WIP');
      final status = isWip ? _TermStatus.wip : _TermStatus.completed;

      final scheduled = termCourses.map((c) {
        final cr = (c['credits'] as num?)?.toInt() ?? 3;
        return _ScheduledCourse(
          code: (c['course_code'] as String?) ?? 'TBD',
          title: (c['course_title'] as String?) ?? 'Course',
          credits: cr,
        );
      }).toList();

      final termCr = scheduled.fold(0, (s, c) => s + c.credits);
      totalCr += termCr;
      if (status == _TermStatus.completed) completedCr += termCr;

      built[term] = scheduled;
      statuses[term] = status;
      lastTerm = term;
    }

    // ── Determine if the student is in their final semester ─────────────────
    // If total transcript credits (completed + WIP) already meet the graduation
    // requirement, the WIP semester IS the last semester – don't add any
    // plan-generated future terms and graduate at the WIP term itself.
    final txOnlyCredits = totalCr; // credits from transcript alone
    final isGraduatingSemester = txOnlyCredits >= _creditsRequired;

    if (!isGraduatingSemester) {
      // Merge plan-generated future terms (don't overwrite transcript terms)
      for (final entry in _terms.entries) {
        if (!built.containsKey(entry.key)) {
          built[entry.key] = entry.value;
          statuses[entry.key] = _TermStatus.planned;
          totalCr += entry.value.fold(0, (s, c) => s + c.credits);
        }
      }
    }

    // Remove plan-level credit overrides for any transcript-derived terms
    // so that completed/WIP terms always show the real per-course sum.
    for (final t in built.keys) {
      if (statuses[t] == _TermStatus.completed ||
          statuses[t] == _TermStatus.wip) {
        _termCreditOverrides.remove(t);
      }
    }

    // Only add a next planned shell term if the student still has remaining
    // credits to finish (i.e. this is NOT the graduation semester).
    final hasWip = statuses.values.contains(_TermStatus.wip);
    if (!isGraduatingSemester && hasWip && lastTerm != null) {
      final nextT = _nextTerm(lastTerm);
      if (!built.containsKey(nextT)) {
        built[nextT] = [];
        statuses[nextT] = _TermStatus.planned;
      }
    }

    // Projected graduation term:
    //  • If WIP semester completes the degree → graduate THIS term (not next)
    //  • Otherwise → next term after the last transcript entry
    final String? projGrad;
    if (isGraduatingSemester && lastTerm != null) {
      projGrad = lastTerm;
    } else if (lastTerm != null) {
      projGrad = _nextTerm(lastTerm);
    } else {
      projGrad = null;
    }

    setState(() {
      _terms = built;
      _termStatuses = statuses;
      _completedCredits = completedCr;
      _totalCredits = totalCr;
      _projectedGradTerm = projGrad;
    });
  }

  int _termSortKey(String termName) {
    final parts = termName.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return 0;
    final year = int.tryParse(parts.last) ?? 0;
    final season = parts.first.toLowerCase();
    final sv = switch (season) {
      'spring' => 1,
      'summer' => 2,
      'fall' => 3,
      _ => 0,
    };
    return year * 10 + sv;
  }

  String _nextTerm(String termName) {
    final parts = termName.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return termName;
    final year = int.tryParse(parts.last) ?? DateTime.now().year;
    final season = parts.first.toLowerCase();
    if (season == 'fall') return 'Spring ${year + 1}';
    return 'Fall $year';
  }

  // ── Course movement ───────────────────────────────────────────────────────

  void _moveCourse(_ScheduledCourse course, String from, String to) {
    if (from == to) return;
    if (_termStatuses[from] == _TermStatus.completed) return;
    if (_termStatuses[to] == _TermStatus.completed) return;
    setState(() {
      _terms[from]!.removeWhere((c) => c.id == course.id);
      _terms[to]!.add(course);
    });
  }

  bool _isTermCompleted(String termName) {
    final status = _termStatuses[termName];
    if (status != null) return status == _TermStatus.completed;
    // Fallback: date-based
    final parsed = _parseTerm(termName);
    if (parsed == null) return false;
    return DateTime.now().isAfter(parsed.endDate);
  }

  _TermStatus _getTermStatus(String termName) {
    final s = _termStatuses[termName];
    if (s != null) return s;
    return _isTermCompleted(termName)
        ? _TermStatus.completed
        : _TermStatus.planned;
  }

  _ParsedTerm? _parseTerm(String termName) {
    final parts = termName.trim().split(RegExp(r"\s+"));
    if (parts.length < 2) return null;
    final season = parts.first.toLowerCase();
    final year = int.tryParse(parts.last);
    if (year == null) return null;

    final endDate = switch (season) {
      "spring" => DateTime(year, 6, 1),
      "summer" => DateTime(year, 9, 1),
      "fall" => DateTime(year, 12, 31),
      _ => DateTime(year, 12, 31),
    };
    return _ParsedTerm(name: termName, endDate: endDate);
  }

  Widget _content(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final maxW = widget.inShell
        ? double.infinity
        : (width > 1400 ? 1280.0 : width * 0.96);
    final isWide = width > 1100;

    return SingleChildScrollView(
      padding: widget.inShell ? const EdgeInsets.all(24) : EdgeInsets.zero,
      child: Column(
        children: [
          if (!widget.inShell) ...[
            const SizedBox(height: 12),
            _TopNavBar(onBack: () => Navigator.of(context).pop()),
            const SizedBox(height: 18)
          ],
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProgressHeader(
                    isWide: isWide,
                    projectedTerm: _projectedGradTerm,
                    completedCredits: _completedCredits,
                    totalCredits: _totalCredits,
                    gpa: _gpa,
                    gpaCredits: _gpaCredits,
                    reoptimizing: _reoptimizing,
                    onReoptimize: _reoptimize,
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    "Term-by-Term Path",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: GPColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Your degree roadmap optimized for minimum time-to-graduation.",
                    style: TextStyle(color: GPColors.subtext),
                  ),
                  const SizedBox(height: 18),
                  if (_transcriptLoading && _terms.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: GPColors.green),
                            SizedBox(height: 12),
                            Text(
                              "Loading transcript\u2026",
                              style: TextStyle(color: GPColors.subtext),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    NotificationListener<ScrollNotification>(
                      // Prevent horizontal scroll events from bubbling up
                      // to the outer vertical scroller / iOS back gesture.
                      onNotification: (_) => true,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        dragStartBehavior: DragStartBehavior.down,
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _terms.keys.map((term) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 16),
                                child: SizedBox(
                                  width: 320,
                                  child: _TermColumn(term: term),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                  const _FooterBar(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.inShell) return _content(context);
    return Scaffold(body: _content(context));
  }

  /// Returns season-specific accent colors for a term name.
  static ({Color bg, Color border, Color accent}) _seasonColors(String term) {
    final lower = term.toLowerCase();
    if (lower.contains('fall')) {
      return (
        bg: GPColors.fallBg,
        border: GPColors.fallBorder,
        accent: GPColors.fallAccent
      );
    } else if (lower.contains('spring')) {
      return (
        bg: GPColors.springBg,
        border: GPColors.springBorder,
        accent: GPColors.springAccent
      );
    } else if (lower.contains('summer')) {
      return (
        bg: GPColors.summerBg,
        border: GPColors.summerBorder,
        accent: GPColors.summerAccent
      );
    } else {
      return (
        bg: GPColors.winterBg,
        border: GPColors.winterBorder,
        accent: GPColors.winterAccent
      );
    }
  }

  Widget _TermColumn({required String term}) {
    final courses = _terms[term]!;
    final isHot = _hoveredTerm == term;
    final status = _getTermStatus(term);
    final isCompleted = status == _TermStatus.completed;
    final isWip = status == _TermStatus.wip;
    final season = _seasonColors(term);

    return DragTarget<_DragPayload>(
      onWillAcceptWithDetails: (payload) {
        if (isCompleted) return false;
        setState(() => _hoveredTerm = term);
        return true;
      },
      onLeave: (_) => setState(() => _hoveredTerm = null),
      onAcceptWithDetails: (payload) {
        setState(() => _hoveredTerm = null);
        _moveCourse(payload.data.course, payload.data.fromTerm, term);
      },
      builder: (context, _, __) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isCompleted
                  ? GPColors.border
                  : isHot
                      ? season.accent.withOpacity(0.5)
                      : season.border,
              width: isHot ? 1.8 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: season.accent.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Season-colored header strip ─────────────────────
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isCompleted ? const Color(0xFFF1F5F9) : season.bg,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isCompleted ? GPColors.subtext : season.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        term,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: isCompleted ? GPColors.subtext : season.accent,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isCompleted) ...[
                      const SizedBox(width: 6),
                      const _StatusPill(
                          label: 'Completed', tone: _TagTone.success),
                    ] else if (isWip) ...[
                      const SizedBox(width: 6),
                      const _StatusPill(
                          label: 'In Progress', tone: _TagTone.warn),
                    ],
                    const SizedBox(width: 8),
                    _CreditsPill(
                        credits: _termCredits(courses, term),
                        color: isCompleted ? GPColors.subtext : season.accent),
                  ],
                ),
              ),
              // ── Course list ─────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (courses.isEmpty && !isCompleted) ...[
                      Container(
                        height: 80,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: GPColors.border, width: 1.2),
                        ),
                        child: const Center(
                          child: Text(
                            "Drag courses here",
                            style: TextStyle(
                                color: GPColors.subtext, fontSize: 12),
                          ),
                        ),
                      ),
                    ] else ...[
                      ...courses.map(
                        (course) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: isCompleted
                              ? _CourseCard(course: course, locked: true)
                              : Draggable<_DragPayload>(
                                  data: _DragPayload(
                                      course: course, fromTerm: term),
                                  feedback: Material(
                                    color: Colors.transparent,
                                    child: ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 360),
                                      child: _CourseCard(
                                          course: course, dragging: true),
                                    ),
                                  ),
                                  childWhenDragging: Opacity(
                                    opacity: 0.4,
                                    child: _CourseCard(course: course),
                                  ),
                                  child: _CourseCard(course: course),
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
      },
    );
  }

  int _termCredits(List<_ScheduledCourse> courses, String term) {
    final override = _termCreditOverrides[term];
    if (override != null) return override;
    return courses.fold(0, (sum, course) => sum + course.credits);
  }
}

class _TopNavBar extends StatelessWidget {
  const _TopNavBar({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          ),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: GPColors.greenSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: const Icon(Icons.school, size: 16, color: GPColors.green),
          ),
          const SizedBox(width: 8),
          const Text(
            "GradPath",
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: GPColors.text,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            "OPTIMIZED PLANNING",
            style: TextStyle(fontSize: 10, color: GPColors.subtext),
          ),
          const Spacer(),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.tune, size: 18),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.download, size: 18),
          ),
        ],
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.isWide,
    this.projectedTerm,
    this.completedCredits = 0,
    this.totalCredits = 0,
    this.gpa,
    this.gpaCredits,
    this.reoptimizing = false,
    this.onReoptimize,
  });
  final bool isWide;
  final String? projectedTerm;
  final int completedCredits;
  final int totalCredits;
  final double? gpa;
  final int? gpaCredits;
  final bool reoptimizing;
  final VoidCallback? onReoptimize;

  @override
  Widget build(BuildContext context) {
    final fraction = totalCredits > 0
        ? (completedCredits / totalCredits).clamp(0.0, 1.0)
        : 0.65;
    // Show actual completed (graded) transcript credits, not the GPA-endpoint
    // credit count which may span multiple transcript uploads.
    final creditsLabel = '$completedCredits credits';
    final gpaLabel = gpa != null ? gpa!.toStringAsFixed(2) : '--';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GPColors.border),
      ),
      child: Column(
        children: [
          // ── Row 1: progress bar + pills + button ─────────────
          Row(
            children: [
              const Text(
                "DEGREE PROGRESS",
                style: TextStyle(fontSize: 10.5, color: GPColors.subtext),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: fraction.toDouble(),
                    minHeight: 8,
                    backgroundColor: const Color(0xFFE2E8F0),
                    color: GPColors.green,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _ProjectedGradPill(isWide: isWide, term: projectedTerm),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: GPColors.green,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: reoptimizing ? null : onReoptimize,
                icon: reoptimizing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.refresh, size: 16),
                label: const Text("Re-optimize"),
              ),
            ],
          ),
          // ── Row 2: stat chips ────────────────────────────────
          const SizedBox(height: 10),
          Row(
            children: [
              _StatChip(
                icon: Icons.check_circle_outline,
                label: 'Completed',
                value: creditsLabel,
              ),
              const SizedBox(width: 10),
              _StatChip(
                icon: Icons.auto_graph,
                label: 'GPA',
                value: gpaLabel,
              ),
              const Spacer(),
              Text(
                '${(fraction * 100).round()}% of degree complete',
                style: const TextStyle(fontSize: 11, color: GPColors.subtext),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GPColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: GPColors.green),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 13, color: GPColors.subtext),
          ),
          Text(
            value,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: GPColors.text),
          ),
        ],
      ),
    );
  }
}

class _ProjectedGradPill extends StatelessWidget {
  const _ProjectedGradPill({required this.isWide, this.term});
  final bool isWide;
  final String? term;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: GPColors.greenSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_month, size: 14, color: GPColors.green),
          const SizedBox(width: 6),
          Text(
            isWide
                ? "Projected Graduation · ${term ?? 'May 2026'}"
                : (term ?? "May 2026"),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: GPColors.green,
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard(
      {required this.course, this.dragging = false, this.locked = false});

  final _ScheduledCourse course;
  final bool dragging;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: locked ? const Color(0xFFF8FAFC) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: course.highlighted ? GPColors.green : GPColors.border,
          width: course.highlighted ? 1.4 : 1,
        ),
        boxShadow: dragging
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CourseCodeChip(code: course.code),
              const Spacer(),
              Text(
                "${course.credits} CREDITS",
                style: const TextStyle(fontSize: 10.5, color: GPColors.subtext),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            course.title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: GPColors.text,
            ),
          ),
          if (course.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: course.tags.map((tag) => _TagChip(tag: tag)).toList(),
            ),
          ],
          if (course.highlighted) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEAFBF0),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: const Text(
                "Optimization Logic\nPlaced here because BIO 201 is Fall-only and required before BIO 302.",
                style: TextStyle(fontSize: 11, color: GPColors.accentInk),
              ),
            ),
          ],
          if (course.explanation != null) ...[
            const SizedBox(height: 10),
            _ExplanationTile(text: course.explanation!),
          ],
        ],
      ),
    );
  }
}

class _ExplanationTile extends StatefulWidget {
  const _ExplanationTile({required this.text});
  final String text;

  @override
  State<_ExplanationTile> createState() => _ExplanationTileState();
}

class _ExplanationTileState extends State<_ExplanationTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              size: 16,
              color: GPColors.subtext,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _expanded ? widget.text : "Tap to view constraint explanation",
                style: const TextStyle(fontSize: 11, color: GPColors.subtext),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.tone});

  final String label;
  final _TagTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      _TagTone.success => (const Color(0xFFEAFBF0), GPColors.green),
      _TagTone.warn => (const Color(0xFFFFF7ED), const Color(0xFFF97316)),
      _TagTone.info => (const Color(0xFFEFF6FF), const Color(0xFF2563EB)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class _ParsedTerm {
  const _ParsedTerm({required this.name, required this.endDate});

  final String name;
  final DateTime endDate;
}

class _CreditsPill extends StatelessWidget {
  const _CreditsPill({required this.credits, this.color});
  final int credits;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? GPColors.subtext;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withOpacity(0.2)),
      ),
      child: Text(
        "$credits Credits",
        style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _FooterBar extends StatelessWidget {
  const _FooterBar();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Spacer(),
        Text(
          "Optimization Algorithm v2.4.1",
          style: TextStyle(fontSize: 11, color: GPColors.subtext),
        ),
        SizedBox(width: 16),
        Text(
          "Privacy Policy",
          style: TextStyle(fontSize: 11, color: GPColors.subtext),
        ),
        SizedBox(width: 10),
        Text(
          "Help Center",
          style: TextStyle(fontSize: 11, color: GPColors.subtext),
        ),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.tag});
  final _CourseTag tag;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (tag.tone) {
      case _TagTone.success:
        bg = const Color(0xFFEAFBF0);
        fg = GPColors.green;
        break;
      case _TagTone.info:
        bg = const Color(0xFFEFF6FF);
        fg = const Color(0xFF2563EB);
        break;
      case _TagTone.warn:
        bg = const Color(0xFFFFF7ED);
        fg = const Color(0xFFB45309);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.2)),
      ),
      child: Text(
        tag.label,
        style: TextStyle(fontSize: 9.5, color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }
}

enum _TermStatus { completed, wip, planned }

/// Returns a vibrant color for a course code based on the subject prefix.
Color _courseCodeColor(String code) {
  final prefix = code.replaceAll(RegExp(r'[\s\-0-9]'), '').toUpperCase();
  if (prefix.startsWith('CS') ||
      prefix.startsWith('CSCI') ||
      prefix.startsWith('CIS')) {
    return const Color(0xFF2563EB); // blue
  } else if (prefix.startsWith('MATH') ||
      prefix.startsWith('MTH') ||
      prefix.startsWith('MAT')) {
    return const Color(0xFF7C3AED); // purple
  } else if (prefix.startsWith('ENG') || prefix.startsWith('ENGL')) {
    return const Color(0xFFF97316); // orange
  } else if (prefix.startsWith('BIO') || prefix.startsWith('BIOL')) {
    return const Color(0xFF16A34A); // green
  } else if (prefix.startsWith('CHEM') || prefix.startsWith('CHE')) {
    return const Color(0xFF0891B2); // teal
  } else if (prefix.startsWith('PHYS') || prefix.startsWith('PHY')) {
    return const Color(0xFFDB2777); // pink
  } else if (prefix.startsWith('ECON') || prefix.startsWith('ECO')) {
    return const Color(0xFF0D9488); // cyan-green
  } else if (prefix.startsWith('HIST') || prefix.startsWith('HIS')) {
    return const Color(0xFFC2410C); // red-orange
  } else if (prefix.startsWith('POLS') || prefix.startsWith('POL')) {
    return const Color(0xFF1D4ED8); // indigo
  } else if (prefix.startsWith('SOC') || prefix.startsWith('SOCI')) {
    return const Color(0xFF9333EA); // violet
  } else if (prefix.startsWith('PSYC') || prefix.startsWith('PSY')) {
    return const Color(0xFFE11D48); // rose
  } else if (prefix.startsWith('BUS') ||
      prefix.startsWith('BUSI') ||
      prefix.startsWith('MBA')) {
    return const Color(0xFF059669); // emerald
  } else {
    return GPColors.green;
  }
}

class _CourseCodeChip extends StatelessWidget {
  const _CourseCodeChip({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final color = _courseCodeColor(code);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        code,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: color,
          fontSize: 12,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _DragPayload {
  const _DragPayload({required this.course, required this.fromTerm});

  final _ScheduledCourse course;
  final String fromTerm;
}

class _ScheduledCourse {
  _ScheduledCourse({
    required this.code,
    required this.title,
    required this.credits,
    this.explanation,
  }) : id = "$code::$title";

  final String id;
  final String code;
  final String title;
  final int credits;
  final String? explanation;
  final bool highlighted = false;
  final List<_CourseTag> tags = const [];
}

class _CourseTag {
  const _CourseTag(this.label, this.tone);

  final String label;
  final _TagTone tone;
}

enum _TagTone { success, info, warn }
