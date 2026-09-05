import 'dart:convert';

/// Structured group payloads sealed inside per-member envelopes.
/// Schema must match `frontend/src/utils/groupPayload.js` for web/mobile interop.

String encodeGroupPayload(Map<String, dynamic> payload) {
  return jsonEncode({'__qc': 1, ...payload});
}

/// Parse a `__qc` group payload, or treat as plain text.
Map<String, dynamic> parseGroupPayload(String? text) {
  if (text == null || text.isEmpty) return {'type': 'text', 'body': text ?? ''};
  final trimmed = text.trim();
  if (!trimmed.startsWith('{')) return {'type': 'text', 'body': text};
  try {
    final obj = jsonDecode(trimmed);
    if (obj is Map && obj['__qc'] == 1 && obj['type'] != null) {
      return Map<String, dynamic>.from(obj);
    }
  } catch (_) {
    /* plain text */
  }
  return {'type': 'text', 'body': text};
}

String encodePoll({required String question, required List<String> options}) {
  return encodeGroupPayload({
    'type': 'poll',
    'question': question.trim(),
    'options': options.map((o) => o.trim()).where((o) => o.isNotEmpty).take(8).toList(),
  });
}

/// [location] maps to the web field `where` for interop.
String encodeEvent({
  required String title,
  String? when,
  String location = '',
  String notes = '',
}) {
  return encodeGroupPayload({
    'type': 'event',
    'title': title.trim(),
    'when': when ?? '',
    'where': location.trim(),
    'notes': notes.trim(),
  });
}

String encodeAnnouncement(String body) {
  return encodeGroupPayload({'type': 'announcement', 'body': body});
}
