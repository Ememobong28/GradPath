import 'package:flutter/material.dart';
import 'gradpath_theme.dart';
import 'dashboard_screen.dart';
import 'schedule_screen.dart';
import 'whatif_screen.dart';
import 'risk_screen.dart';
import 'export_screen.dart';

// ────────────────────────────────────────────────────────────
// GradPathShell — Scaffold with persistent sidebar
// Nav indices: 0=Dashboard  1=My Plan  2=What-If  3=Risk  4=Export
// ────────────────────────────────────────────────────────────

class GradPathShell extends StatefulWidget {
  const GradPathShell({
    super.key,
    this.initialIndex = 0,
    this.planDetail,
    this.studentId,
    this.studentName,
    this.studentInfo,
  });

  final int initialIndex;
  final Map<String, dynamic>? planDetail;
  final int? studentId;
  final String? studentName;
  final String? studentInfo;

  @override
  State<GradPathShell> createState() => _GradPathShellState();
}

class _GradPathShellState extends State<GradPathShell> {
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
  }

  Widget _buildBody() {
    switch (_index) {
      case 0:
        return DashboardScreen(
          studentId: widget.studentId,
          planDetail: widget.planDetail,
          studentName: widget.studentName,
        );
      case 1:
        return ScheduleScreen(
          planDetail: widget.planDetail,
          studentId: widget.studentId,
          inShell: true,
        );
      case 2:
        return WhatIfScreen(
          studentId: widget.studentId,
          planDetail: widget.planDetail,
        );
      case 3:
        return RiskScreen(
          studentId: widget.studentId,
          planDetail: widget.planDetail,
        );
      case 4:
        return ExportScreen(
          studentId: widget.studentId,
          planDetail: widget.planDetail,
          studentName: widget.studentName,
        );
      default:
        return DashboardScreen(
          studentId: widget.studentId,
          planDetail: widget.planDetail,
          studentName: widget.studentName,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GPColors.bg,
      body: Row(
        children: [
          GradPathSidebar(
            currentIndex: _index,
            onNavigate: (i) => setState(() => _index = i),
            studentName: widget.studentName ?? 'Student',
            studentInfo: widget.studentInfo ?? '',
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// GradPathSidebar — collapsible: icons-only ↔ full labels
// ────────────────────────────────────────────────────────────

class GradPathSidebar extends StatefulWidget {
  const GradPathSidebar({
    super.key,
    required this.currentIndex,
    required this.onNavigate,
    required this.studentName,
    required this.studentInfo,
  });

  final int currentIndex;
  final ValueChanged<int> onNavigate;
  final String studentName;
  final String studentInfo;

  static const _navItems = [
    (Icons.dashboard_outlined, Icons.dashboard, 'Dashboard'),
    (Icons.map_outlined, Icons.map, 'My Plan'),
    (Icons.science_outlined, Icons.science, 'What-If'),
    (
      Icons.warning_amber_outlined,
      Icons.warning_amber_rounded,
      'Risk Analysis'
    ),
    (Icons.upload_file_outlined, Icons.upload_file, 'Export'),
  ];

  @override
  State<GradPathSidebar> createState() => _GradPathSidebarState();
}

class _GradPathSidebarState extends State<GradPathSidebar> {
  bool _collapsed = false;

  static const double _expandedWidth = 224;
  static const double _collapsedWidth = 62;

  @override
  Widget build(BuildContext context) {
    final w = _collapsed ? _collapsedWidth : _expandedWidth;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      width: w,
      decoration: const BoxDecoration(
        color: GPColors.sidebarBg,
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 12,
            offset: Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          // ── Logo + toggle ────────────────────────────────────
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: _collapsed ? 0 : 14, vertical: 4),
            child: Row(
              mainAxisAlignment: _collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.spaceBetween,
              children: [
                if (!_collapsed) ...[
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: GPColors.green2,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.school_rounded,
                            size: 18, color: Colors.white),
                      ),
                      const SizedBox(width: 10),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'GradPath',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            'OPTIMIZED PLANNING',
                            style: TextStyle(
                              color: Color(0xFF86EFAC),
                              fontSize: 8.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
                // toggle chevron
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _collapsed = !_collapsed),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      _collapsed ? Icons.chevron_right : Icons.chevron_left,
                      size: 18,
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // ── Nav items ───────────────────────────────────────
          Expanded(
            child: Column(
              children: List.generate(GradPathSidebar._navItems.length, (i) {
                final (outlinedIcon, filledIcon, label) =
                    GradPathSidebar._navItems[i];
                final active = i == widget.currentIndex;
                return _SidebarTile(
                  icon: active ? filledIcon : outlinedIcon,
                  label: label,
                  active: active,
                  collapsed: _collapsed,
                  onTap: () => widget.onNavigate(i),
                );
              }),
            ),
          ),
          // ── User profile ─────────────────────────────────────
          AnimatedOpacity(
            opacity: _collapsed ? 0 : 1,
            duration: const Duration(milliseconds: 160),
            child: IgnorePointer(
              ignoring: _collapsed,
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: GPColors.green2.withOpacity(0.3),
                      child: Text(
                        widget.studentName.isNotEmpty
                            ? widget.studentName[0].toUpperCase()
                            : 'S',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.studentName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          if (widget.studentInfo.isNotEmpty)
                            Text(
                              widget.studentInfo,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF86EFAC),
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ── Avatar only when collapsed ───────────────────────
          if (_collapsed)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Center(
                child: Tooltip(
                  message: widget.studentName,
                  child: CircleAvatar(
                    radius: 17,
                    backgroundColor: GPColors.green2.withOpacity(0.3),
                    child: Text(
                      widget.studentName.isNotEmpty
                          ? widget.studentName[0].toUpperCase()
                          : 'S',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // ── Settings ─────────────────────────────────────────
          if (!_collapsed)
            Padding(
              padding: const EdgeInsets.only(left: 18, bottom: 18),
              child: Row(
                children: [
                  Icon(Icons.settings_outlined,
                      size: 13, color: Colors.white.withOpacity(0.5)),
                  const SizedBox(width: 6),
                  Text(
                    'Account Settings',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          if (_collapsed) const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.collapsed,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(
      icon,
      size: 20,
      color: active ? Colors.white : Colors.white.withOpacity(0.6),
    );

    final tile = GestureDetector(
      onTap: onTap,
      child: Container(
        margin:
            EdgeInsets.symmetric(horizontal: collapsed ? 6 : 10, vertical: 3),
        padding:
            EdgeInsets.symmetric(horizontal: collapsed ? 0 : 12, vertical: 11),
        decoration: BoxDecoration(
          color: active ? GPColors.sidebarActive : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: collapsed
            ? Center(child: iconWidget)
            : Row(
                children: [
                  iconWidget,
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: TextStyle(
                      color:
                          active ? Colors.white : Colors.white.withOpacity(0.6),
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  if (active) ...[
                    const Spacer(),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: GPColors.green2,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );

    if (collapsed) {
      return Tooltip(
        message: label,
        preferBelow: false,
        child: tile,
      );
    }
    return tile;
  }
}
