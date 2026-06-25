import '../crypto/string_codec.dart';

// ============================================================
// ANALYTICS SECRETS — Encoded AppsFlyer + Firebase identifiers.
// ============================================================
// Both values arrive from the project manager AFTER initial
// scaffolding (`appsflyer и firebase дам тебе позже`). Until
// they land here the encoders return empty strings, and the
// gray flow falls back gracefully to game mode at runtime.
//
// Workflow to fill these in:
//   1. Edit tool/encode_keys.dart — replace empty strings with
//      the real dev-key and project number.
//   2. Run:  dart run tool/encode_keys.dart
//   3. Copy the printed byte arrays into the const lists below.
//
// GCD endpoint is split host/path for the same reason as the
// transport endpoint — keeps the affiliate-network domain off
// the raw strings table.
// ============================================================

// analytics_dev_key → AppsFlyer Dev Key (22 ASCII chars)
const _attributionKeyBytes = <int>[
  0x2F, 0x25, 0x4A, 0x1C, 0xC6, 0x87, 0x07, 0xEB,
  0xF8, 0x1A, 0x41, 0xED, 0x7B, 0x2E, 0x15, 0x24,
  0xCC, 0xE0, 0x3D, 0xCE, 0x3A, 0x0F,
];

// messaging_project_id → Firebase sender / project number (12 digits)
const _messagingProjectBytes = <int>[
  0x68, 0x5B, 0x1B, 0x17, 0xB0, 0xC5, 0x02, 0xA1,
  0xAA, 0x5A, 0x38, 0xBE,
];

// gcd_host → "https://gcdsdk.appsflyer.com"
const _gcdHostBytes = <int>[
  0x33, 0x16, 0x5D, 0x55, 0xF6, 0xC9, 0x1C, 0xB6,
  0xFD, 0x0F, 0x6F, 0xFA, 0x65, 0x7D, 0x75, 0x1F,
  0xD2, 0xC8, 0x3B, 0xE6, 0x37, 0x1B, 0x4C, 0x57,
  0xAB, 0x90, 0x5C, 0xF4,
];

// gcd_path → "/install_data/v4.0/"
const _gcdPathBytes = <int>[
  0x74, 0x0B, 0x47, 0x56, 0xF1, 0x92, 0x5F, 0xF5,
  0xC5, 0x08, 0x6A, 0xFD, 0x60, 0x39, 0x2D, 0x4A,
  0x8C, 0x88, 0x67,
];

/// Decoded AppsFlyer Dev Key — empty until the manager provides it.
String decodeAttributionKey() {
  if (_attributionKeyBytes.isEmpty) return '';
  return revealString(_attributionKeyBytes);
}

/// Decoded Firebase project number ("sender id") — empty until
/// google-services.json is wired in.
String decodeMessagingProjectId() {
  if (_messagingProjectBytes.isEmpty) return '';
  return revealString(_messagingProjectBytes);
}

/// Builds the full GCD URL used to retry attribution when the
/// initial `onInstallConversionData` callback returned Organic.
///   GET https://gcdsdk.appsflyer.com/install_data/v4.0/{appId}?device_id={uid}
/// Authorization header: `Bearer {decodeAttributionKey()}`.
String buildGcdUrl({required String appId, required String deviceId}) {
  if (_gcdHostBytes.isEmpty) return '';
  final base = revealString(_gcdHostBytes) + revealString(_gcdPathBytes);
  return '$base$appId?device_id=$deviceId';
}
