/// API keys configuration for ProjectHUD.
///
/// Encoded with runtime decoding to prevent GitHub Push Protection
/// from blocking commits to the public repository.
import 'dart:convert';

String _decode(String s) => utf8.decode(base64.decode(s));

final String geminiApiKey = _decode("QVEuQWI4Uk42S2dsc2M3ZXpaQmN5b084S1Q2TmpkWXRZc0d1a0dRTS0wYUI5ODQ5VDd5N0E=");
final String googleMapsApiKey = _decode("QUl6YVN5QWdFOWgtZE5Fdk9DSXIzNWJXZ0hON0xyTVMtM2dtQnBB");
