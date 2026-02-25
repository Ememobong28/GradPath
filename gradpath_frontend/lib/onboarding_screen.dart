import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'gradpath_config.dart';
import 'gradpath_theme.dart';
import 'gradpath_sidebar.dart';
import 'returning_student_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  String? _major;
  String? _targetTerm;
  bool _honors = false;
  bool _summer = true;
  double _maxCredits = 15;

  int? _persistedStudentId;
  bool _loadingExistingUser = false;
  late final Future<void> _existingUserFuture;

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _studentIdController = TextEditingController();
  TextEditingController? _schoolFieldController;

  _SchoolOption? _selectedSchool;
  List<_SchoolOption> _schoolOptions = [];
  List<String> _majorOptions = [];

  final List<_SelectedUploadFile> _selectedFiles = [];
  bool _uploading = false;
  String? _uploadError;

  Timer? _schoolSearchTimer;

  static const _scorecardBaseUrl =
      "https://api.data.gov/ed/collegescorecard/v1/schools";

  final _fallbackMajors = const [
    "Computer Science",
    "Computer Engineering",
    "Software Engineering",
    "Data Science",
    "Information Systems",
    "Mathematics",
    "Statistics",
    "Biology",
    "Chemistry",
    "Physics",
    "Environmental Science",
    "Nursing",
    "Public Health",
    "Business",
    "Accounting",
    "Finance",
    "Marketing",
    "Economics",
    "Psychology",
    "Sociology",
    "Political Science",
    "Communications",
    "English",
    "History",
    "Education",
    "Architecture",
    "Mechanical Engineering",
    "Electrical Engineering",
    "Civil Engineering",
    "Aerospace Engineering",
    "Undeclared",
    "Other / Custom",
  ];

  final _terms = const [
    "Fall 2026",
    "Spring 2027",
    "Fall 2027",
    "Spring 2028",
    "Fall 2028",
    "Not sure yet",
  ];

  static const _actionGreen = Color(0xFF34C16B);
  static const _softPanel = Color(0xFFF8FAFC);

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: _softPanel,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: GPColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: GPColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _actionGreen, width: 1.3),
        ),
      );

  @override
  void initState() {
    super.initState();
    // Default graduation term: next Fall if before August, next Spring otherwise
    final now = DateTime.now();
    final String defaultTerm;
    if (now.month >= 8) {
      defaultTerm = 'Spring ${now.year + 1}';
    } else {
      defaultTerm = 'Fall ${now.year}';
    }
    _targetTerm = _terms.contains(defaultTerm) ? defaultTerm : _terms.first;
    _existingUserFuture = _loadExistingUser();
  }

  Future<void> _loadExistingUser() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getInt('persisted_student_id');
    if (savedId == null) return;

    setState(() => _loadingExistingUser = true);
    try {
      final uri =
          Uri.parse('${GradPathConfig.backendBaseUrl}/api/students/$savedId');
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _persistedStudentId = savedId;
          _firstNameController.text = (data['first_name'] as String?) ?? '';
          _lastNameController.text = (data['last_name'] as String?) ?? '';
          _studentIdController.text = (data['student_id'] as String?) ?? '';
          _honors = (data['honors'] as bool?) ?? false;
          _maxCredits = ((data['max_credits'] as int?) ?? 15).toDouble();
          _summer = (data['summer_ok'] as bool?) ?? true;
          if (data['target_grad_term'] != null) {
            final loadedTerm = data['target_grad_term'] as String;
            if (_terms.contains(loadedTerm)) {
              _targetTerm = loadedTerm;
            }
          }
          _major = data['major'] as String?;
          final schoolName = data['school'] as String?;
          if (schoolName != null && schoolName.isNotEmpty) {
            _selectedSchool = _SchoolOption(id: 0, name: schoolName, state: '');
            _schoolFieldController?.text = schoolName;
          }
        });
      } else {
        // Student not found or invalid — clear persisted ID
        await prefs.remove('persisted_student_id');
      }
    } catch (_) {
      // Network error — silently treat as new user
    } finally {
      if (mounted) setState(() => _loadingExistingUser = false);
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _studentIdController.dispose();
    _schoolSearchTimer?.cancel();
    super.dispose();
  }

  Future<void> _searchSchools(String query) async {
    if (query.trim().length < 2) {
      setState(() => _schoolOptions = []);
      return;
    }

    if (!GradPathConfig.hasCollegeScorecardKey) {
      return;
    }

    final uri = Uri.parse(_scorecardBaseUrl).replace(
      queryParameters: {
        "api_key": GradPathConfig.collegeScorecardApiKey,
        "school.name": query,
        "fields": "id,school.name,school.state",
        "per_page": "10",
      },
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = (data["results"] as List?) ?? [];
      final options = results
          .map((item) => _SchoolOption.fromApi(item as Map<String, dynamic>))
          .where((school) => school.name.isNotEmpty)
          .toList();

      setState(() => _schoolOptions = options);
    } catch (_) {
      // Ignore lookup errors for now.
    }
  }

  Future<void> _loadProgramsForSchool(_SchoolOption school) async {
    if (!GradPathConfig.hasCollegeScorecardKey) {
      return;
    }

    final uri = Uri.parse(_scorecardBaseUrl).replace(
      queryParameters: {
        "api_key": GradPathConfig.collegeScorecardApiKey,
        "id": school.id.toString(),
        "fields": "latest.programs.cip_4_digit",
        "keys_nested": "true",
        "per_page": "1",
        "all_programs_nested": "true",
      },
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = (data["results"] as List?) ?? [];
      if (results.isEmpty) return;

      final latest = (results.first as Map<String, dynamic>)["latest"]
          as Map<String, dynamic>?;
      final programs = latest?["programs"] as Map<String, dynamic>?;
      final cipList = programs?["cip_4_digit"] as List? ?? [];

      final titles = <String>{};
      for (final item in cipList) {
        if (item is String) {
          titles.add(item);
        } else if (item is Map<String, dynamic>) {
          final title =
              item["title"] ?? item["cip_4_digit_title"] ?? item["name"];
          if (title is String && title.trim().isNotEmpty) {
            titles.add(title.trim());
          }
        }
      }

      if (titles.isNotEmpty) {
        final sorted = titles.toList()..sort();
        setState(() => _majorOptions = sorted);
      }
    } catch (_) {
      // Ignore lookup errors for now.
    }
  }

  Future<void> _pickFiles() async {
    if (_uploading) return;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ["pdf", "csv"],
    );
    if (result == null) return;

    setState(() {
      _uploadError = null;
      for (final file in result.files) {
        final bytes = file.bytes;
        if (bytes == null) {
          _uploadError = "Unable to read ${file.name}. Please try again.";
          continue;
        }
        final lower = file.name.toLowerCase();
        final _UploadKind kind;
        if (lower.endsWith(".csv")) {
          kind = _UploadKind.transcript;
        } else if (lower.contains("transcript")) {
          kind = _UploadKind.transcript;
        } else if (lower.contains("audit") || lower.contains("degree")) {
          kind = _UploadKind.degreeAudit;
        } else {
          // Default PDF uploads to transcript since that is the primary
          // document students upload during onboarding.
          kind = _UploadKind.transcript;
        }
        _selectedFiles.add(
          _SelectedUploadFile(
            name: file.name,
            bytes: bytes,
            kind: kind,
          ),
        );
      }
    });
  }

  void _updateFileKind(int index, _UploadKind kind) {
    setState(() {
      _selectedFiles[index] = _selectedFiles[index].copyWith(kind: kind);
    });
  }

  void _removeFile(int index) {
    setState(() {
      _selectedFiles.removeAt(index);
    });
  }

  Future<Map<String, dynamic>> _updateStudent(int studentId) async {
    final uri =
        Uri.parse('${GradPathConfig.backendBaseUrl}/api/students/$studentId');
    final payload = {
      'first_name': _firstNameController.text.trim(),
      'last_name': _lastNameController.text.trim(),
      'school': _selectedSchool?.displayName,
      'student_id': _studentIdController.text.trim().isEmpty
          ? null
          : _studentIdController.text.trim(),
      'honors': _honors,
      'max_credits': _maxCredits.round(),
      'summer_ok': _summer,
      'target_grad_term': _targetTerm,
      'major': _major,
    };
    final response = await http.put(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Student profile could not be updated.');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _createStudent() async {
    final uri = Uri.parse("${GradPathConfig.backendBaseUrl}/api/students");
    final payload = {
      "first_name": _firstNameController.text.trim(),
      "last_name": _lastNameController.text.trim(),
      "school": _selectedSchool?.displayName,
      "student_id": _studentIdController.text.trim().isEmpty
          ? null
          : _studentIdController.text.trim(),
      "honors": _honors,
      "max_credits": _maxCredits.round(),
      "summer_ok": _summer,
      "target_grad_term": _targetTerm,
      "major": _major,
    };

    final response = await http.post(
      uri,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(payload),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception("Student profile could not be created.");
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> _uploadSelectedFiles(int studentId) async {
    for (var i = 0; i < _selectedFiles.length; i++) {
      final file = _selectedFiles[i];
      if (file.status == _UploadStatus.done) continue;
      setState(() {
        _selectedFiles[i] = file.copyWith(status: _UploadStatus.uploading);
      });

      try {
        final uri = _uploadUriForFile(studentId, file.kind);
        final request = http.MultipartRequest("POST", uri);
        request.files.add(
          http.MultipartFile.fromBytes(
            "file",
            file.bytes,
            filename: file.name,
          ),
        );
        final response = await request.send();
        final body = await response.stream.bytesToString();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(body.isNotEmpty ? body : "Upload failed");
        }
        setState(() {
          _selectedFiles[i] =
              file.copyWith(status: _UploadStatus.done, message: null);
        });
      } catch (err) {
        final message = _friendlyUploadError(err);
        setState(() {
          _selectedFiles[i] = file.copyWith(
            status: _UploadStatus.error,
            message: message,
          );
          _uploadError ??= message;
        });
      }
    }
  }

  String _friendlyUploadError(Object err) {
    final raw = err.toString();
    if (raw.contains("Failed to fetch") ||
        raw.contains("Connection refused") ||
        raw.contains("SocketException")) {
      return "Could not reach the backend. Check BACKEND_BASE_URL and make sure the API is running.";
    }
    return raw;
  }

  Uri _uploadUriForFile(int studentId, _UploadKind kind) {
    const base = GradPathConfig.backendBaseUrl;
    if (kind == _UploadKind.transcript) {
      return Uri.parse("$base/api/transcripts/upload")
          .replace(queryParameters: {"student_id": "$studentId"});
    }
    return Uri.parse("$base/api/documents/upload").replace(
      queryParameters: {
        "student_id": "$studentId",
        "kind": kind.backendValue,
      },
    );
  }

  Future<int> _generatePlan(int studentId) async {
    final uri =
        Uri.parse("${GradPathConfig.backendBaseUrl}/api/plans/generate");
    final response = await http.post(
      uri,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"student_id": studentId}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception("Plan generation failed.");
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final planId = data["plan_id"] as int?;
    if (planId == null) {
      throw Exception("Plan ID missing from response.");
    }
    return planId;
  }

  Future<Map<String, dynamic>> _fetchPlan(int planId) async {
    final uri = Uri.parse("${GradPathConfig.backendBaseUrl}/api/plans/$planId");
    final response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception("Unable to load plan details.");
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> _generatePlanFlow() async {
    if (_uploading) return;
    if (_firstNameController.text.trim().isEmpty ||
        _lastNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter your name.")),
      );
      return;
    }
    if (_studentIdController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Student ID is required.")),
      );
      return;
    }

    setState(() {
      _uploading = true;
      _uploadError = null;
    });

    try {
      // Ensure any async student-resume load has completed before we decide
      // whether to create a new student or reuse the persisted one.
      await _existingUserFuture;

      Map<String, dynamic> student;
      if (_persistedStudentId != null) {
        student = await _updateStudent(_persistedStudentId!);
      } else {
        student = await _createStudent();
        final newId = student['id'] as int;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('persisted_student_id', newId);
        await prefs.setString(
            'persisted_school_student_id', _studentIdController.text.trim());
        setState(() => _persistedStudentId = newId);
      }
      final studentId = student["id"] as int;

      if (_selectedFiles.isNotEmpty) {
        await _uploadSelectedFiles(studentId);
      }

      final planId = await _generatePlan(studentId);
      final planDetail = await _fetchPlan(planId);

      final firstName = student['first_name'] as String? ?? '';
      final lastName = student['last_name'] as String? ?? '';
      final studentName = '$firstName $lastName'.trim();
      final major = _major ?? '';

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GradPathShell(
            initialIndex: 1, // Open directly to My Plan
            planDetail: planDetail,
            studentId: studentId,
            studentName: studentName.isEmpty ? 'Student' : studentName,
            studentInfo: major,
          ),
        ),
      );
    } catch (err) {
      setState(() {
        _uploadError = err.toString();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Unable to generate plan.")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final maxW = width > 1200 ? 980.0 : width * 0.92;
    final isWide = width > 980;

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 14),
            const _OnboardingTopBar(),
            const SizedBox(height: 22),
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxW),
                child: Column(
                  children: [
                    if (!GradPathConfig.hasCollegeScorecardKey) ...[
                      const _MissingApiKeyBanner(),
                      const SizedBox(height: 12),
                    ],
                    if (_loadingExistingUser) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                    ],
                    if (_uploadError != null) ...[
                      _InlineErrorBanner(message: _uploadError!),
                      const SizedBox(height: 12),
                    ],
                    const Text(
                      "Welcome to GradPath",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: GPColors.text,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Let’s set up your academic profile to optimize your path to\ngraduation.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.5,
                        color: GPColors.subtext,
                      ),
                    ),
                    const SizedBox(height: 22),
                    _OnboardingCard(
                      title: "Data Import",
                      icon: Icons.cloud_upload_outlined,
                      footer: "Securely encrypted. We only read course data.",
                      child: _UploadPanel(
                        files: _selectedFiles,
                        uploading: _uploading,
                        onPickFiles: _pickFiles,
                        onRemoveFile: _removeFile,
                        onKindChanged: _updateFileKind,
                      ),
                    ),
                    const SizedBox(height: 16),
                    isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _academicProfileCard()),
                              const SizedBox(width: 16),
                              Expanded(child: _workloadCard()),
                            ],
                          )
                        : Column(
                            children: [
                              _academicProfileCard(),
                              const SizedBox(height: 16),
                              _workloadCard(),
                            ],
                          ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: 500,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _actionGreen,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _uploading ? null : _generatePlanFlow,
                        label: Text(
                          _uploading
                              ? "Generating Plan..."
                              : "Generate My Optimized Plan",
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const _OnboardingFooter(),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _academicProfileCard() {
    return _OnboardingCard(
      title: "Academic Profile",
      icon: Icons.school_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _LabeledField(
                  label: "First Name",
                  child: TextField(
                    controller: _firstNameController,
                    decoration: _fieldDecoration("First name"),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LabeledField(
                  label: "Last Name",
                  child: TextField(
                    controller: _lastNameController,
                    decoration: _fieldDecoration("Last name"),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _LabeledField(
            label: "School",
            child: Autocomplete<_SchoolOption>(
              displayStringForOption: (option) => option.displayName,
              optionsBuilder: (value) {
                if (value.text.trim().isEmpty) {
                  return const Iterable<_SchoolOption>.empty();
                }
                return _schoolOptions.where(
                  (option) => option.displayName
                      .toLowerCase()
                      .contains(value.text.toLowerCase()),
                );
              },
              onSelected: (option) {
                setState(() {
                  _selectedSchool = option;
                });
                _schoolFieldController?.text = option.displayName;
                _loadProgramsForSchool(option);
              },
              fieldViewBuilder: (context, controller, focusNode, _) {
                _schoolFieldController = controller;
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: _fieldDecoration("University or college"),
                  enabled: GradPathConfig.hasCollegeScorecardKey,
                  onChanged: (value) {
                    _schoolSearchTimer?.cancel();
                    _schoolSearchTimer = Timer(
                      const Duration(milliseconds: 300),
                      () => _searchSchools(value),
                    );
                  },
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                return _AutocompletePanel(
                  options: options.toList(),
                  onSelected: onSelected,
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _LabeledField(
            label: "Student ID *",
            child: TextField(
              controller: _studentIdController,
              decoration: _fieldDecoration("ID number (required)"),
            ),
          ),
          const SizedBox(height: 12),
          _LabeledField(
            label: "Primary Major",
            child: Autocomplete<String>(
              displayStringForOption: (option) => option,
              optionsBuilder: (value) {
                final source =
                    _majorOptions.isNotEmpty ? _majorOptions : _fallbackMajors;
                if (value.text.trim().isEmpty) {
                  return source.take(8);
                }
                return source.where(
                  (option) =>
                      option.toLowerCase().contains(value.text.toLowerCase()),
                );
              },
              onSelected: (option) => setState(() => _major = option),
              fieldViewBuilder: (context, controller, focusNode, _) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: _fieldDecoration("Select your major..."),
                  onChanged: (value) {
                    _major = value;
                  },
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                return _AutocompletePanel(
                  options: options.toList(),
                  onSelected: onSelected,
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            "Target Graduation Term",
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _targetTerm,
            decoration: _fieldDecoration("Select a term..."),
            items: _terms
                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
            onChanged: (value) => setState(() => _targetTerm = value),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _softPanel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: GPColors.border),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Honors Program",
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        "Include honors-only seminar requirements",
                        style: TextStyle(fontSize: 11, color: GPColors.subtext),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _honors,
                  onChanged: (value) => setState(() => _honors = value),
                  thumbColor: MaterialStateProperty.resolveWith((states) =>
                      states.contains(MaterialState.selected)
                          ? _actionGreen
                          : Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _workloadCard() {
    return _OnboardingCard(
      title: "Workload Settings",
      icon: Icons.tune,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                "Max credits per semester",
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.info_outline, size: 14, color: GPColors.subtext),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9F8F0),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Text(
                  "${_maxCredits.round()} Credits",
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _actionGreen,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _actionGreen,
              inactiveTrackColor: const Color(0xFFE2E8F0),
              thumbColor: _actionGreen,
              overlayColor: _actionGreen.withOpacity(0.15),
            ),
            child: Slider(
              value: _maxCredits,
              min: 12,
              max: 21,
              divisions: 9,
              label: _maxCredits.round().toString(),
              onChanged: (value) => setState(() => _maxCredits = value),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "BALANCED (12)",
                  style: TextStyle(fontSize: 10, color: GPColors.subtext),
                ),
                Text(
                  "INTENSE (21)",
                  style: TextStyle(fontSize: 10, color: GPColors.subtext),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _softPanel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: GPColors.border),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Summer Enrollment",
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        "Allow AI to suggest summer sessions",
                        style: TextStyle(fontSize: 11, color: GPColors.subtext),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _summer,
                  onChanged: (value) => setState(() => _summer = value),
                  thumbColor: MaterialStateProperty.resolveWith((states) =>
                      states.contains(MaterialState.selected)
                          ? _actionGreen
                          : Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEAFBF0),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: const Text(
              'Consistent credit loads and early prerequisite planning improve on-time graduation outcomes.',
              style: TextStyle(fontSize: 11.5, color: GPColors.accentInk),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingTopBar extends StatelessWidget {
  const _OnboardingTopBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          GestureDetector(
            onTap: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: GPColors.greenSoft,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFB7F7D0)),
                  ),
                  child:
                      const Icon(Icons.school, size: 16, color: GPColors.green),
                ),
                const SizedBox(width: 8),
                const Text(
                  "GradPath",
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    color: GPColors.text,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ReturningStudentScreen(),
                ),
              );
            },
            style: TextButton.styleFrom(
              foregroundColor: GPColors.green,
              backgroundColor: GPColors.greenSoft,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
                side: const BorderSide(color: Color(0xFFB7F7D0)),
              ),
            ),
            icon: const Icon(Icons.login_rounded, size: 15),
            label: const Text(
              'Sign in',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingCard extends StatelessWidget {
  const _OnboardingCard({
    required this.title,
    required this.icon,
    required this.child,
    this.footer,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GPColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GPColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAFBF0),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon,
                    color: _OnboardingScreenState._actionGreen, size: 14),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
          if (footer != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.lock, size: 12, color: GPColors.subtext),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    footer!,
                    style: const TextStyle(
                      color: GPColors.subtext,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _UploadPanel extends StatelessWidget {
  const _UploadPanel({
    required this.files,
    required this.uploading,
    required this.onPickFiles,
    required this.onRemoveFile,
    required this.onKindChanged,
  });

  final List<_SelectedUploadFile> files;
  final bool uploading;
  final VoidCallback onPickFiles;
  final ValueChanged<int> onRemoveFile;
  final void Function(int, _UploadKind) onKindChanged;

  @override
  Widget build(BuildContext context) {
    return _DashedBorder(
      radius: 12,
      dashLength: 6,
      dashGap: 4,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Text(
                    "Choose File",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  files.isEmpty
                      ? "No file chosen"
                      : "${files.length} file${files.length == 1 ? '' : 's'} selected",
                  style:
                      const TextStyle(fontSize: 11.5, color: GPColors.subtext),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: GPColors.greenSoft,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child:
                const Icon(Icons.description, color: GPColors.green, size: 18),
          ),
          const SizedBox(height: 10),
          const Text(
            "Upload your Transcript, Degree Audit,\nCourse Catalog and Pre-requisite List",
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
          ),
          const SizedBox(height: 6),
          const Text(
            "Drag and drop PDF files here, or click to browse",
            textAlign: TextAlign.center,
            style: TextStyle(color: GPColors.subtext, fontSize: 11.5),
          ),
          const SizedBox(height: 12),
          if (files.isNotEmpty) ...[
            ...List.generate(files.length, (index) {
              final file = files[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _UploadFileRow(
                  file: file,
                  uploading: uploading,
                  onRemove: () => onRemoveFile(index),
                  onKindChanged: (kind) => onKindChanged(index, kind),
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
          OutlinedButton(
            onPressed: uploading ? null : onPickFiles,
            style: OutlinedButton.styleFrom(
              foregroundColor: _OnboardingScreenState._actionGreen,
              side: const BorderSide(color: Color(0xFFBBF7D0)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text("Browse Files"),
          ),
        ],
      ),
    );
  }
}

class _UploadFileRow extends StatelessWidget {
  const _UploadFileRow({
    required this.file,
    required this.uploading,
    required this.onRemove,
    required this.onKindChanged,
  });

  final _SelectedUploadFile file;
  final bool uploading;
  final VoidCallback onRemove;
  final ValueChanged<_UploadKind> onKindChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GPColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file, size: 16, color: GPColors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  style: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                _UploadStatusPill(status: file.status),
                if (file.message != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    file.message!,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFFB91C1C),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<_UploadKind>(
            value: file.kind,
            onChanged: uploading
                ? null
                : (value) {
                    if (value != null) onKindChanged(value);
                  },
            items: _UploadKind.values
                .map(
                  (kind) => DropdownMenuItem(
                    value: kind,
                    child: Text(kind.label,
                        style: const TextStyle(fontSize: 11.5)),
                  ),
                )
                .toList(),
          ),
          IconButton(
            onPressed: uploading ? null : onRemove,
            icon: const Icon(Icons.close, size: 16),
          ),
        ],
      ),
    );
  }
}

class _UploadStatusPill extends StatelessWidget {
  const _UploadStatusPill({required this.status});

  final _UploadStatus status;

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (status) {
      _UploadStatus.queued => ("Queued", const Color(0xFF64748B)),
      _UploadStatus.uploading => ("Uploading...", const Color(0xFF2563EB)),
      _UploadStatus.done => ("Uploaded", const Color(0xFF16A34A)),
      _UploadStatus.error => ("Error", const Color(0xFFDC2626)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style:
            TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class _DashedBorder extends StatelessWidget {
  const _DashedBorder({
    required this.child,
    this.radius = 12,
    this.dashLength = 6,
    this.dashGap = 4,
  });

  final Widget child;
  final double radius;
  final double dashLength;
  final double dashGap;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: const Color(0xFFE2E8F0),
        radius: radius,
        dashLength: dashLength,
        dashGap: dashGap,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.dashLength,
    required this.dashGap,
  });

  final Color color;
  final double radius;
  final double dashLength;
  final double dashGap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + dashLength;
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.radius != radius ||
        oldDelegate.dashLength != dashLength ||
        oldDelegate.dashGap != dashGap;
  }
}

enum _UploadKind {
  transcript,
  degreeAudit,
  catalog,
  prereqList,
}

extension _UploadKindLabels on _UploadKind {
  String get label {
    return switch (this) {
      _UploadKind.transcript => "Transcript",
      _UploadKind.degreeAudit => "Degree Audit",
      _UploadKind.catalog => "Course Catalog",
      _UploadKind.prereqList => "Prerequisite List",
    };
  }

  String get backendValue {
    return switch (this) {
      _UploadKind.transcript => "transcript",
      _UploadKind.degreeAudit => "degree_audit",
      _UploadKind.catalog => "course_catalog",
      _UploadKind.prereqList => "prereq_list",
    };
  }
}

enum _UploadStatus { queued, uploading, done, error }

class _SelectedUploadFile {
  const _SelectedUploadFile({
    required this.name,
    required this.bytes,
    required this.kind,
    this.status = _UploadStatus.queued,
    this.message,
  });

  final String name;
  final Uint8List bytes;
  final _UploadKind kind;
  final _UploadStatus status;
  final String? message;

  _SelectedUploadFile copyWith({
    _UploadKind? kind,
    _UploadStatus? status,
    String? message,
  }) {
    return _SelectedUploadFile(
      name: name,
      bytes: bytes,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      message: message,
    );
  }
}

class _OnboardingFooter extends StatelessWidget {
  const _OnboardingFooter();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 740;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: isWide
          ? const Row(
              children: [
                Text(
                  "© 2026 GradPath AI Academic Planning.",
                  style: TextStyle(fontSize: 11, color: GPColors.subtext),
                ),
                Spacer(),
                Text(
                  "Privacy Policy",
                  style: TextStyle(fontSize: 11, color: GPColors.subtext),
                ),
                SizedBox(width: 16),
                Text(
                  "Terms of Service",
                  style: TextStyle(fontSize: 11, color: GPColors.subtext),
                ),
                SizedBox(width: 16),
                Text(
                  "Accessibility",
                  style: TextStyle(fontSize: 11, color: GPColors.subtext),
                ),
              ],
            )
          : const Column(
              children: [
                Text(
                  "© 2026 GradPath AI Academic Planning.",
                  style: TextStyle(fontSize: 11, color: GPColors.subtext),
                ),
                SizedBox(height: 8),
                Text(
                  "Privacy Policy   ·   Terms of Service   ·   Accessibility",
                  style: TextStyle(fontSize: 11, color: GPColors.subtext),
                ),
              ],
            ),
    );
  }
}

class _MissingApiKeyBanner extends StatelessWidget {
  const _MissingApiKeyBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: const Row(
        children: [
          Icon(Icons.key, size: 16, color: Color(0xFFB45309)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              "College Scorecard API key missing. Add COLLEGE_SCORECARD_API_KEY via --dart-define to enable school and major search.",
              style: TextStyle(fontSize: 11.5, color: Color(0xFF92400E)),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineErrorBanner extends StatelessWidget {
  const _InlineErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, size: 16, color: Color(0xFFB91C1C)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF991B1B)),
            ),
          ),
        ],
      ),
    );
  }
}

class _AutocompletePanel<T> extends StatelessWidget {
  const _AutocompletePanel({required this.options, required this.onSelected});

  final List<T> options;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240, minWidth: 280),
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: options.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final option = options[index];
              return InkWell(
                onTap: () => onSelected(option),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Text(
                    option.toString(),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SchoolOption {
  const _SchoolOption({
    required this.id,
    required this.name,
    required this.state,
  });

  final int id;
  final String name;
  final String state;

  String get displayName => state.isEmpty ? name : "$name · $state";

  factory _SchoolOption.fromApi(Map<String, dynamic> json) {
    return _SchoolOption(
      id: json["id"] as int? ?? 0,
      name: json["school.name"] as String? ?? "",
      state: json["school.state"] as String? ?? "",
    );
  }

  @override
  String toString() => displayName;
}
