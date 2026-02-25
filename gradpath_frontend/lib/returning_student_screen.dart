import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'gradpath_config.dart';
import 'gradpath_theme.dart';
import 'gradpath_sidebar.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ReturningStudentScreen
// Lets a student who already has a profile re-enter their school-issued
// student ID and jump straight back into their last saved plan.
// ─────────────────────────────────────────────────────────────────────────────

class ReturningStudentScreen extends StatefulWidget {
  const ReturningStudentScreen({super.key, this.onNewStudent});

  final VoidCallback? onNewStudent;

  @override
  State<ReturningStudentScreen> createState() => _ReturningStudentScreenState();
}

class _ReturningStudentScreenState extends State<ReturningStudentScreen> {
  final _idController = TextEditingController();
  bool _loading = false;
  String? _error;

  static const _green = Color(0xFF34C16B);
  static const _softPanel = Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _prefillFromPrefs();
  }

  Future<void> _prefillFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('persisted_school_student_id');
    if (saved != null && saved.isNotEmpty && mounted) {
      _idController.text = saved;
    }
  }

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  Future<void> _resume() async {
    final id = _idController.text.trim();
    if (id.isEmpty) {
      setState(() => _error = 'Please enter your student ID.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // ── 1. Look up student by school-issued ID ────────────────────────────
      final lookupUri = Uri.parse(
        '${GradPathConfig.backendBaseUrl}/api/students/lookup'
        '?school_student_id=${Uri.encodeComponent(id)}',
      );
      final lookupResp = await http.get(lookupUri);

      if (lookupResp.statusCode == 404) {
        setState(() => _error = 'No account found for that student ID.\n'
            'Please complete the full onboarding to get started.');
        return;
      }
      if (lookupResp.statusCode != 200) {
        setState(() => _error =
            'Server error (${lookupResp.statusCode}). Please try again.');
        return;
      }

      final lookup = jsonDecode(lookupResp.body) as Map<String, dynamic>;
      final dbId = lookup['db_id'] as int;
      final firstName = (lookup['first_name'] as String?) ?? '';
      final lastName = (lookup['last_name'] as String?) ?? '';
      final major = (lookup['major'] as String?) ?? '';
      int? planId = lookup['plan_id'] as int?;

      // ── 2. If no plan yet — generate one ─────────────────────────────────
      if (planId == null) {
        final genResp = await http.post(
          Uri.parse('${GradPathConfig.backendBaseUrl}/api/plans/generate'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'student_id': dbId}),
        );
        if (genResp.statusCode < 200 || genResp.statusCode >= 300) {
          setState(
              () => _error = 'Could not generate a plan. Please try again.');
          return;
        }
        planId = (jsonDecode(genResp.body) as Map<String, dynamic>)['plan_id']
            as int?;
        if (planId == null) {
          setState(() => _error = 'Plan generation did not return a plan ID.');
          return;
        }
      }

      // ── 3. Fetch plan detail ──────────────────────────────────────────────
      final planResp = await http.get(
        Uri.parse('${GradPathConfig.backendBaseUrl}/api/plans/$planId'),
      );
      if (planResp.statusCode != 200) {
        setState(
            () => _error = 'Could not load plan details. Please try again.');
        return;
      }
      final planDetail = jsonDecode(planResp.body) as Map<String, dynamic>;

      // ── 4. Persist IDs locally ────────────────────────────────────────────
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('persisted_student_id', dbId);
      await prefs.setString('persisted_school_student_id', id);

      if (!mounted) return;

      // ── 5. Navigate to the shell ──────────────────────────────────────────
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GradPathShell(
            initialIndex: 0, // Dashboard first for returning users
            planDetail: planDetail,
            studentId: dbId,
            studentName: '$firstName $lastName'.trim().isEmpty
                ? 'Student'
                : '$firstName $lastName'.trim(),
            studentInfo: major,
          ),
        ),
      );
    } catch (e) {
      setState(() => _error = 'Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GPColors.bg,
      body: Center(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo + wordmark
                    GestureDetector(
                      onTap: () => Navigator.of(context)
                          .popUntil((route) => route.isFirst),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: GPColors.greenSoft,
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: const Color(0xFFBBF7D0)),
                            ),
                            child: const Icon(Icons.school,
                                size: 20, color: GPColors.green),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'GradPath',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: GPColors.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Card
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: GPColors.border),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x08000000),
                            blurRadius: 16,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Welcome back',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: GPColors.text,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Enter your school-issued student ID to pick up exactly where you left off.',
                            style: TextStyle(
                                color: GPColors.subtext,
                                fontSize: 13,
                                height: 1.5),
                          ),
                          const SizedBox(height: 24),

                          // Student ID field
                          const Text(
                            'Student ID',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: GPColors.text,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _idController,
                            autofocus: true,
                            textInputAction: TextInputAction.go,
                            onSubmitted: (_) => _resume(),
                            decoration: InputDecoration(
                              hintText: 'e.g. 12345678',
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              prefixIcon: const Icon(Icons.badge_outlined,
                                  size: 18, color: GPColors.subtext),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide:
                                    const BorderSide(color: GPColors.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide:
                                    const BorderSide(color: GPColors.border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide:
                                    const BorderSide(color: _green, width: 1.4),
                              ),
                              errorText: null,
                            ),
                          ),

                          // Error message
                          if (_error != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF1F2),
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: const Color(0xFFFECACA)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.error_outline,
                                      size: 16, color: Color(0xFFDC2626)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFFDC2626),
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 20),

                          // Resume button
                          SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _green,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _loading ? null : _resume,
                              child: _loading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Resume My Plan',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // New student link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "New to GradPath? ",
                          style:
                              TextStyle(color: GPColors.subtext, fontSize: 13),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).pop();
                            widget.onNewStudent?.call();
                          },
                          child: const Text(
                            "Let's get started",
                            style: TextStyle(
                              color: _green,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// end of file
