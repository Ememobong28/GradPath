import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'gradpath_config.dart';
import 'gradpath_theme.dart';

// ────────────────────────────────────────────────────────────
// RiskScreen — Risk Optimizer
// Used inside GradPathShell (no Scaffold of its own)
// ────────────────────────────────────────────────────────────

class RiskScreen extends StatefulWidget {
  const RiskScreen({super.key, this.studentId, this.planDetail});

  final int? studentId;
  final Map<String, dynamic>? planDetail;

  @override
  State<RiskScreen> createState() => _RiskScreenState();
}

class _RiskScreenState extends State<RiskScreen> {
  List<Map<String, dynamic>> _risks = [];
  bool _loading = true;
  int? _resolvedPlanId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Fast path: planDetail already provided
    final planId = widget.planDetail?['id'] as int?;
    if (planId != null) {
      _resolvedPlanId = planId;
      await _loadRisks(planId);
      return;
    }
    // Returning student path: look up latest plan via student
    if (widget.studentId != null) {
      try {
        final stuResp = await http.get(Uri.parse(
            '${GradPathConfig.backendBaseUrl}/api/students/${widget.studentId}'));
        if (stuResp.statusCode == 200) {
          final stuData = jsonDecode(stuResp.body) as Map<String, dynamic>;
          final latestPlanId = stuData['plan_id'] as int?;
          if (latestPlanId != null) {
            _resolvedPlanId = latestPlanId;
            await _loadRisks(latestPlanId);
            return;
          }
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadRisks([int? planId]) async {
    final id = planId ?? _resolvedPlanId ?? widget.planDetail?['id'] as int?;
    if (id == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final uri =
          Uri.parse('${GradPathConfig.backendBaseUrl}/api/plans/$id/risks');
      final resp = await http.get(uri);
      if (resp.statusCode == 200 && mounted) {
        // Backend returns a plain list: [{id, plan_id, kind, message}, ...]
        final raw = jsonDecode(resp.body);
        final items = raw is List
            ? raw.whereType<Map<String, dynamic>>().toList()
            : ((raw as Map)['risks'] as List? ?? [])
                .whereType<Map<String, dynamic>>()
                .toList();
        setState(() => _risks = items);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // All backend risks have kind="bottleneck" — they are moderate/schedule warnings.
  // We classify by message content: keywords → critical, rest → moderate.
  String _severity(Map<String, dynamic> r) {
    final msg = (r['message'] as String? ?? '').toLowerCase();
    final kind = (r['kind'] as String? ?? '').toLowerCase();
    if (kind == 'critical' ||
        msg.contains('cannot') ||
        msg.contains('impossible') ||
        msg.contains('no path')) {
      return 'critical';
    }
    return 'moderate';
  }

  int get _criticalCount =>
      _risks.where((r) => _severity(r) == 'critical').length;
  int get _moderateCount =>
      _risks.where((r) => _severity(r) == 'moderate').length;
  int get _lowCount => _risks.where((r) => _severity(r) == 'low').length;

  @override
  Widget build(BuildContext context) {
    final overallRisk = _criticalCount > 0
        ? 'High Risk'
        : _moderateCount > 0
            ? 'Moderate'
            : 'Low Risk';
    final riskColor = _criticalCount > 0
        ? GPColors.riskCritical
        : _moderateCount > 0
            ? GPColors.amber
            : GPColors.riskLow;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top bar ────────────────────────────────────────────
          Row(
            children: [
              // Gauge circle
              SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: _criticalCount > 0
                          ? 0.75
                          : _moderateCount > 0
                              ? 0.45
                              : 0.15,
                      strokeWidth: 10,
                      backgroundColor: const Color(0xFFE2E8F0),
                      color: riskColor,
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          overallRisk.split(' ').first,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: riskColor,
                          ),
                        ),
                        const Text(
                          'STATUS LEVEL',
                          style:
                              TextStyle(fontSize: 8, color: GPColors.subtext),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Risk Analysis',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: GPColors.text,
                      ),
                    ),
                    Text(
                      'Last scanned: ${DateTime.now().month}/${DateTime.now().day}/${DateTime.now().year} · ${TimeOfDay.now().format(context)}',
                      style: const TextStyle(
                          color: GPColors.subtext, fontSize: 12),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _RiskCountBadge(
                          label: 'CRITICAL ISSUES',
                          count: _criticalCount,
                          color: GPColors.riskCritical,
                        ),
                        const SizedBox(width: 12),
                        _RiskCountBadge(
                          label: 'MODERATE RISKS',
                          count: _moderateCount,
                          color: GPColors.amber,
                        ),
                        const SizedBox(width: 12),
                        _RiskCountBadge(
                          label: 'LOW IMPACTS',
                          count: _lowCount,
                          color: GPColors.riskLow,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: GPColors.green,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _loadRisks,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Re-calculate Risk'),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // ── Risk category cards ─────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _RiskCategoryCard(
                  title: 'Course Bottlenecks',
                  badge: 'CRITICAL',
                  badgeColor: GPColors.riskCritical,
                  icon: Icons.block_flipped,
                  items: _risks
                      .where((r) => _severity(r) == 'critical')
                      .take(3)
                      .map((r) {
                    final msg = r['message'] as String? ?? 'Bottleneck';
                    // Try to extract course code from message
                    final match = RegExp(r'[A-Z]{2,5}\s?\d{3}').firstMatch(msg);
                    return _RiskLine(
                      label:
                          match?.group(0) ?? msg.split(' ').take(3).join(' '),
                      value: 'Bottleneck',
                      color: GPColors.riskCritical,
                    );
                  }).toList(),
                  emptyMessage: _risks.isEmpty
                      ? 'No issues detected.'
                      : 'No critical issues.',
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _RiskCategoryCard(
                  title: 'Term-Only Constraints',
                  badge: 'SCHEDULE',
                  badgeColor: GPColors.blue,
                  icon: Icons.calendar_today_outlined,
                  items: _risks
                      .where((r) {
                        final msg =
                            (r['message'] as String? ?? '').toLowerCase();
                        return msg.contains('fall only') ||
                            msg.contains('spring only') ||
                            msg.contains('summer only') ||
                            msg.contains('term') ||
                            msg.contains('offered');
                      })
                      .take(3)
                      .map((r) {
                        final msg = r['message'] as String? ?? '';
                        final match =
                            RegExp(r'[A-Z]{2,5}\s?\d{3}').firstMatch(msg);
                        return _RiskLine(
                          label: match?.group(0) ?? 'Constraint',
                          value: msg.split('.').first.split(',').first,
                          color: GPColors.blue,
                        );
                      })
                      .toList(),
                  emptyMessage: 'No issues detected.',
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _RiskCategoryCard(
                  title: 'Credit Overload',
                  badge: 'WARNING',
                  badgeColor: GPColors.amber,
                  icon: Icons.battery_charging_full_outlined,
                  body: _buildOverloadBody(),
                  emptyMessage: 'No overloaded terms detected.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── At-Risk Courses Table ────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: GPColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'At-Risk Courses Detail',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: GPColors.text),
                    ),
                    TextButton(
                      onPressed: () {},
                      child: const Text(
                        'Export CSV',
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
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'No at-risk courses detected.',
                              style: TextStyle(color: GPColors.subtext),
                            ),
                          )
                        : _RiskTable(risks: _risks),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Smart Mitigation + Legend ────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _SmartMitigationCard(risks: _risks)),
              const SizedBox(width: 16),
              Expanded(flex: 1, child: _RiskLegendCard()),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildOverloadBody() {
    final terms = (widget.planDetail?['terms'] as List?) ?? [];
    final overload = terms.where((t) {
      if (t is! Map<String, dynamic>) return false;
      final cr = (t['credits'] as num?)?.toInt() ?? 0;
      return cr > 18;
    }).toList();
    if (overload.isEmpty) {
      return const Text(
        'No overloaded terms detected.',
        style: TextStyle(color: GPColors.subtext, fontSize: 12),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: overload.take(3).map((t) {
        final name = (t as Map)['term_name'] as String? ?? 'Term';
        final cr = (t['credits'] as num?)?.toInt() ?? 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: GPColors.riskModerateSoft,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: GPColors.amber.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
                Text(
                  '$cr credits',
                  style: const TextStyle(fontSize: 12, color: GPColors.amber),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Widgets ────────────────────────────────────────────────────────────────

class _RiskCountBadge extends StatelessWidget {
  const _RiskCountBadge(
      {required this.label, required this.count, required this.color});
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GPColors.border),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: GPColors.subtext,
                letterSpacing: 0.5),
          ),
          const SizedBox(height: 2),
          Text(
            '$count',
            style: TextStyle(
                fontSize: 26, fontWeight: FontWeight.w900, color: color),
          ),
        ],
      ),
    );
  }
}

class _RiskLine {
  const _RiskLine(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;
}

class _RiskCategoryCard extends StatelessWidget {
  const _RiskCategoryCard({
    required this.title,
    required this.badge,
    required this.badgeColor,
    required this.icon,
    this.items = const [],
    this.body,
    this.emptyMessage = 'No issues detected.',
  });

  final String title;
  final String badge;
  final Color badgeColor;
  final IconData icon;
  final List<_RiskLine> items;
  final Widget? body;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GPColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, size: 18, color: badgeColor),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: badgeColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: GPColors.text),
          ),
          const SizedBox(height: 12),
          body ??
              (items.isEmpty
                  ? Text(emptyMessage,
                      style: const TextStyle(
                          color: GPColors.subtext, fontSize: 12))
                  : Column(
                      children: items
                          .map((item) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.label,
                                        style: const TextStyle(
                                            fontSize: 12, color: GPColors.text),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      item.value,
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: item.color),
                                    ),
                                  ],
                                ),
                              ))
                          .toList(),
                    )),
        ],
      ),
    );
  }
}

class _RiskTable extends StatelessWidget {
  const _RiskTable({required this.risks});
  final List<Map<String, dynamic>> risks;

  static String _severityForKind(String kind, String msg) {
    final k = kind.toLowerCase();
    final m = msg.toLowerCase();
    if (k == 'critical' ||
        m.contains('cannot') ||
        m.contains('no path') ||
        m.contains('impossible')) {
      return 'critical';
    }
    return 'moderate';
  }

  @override
  Widget build(BuildContext context) {
    const headerStyle = TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: GPColors.subtext,
        letterSpacing: 0.5);

    return Column(
      children: [
        // Header row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            color: GPColors.bg,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
          ),
          child: const Row(
            children: [
              Expanded(flex: 1, child: Text('COURSE CODE', style: headerStyle)),
              Expanded(flex: 2, child: Text('NAME', style: headerStyle)),
              Expanded(
                  flex: 1, child: Text('FAILURE IMPACT', style: headerStyle)),
              Expanded(flex: 1, child: Text('STATUS', style: headerStyle)),
              Expanded(flex: 1, child: Text('ACTION', style: headerStyle)),
            ],
          ),
        ),
        const Divider(height: 1, color: GPColors.border),
        ...risks.take(5).map((r) {
          final kind = r['kind'] as String? ?? '—';
          final msg = r['message'] as String? ?? '—';
          final sev = _severityForKind(kind, msg);
          final match = RegExp(r'[A-Z]{2,5}\s?\d{3}').firstMatch(msg);
          final code = match?.group(0) ?? kind;
          final Color sevColor = sev == 'critical'
              ? GPColors.riskCritical
              : sev == 'moderate'
                  ? GPColors.amber
                  : GPColors.riskLow;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: GPColors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 1,
                  child: Text(
                    code,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: GPColors.green),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    msg.length > 60 ? '${msg.substring(0, 60)}…' : msg,
                    style: const TextStyle(fontSize: 12, color: GPColors.text),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    kind,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: sevColor),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: sevColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      sev,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: sevColor),
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: TextButton(
                    onPressed: () {},
                    child: const Text(
                      'View Alternatives',
                      style: TextStyle(color: GPColors.green, fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _SmartMitigationCard extends StatelessWidget {
  const _SmartMitigationCard({required this.risks});
  final List<Map<String, dynamic>> risks;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: GPColors.accentInk,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lightbulb_outline, color: GPColors.green2, size: 18),
              SizedBox(width: 8),
              Text(
                'Smart Mitigation',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'AI suggestions to reduce your current risk level.',
            style: TextStyle(color: Color(0xFF86EFAC), fontSize: 12),
          ),
          const SizedBox(height: 16),
          if (risks.isEmpty)
            const Text(
              'No mitigation needed. Your plan looks great.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            )
          else
            ...risks.take(2).map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (r['kind'] as String? ?? 'Risk').toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          r['message'] as String? ?? '',
                          style: const TextStyle(
                              color: Color(0xFF86EFAC), fontSize: 11),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                )),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () {},
              child: const Text(
                'Apply All Optimizations',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RiskLegendCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: GPColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'RISK LEGEND',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: GPColors.subtext,
                letterSpacing: 0.8),
          ),
          const SizedBox(height: 14),
          ...const [
            (GPColors.riskCritical, 'Critical: Immediate Delay'),
            (GPColors.amber, 'Moderate: Probable Delay'),
            (GPColors.riskLow, 'Safe: On-track Path'),
          ].map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: e.$1,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.$2,
                        style: const TextStyle(
                            fontSize: 11, color: GPColors.subtext),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
