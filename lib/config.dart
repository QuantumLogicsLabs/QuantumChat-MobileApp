import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// QuantumChat API origin (no trailing slash, no `/api` suffix).
/// Override at build time: `--dart-define=API_URL=https://your-api.example`
/// or from Settings on device.
class AppConfig {
  static const _defined = String.fromEnvironment('API_URL');
  static const _aiDefined = String.fromEnvironment('AI_API_URL');
  static const productionFallback = 'https://quantum-chat-backend-six.vercel.app';
  static const productionAiFallback = 'https://ai.quantumlogicslimited.com/api/v1';

  /// Same backend as chat.quantumlogicslimited.com. For a local backend, pass
  /// `--dart-define=API_URL=http://10.0.2.2:5000` (Android emulator -> host).
  static String get defaultApiBase {
    if (_defined.isNotEmpty) return _defined.replaceAll(RegExp(r'/$'), '');
    return productionFallback;
  }

  /// QuantumAI companion API (`/api/v1`). Local: `--dart-define=AI_API_URL=http://10.0.2.2:5001/api/v1`.
  static String get defaultAiApiBase {
    if (_aiDefined.isNotEmpty) return _aiDefined.replaceAll(RegExp(r'/$'), '');
    return productionAiFallback;
  }

  /// TURN relay for live video, same as the website's VITE_TURN_* settings.
  /// `TURN_URL` accepts a comma-separated list (e.g. UDP 3478, TLS 443).
  static const _turnUrls = String.fromEnvironment('TURN_URL');
  static const _turnUsername = String.fromEnvironment('TURN_USERNAME');
  static const _turnCredential = String.fromEnvironment('TURN_CREDENTIAL');

  static List<Map<String, dynamic>> get iceServers {
    final turn = _turnUrls.split(',').map((u) => u.trim()).where((u) => u.isNotEmpty).toList();
    return [
      {
        'urls': ['stun:stun.l.google.com:19302', 'stun:stun.cloudflare.com:3478'],
      },
      if (turn.isNotEmpty) {'urls': turn, 'username': _turnUsername, 'credential': _turnCredential},
    ];
  }

  static String apiUrl(String base) => '${base.replaceAll(RegExp(r'/$'), '')}/api';

  static String signalUrl(String base) {
    if (base.contains('vercel.app')) return '';
    return base.replaceAll(RegExp(r'/$'), '');
  }

  static String deviceLabel() {
    final os = kIsWeb
        ? 'Web'
        : Platform.isIOS
            ? 'iOS'
            : Platform.isAndroid
                ? 'Android'
                : Platform.operatingSystem;
    final label = 'QuantumChat $os';
    return label.length <= 120 ? label : label.substring(0, 120);
  }
}
