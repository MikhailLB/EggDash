import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import '../setup/transport_secrets.dart';

// ============================================================
// TRANSPORT PIPE — Real-device User-Agent injection layer
// ============================================================
// Every outbound request from the gray side (config POST, GCD
// retry, push image download) is funneled through this client
// so it advertises a believable mobile browser User-Agent.
//
// The UA is built once from real device information (brand,
// model, build id, SDK level) and then cached. Chrome / WebKit
// version fragments live inside transport_secrets as XOR bytes
// so they are not greppable in the binary.
//
// The UA stays a plain mobile-browser string — no `appid` or
// `appname` suffix is appended. Anything that needs the app
// identity for the backend should send it explicitly in the
// request body / headers.
// ============================================================

class TransportPipe extends http.BaseClient {
  TransportPipe._();

  static final TransportPipe instance = TransportPipe._();

  final http.Client _inner = http.Client();
  String _userAgent = 'Mozilla/5.0';
  bool _prepared = false;

  /// Builds and caches the User-Agent for the current device.
  /// Must be called once before `runApp` so any service that uses
  /// the pipe immediately gets the correct header.
  Future<void> prepare() async {
    if (_prepared) return;
    _prepared = true;
    _userAgent = await _composeUserAgent();
  }

  String get userAgent => _userAgent;

  Future<String> _composeUserAgent() async {
    final chrome = _firstNotEmpty(decodeChromeVersion(), '132.0.6834.163');
    final webkit = _firstNotEmpty(decodeWebkitVersion(), '537.36');

    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final droid = await info.androidInfo;
        final sdk = droid.version.sdkInt;
        final model = droid.model;
        final brand = droid.brand;
        final build = droid.display.isNotEmpty ? droid.display : droid.id;
        return 'Mozilla/5.0 (Linux; Android $sdk; $brand $model '
            'Build/$build) AppleWebKit/$webkit (KHTML, like Gecko) '
            'Chrome/$chrome Mobile Safari/$webkit';
      } else if (Platform.isIOS) {
        final ios = await info.iosInfo;
        final formatted = ios.systemVersion.replaceAll('.', '_');
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $formatted like Mac OS X) '
            'AppleWebKit/$webkit (KHTML, like Gecko) '
            'Version/${ios.systemVersion} Mobile/15E148 Safari/$webkit';
      }
    } catch (_) {
      // fall through to a safe fallback below
    }

    if (Platform.isAndroid) {
      return 'Mozilla/5.0 (Linux; Android 15; SM-S931U '
          'Build/AP3A.240905.015.A2) AppleWebKit/$webkit (KHTML, like Gecko) '
          'Chrome/$chrome Mobile Safari/$webkit';
    }
    return 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
        'AppleWebKit/$webkit (KHTML, like Gecko) '
        'Version/17.5 Mobile/15E148 Safari/$webkit';
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.putIfAbsent('User-Agent', () => _userAgent);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

String _firstNotEmpty(String a, String b) => a.isNotEmpty ? a : b;
