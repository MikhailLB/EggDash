// ============================================================
// ENCODE KEYS — Tooling for obfuscating runtime secrets
// ============================================================
// Run with:    dart run tool/encode_keys.dart
//
// Fill the plaintext map below with whatever values need to be
// hidden (config endpoint host/path, AppsFlyer dev key, Firebase
// project number, GCD host/path, Chrome version fragments). The
// script prints Dart-ready byte arrays that can be pasted into
// lib/setup/*.dart.
//
// ⚠️ Always use `dart run`, never PowerShell foreach loops —
//    PowerShell overflows 32-bit integers on Windows and outputs
//    incorrect byte values, which manifests as HTTP 400 / "Invalid
//    HTTP header field value" errors at runtime.
//
// Re-run this script whenever the cipher seed in
// lib/crypto/string_codec.dart changes.
// ============================================================

// ignore_for_file: avoid_relative_lib_imports, avoid_print

import '../lib/crypto/string_codec.dart';

void main() {
  // Fill in plaintext values that need to be embedded as encoded bytes.
  // Leave a value empty to skip emitting it.
  final secrets = <String, String>{
    // -- Config endpoint (sync gateway) --
    'transport_host': 'https://eeggdassh.com',
    'transport_path': '/config.php',

    // -- AppsFlyer + Firebase --
    'analytics_dev_key': 'tGc9Ct4rbvJdz8NZnXuNam',
    'messaging_project_id': '392256180637',

    // -- GCD retry endpoint --
    // Plaintext: https://gcdsdk.appsflyer.com/install_data/v4.0/
    'gcd_host': 'https://gcdsdk.appsflyer.com',
    'gcd_path': '/install_data/v4.0/',

    // -- HTTP User-Agent fragments --
    'chrome_version': '132.0.6834.163',
    'webkit_version': '537.36',
  };

  for (final entry in secrets.entries) {
    final plaintext = entry.value;
    if (plaintext.isEmpty) {
      print('// ${entry.key}: <empty — fill before release>');
      print('');
      continue;
    }
    final bytes = hideString(plaintext);
    print('// ${entry.key} → "$plaintext"');
    print('const _${entry.key} = <int>[');
    for (var i = 0; i < bytes.length; i += 8) {
      final chunk = bytes
          .skip(i)
          .take(8)
          .map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}')
          .join(', ');
      print('  $chunk,');
    }
    print('];');
    print('');
  }
}
