/// API keys configuration for ProjectHUD.
///
/// API keys are supplied at build time with --dart-define
/// (for example, from GitHub Actions secrets) and are never
/// committed to the repository. When no value is supplied,
/// the keys default to an empty string.
final String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
final String googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');
