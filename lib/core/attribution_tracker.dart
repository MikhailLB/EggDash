import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';

import '../setup/analytics_secrets.dart';
import '../setup/core_settings.dart';
import 'transport_pipe.dart';

// ============================================================
// ATTRIBUTION TRACKER — AppsFlyer SDK + GCD retry
// ============================================================
// Wraps the AppsFlyer SDK and exposes three high-level operations:
//
//   • boot()              — initialise the SDK exactly once and
//                            register all three callbacks
//                            (conversion, deep-link, app-open).
//
//   • waitForConversion() — await the first conversion payload,
//                            with a 30-second hard cap. If the SDK
//                            reports `af_status = "Organic"` we
//                            wait five seconds and ask the GCD HTTP
//                            endpoint to confirm — AppsFlyer is
//                            known to mis-report attribution on the
//                            very first callback.
//
//   • buildPayload()      — merge the conversion map, the deep-link
//                            map and the app-open map into a single
//                            JSON dictionary, then layer the
//                            device-side fields on top.
//
// NEVER strip or rename fields from the SDK — the backend parses
// the whole payload and uses sparse keys to score installs.
// ============================================================

class AttributionTracker {
  AttributionTracker._();

  static final AttributionTracker instance = AttributionTracker._();

  AppsflyerSdk? _sdk;
  bool _ready = false;

  Map<String, dynamic>? _conversionPayload;
  Map<String, dynamic>? _deepLinkPayload;
  Map<String, dynamic>? _appOpenPayload;

  final Completer<Map<String, dynamic>> _conversionGate =
      Completer<Map<String, dynamic>>();
  final Completer<void> _deepLinkGate = Completer<void>();

  /// Initialise the SDK and register callbacks. Idempotent.
  Future<void> boot() async {
    if (_ready) return;
    _ready = true;

    final key = CoreSettings.attributionDevKey;
    if (key.isEmpty) {
      if (kDebugMode) {
        debugPrint('[AttributionTracker] dev key missing — SDK skipped');
      }
      _completeConversionWith(<String, dynamic>{});
      _completeDeepLink();
      return;
    }

    final options = AppsFlyerOptions(
      afDevKey: key,
      appId: CoreSettings.iosStoreId,
      showDebug: kDebugMode,
      timeToWaitForATTUserAuthorization: 10,
    );

    try {
      _sdk = AppsflyerSdk(options);

      _sdk!.onInstallConversionData(_handleConversion);
      _sdk!.onAppOpenAttribution(_handleAppOpen);
      _sdk!.onDeepLinking(_handleDeepLink);

      await _sdk!.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[AttributionTracker] initSdk failed: $e');
      _completeConversionWith(<String, dynamic>{});
      _completeDeepLink();
    }
  }

  void _handleConversion(dynamic data) async {
    if (kDebugMode) debugPrint('[AttributionTracker] conversion raw: $data');
    final map = _coerceMap(data);
    final payload = map['payload'] is Map
        ? Map<String, dynamic>.from(map['payload'] as Map)
        : map;

    if (payload['af_status'] == 'Organic') {
      // False-organic patch — wait, then ask GCD for the truth.
      await Future<void>.delayed(
        Duration(seconds: CoreSettings.gcdFalseOrganicDelaySeconds),
      );
      final fresh = await _refreshViaGcd();
      _conversionPayload = fresh ?? payload;
    } else {
      _conversionPayload = payload;
    }

    _completeConversionWith(_conversionPayload ?? <String, dynamic>{});
  }

  void _handleAppOpen(dynamic data) {
    final map = _coerceMap(data);
    final payload = map['payload'] is Map
        ? Map<String, dynamic>.from(map['payload'] as Map)
        : map;
    _appOpenPayload = payload;
  }

  void _handleDeepLink(dynamic result) {
    try {
      final dlMap = _coerceMap(result);
      final deepLinkObj = dlMap['deepLink'];
      if (deepLinkObj is Map) {
        final clickEvent = deepLinkObj['clickEvent'];
        if (clickEvent is Map) {
          _deepLinkPayload = Map<String, dynamic>.from(clickEvent);
        } else {
          _deepLinkPayload = Map<String, dynamic>.from(deepLinkObj);
        }
      }
    } catch (_) {}
    _completeDeepLink();
  }

  Future<Map<String, dynamic>?> _refreshViaGcd() async {
    final key = CoreSettings.attributionDevKey;
    if (key.isEmpty) return null;
    try {
      final uid = await _safeUid();
      if (uid == null || uid.isEmpty) return null;
      final appId = Platform.isIOS
          ? CoreSettings.iosStoreId
          : CoreSettings.bundleIdentifier;
      final url = buildGcdUrl(appId: appId, deviceId: uid);
      if (url.isEmpty) return null;

      final resp = await TransportPipe.instance
          .get(
            Uri.parse(url),
            headers: {'authorization': 'Bearer $key'},
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AttributionTracker] GCD retry failed: $e');
    }
    return null;
  }

  Future<String?> _safeUid() async {
    if (_sdk == null) return null;
    try {
      return await _sdk!.getAppsFlyerUID();
    } catch (_) {
      return null;
    }
  }

  /// Awaits the first conversion payload, capped at 30 s.
  Future<Map<String, dynamic>> waitForConversion({Duration? cap}) {
    return _conversionGate.future.timeout(
      cap ?? CoreSettings.firstLaunchAttributionWindow,
      onTimeout: () => <String, dynamic>{},
    );
  }

  /// Awaits the deep-link callback, capped at 5 s.
  Future<void> waitForDeepLink() {
    return _deepLinkGate.future
        .timeout(const Duration(seconds: 5), onTimeout: () {});
  }

  /// Merges everything we have plus device-side fields into a single
  /// JSON dictionary that the backend expects.
  Future<Map<String, dynamic>> buildPayload({
    required String locale,
    String? pushToken,
  }) async {
    final body = <String, dynamic>{};

    // Attribution wins over deep-link wins over app-open — same
    // priority as the reference template, but we use addAll for the
    // first source and putIfAbsent for the rest so we don't clobber.
    if (_conversionPayload != null) body.addAll(_conversionPayload!);
    _deepLinkPayload?.forEach((k, v) => body.putIfAbsent(k, () => v));
    _appOpenPayload?.forEach((k, v) => body.putIfAbsent(k, () => v));

    body['af_id'] = await _safeUid() ?? '';
    body['bundle_id'] = CoreSettings.bundleIdentifier;
    body['os'] = Platform.isAndroid ? 'Android' : 'iOS';
    body['store_id'] = CoreSettings.storeIdentifier;
    body['locale'] = locale;

    if (pushToken != null && pushToken.isNotEmpty) {
      body['push_token'] = pushToken;
    }
    final fbProject = CoreSettings.firebaseProjectNumber;
    if (fbProject.isNotEmpty) body['firebase_project_id'] = fbProject;

    if (kDebugMode) {
      debugPrint('[AttributionTracker] payload: ${jsonEncode(body)}');
    }
    return body;
  }

  void _completeConversionWith(Map<String, dynamic> map) {
    if (!_conversionGate.isCompleted) _conversionGate.complete(map);
  }

  void _completeDeepLink() {
    if (!_deepLinkGate.isCompleted) _deepLinkGate.complete();
  }

  Map<String, dynamic> _coerceMap(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }
}
