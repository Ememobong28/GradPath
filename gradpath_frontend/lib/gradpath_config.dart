class GradPathConfig {
  static const collegeScorecardApiKey =
      String.fromEnvironment("COLLEGE_SCORECARD_API_KEY", defaultValue: "");

  static const backendBaseUrl = String.fromEnvironment("BACKEND_BASE_URL",
      defaultValue: "http://127.0.0.1:8000");

  static bool get hasCollegeScorecardKey =>
      collegeScorecardApiKey.trim().isNotEmpty;
}
