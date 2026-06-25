import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'data_vault.dart';
import 'transport_pipe.dart';

// ============================================================
// ALERT CENTER — Push notifications (FCM + local display)
// ============================================================
// Push URL routing rules (per TZ):
//
//   • Cold-start tap (app killed):
//       Firebase delivers via getInitialMessage() at boot.
//       SAVE the url into the vault — the boot stage reads it back
//       and routes the user straight into ShellStage.
//
//   • Warm-tap (app backgrounded):
//       Firebase delivers via onMessageOpenedApp. Notify the live
//       listener (ShellStage) — DO NOT persist.
//
//   • Foreground arrival:
//       Firebase delivers via onMessage. Display a local
//       notification; if the user taps it we deliver to the
//       in-memory listener and again DO NOT persist.
//
// The OS-denied flag is set when the user dismisses the system
// permission dialog. Android will not show that dialog a second
// time, so without the flag a 3-day skip cooldown would expire
// and the "Accept" button would silently no-op.
// ============================================================

@pragma('vm:entry-point')
Future<void> _isolateBackgroundHandler(RemoteMessage message) async {
  // Background notifications are rendered by the system tray — no
  // foreground UI work happens in this isolate. The tap itself is
  // routed through onMessageOpenedApp / getInitialMessage on resume.
}

class AlertCenter {
  AlertCenter(this._vault);

  final DataVault _vault;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  FirebaseMessaging? _fcm;
  String? _token;
  bool _online = false;

  /// Fires when the user taps a notification while the app is warm.
  /// ShellStage subscribes to this and loads the URL into the WebView.
  void Function(String url)? onWarmTapUrl;

  /// Fires when FCM rotates the push token mid-session.
  void Function(String newToken)? onTokenRefreshed;

  String? get currentToken => _token;
  bool get isReady => _online;

  static const String _channelId = 'eggdash_priority';
  static const String _channelTitle = 'Egg Dash priority alerts';
  static const String _channelDesc =
      'Game updates, daily challenges and bonus events.';
  static const String _iconRes = '@drawable/ic_notification';

  Future<void> warmUp() async {
    try {
      await Firebase.initializeApp();
      _fcm = FirebaseMessaging.instance;

      FirebaseMessaging.onBackgroundMessage(_isolateBackgroundHandler);
      await _setupLocalChannel();

      _token = await _fcm!.getToken();
      _fcm!.onTokenRefresh.listen((rotated) {
        _token = rotated;
        onTokenRefreshed?.call(rotated);
      });

      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleWarmTap);

      final cold = await _fcm!.getInitialMessage();
      if (cold != null) _handleColdStartTap(cold);

      _online = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[AlertCenter] warmUp failed: $e');
    }
  }

  Future<void> _setupLocalChannel() async {
    const androidInit = AndroidInitializationSettings(_iconRes);
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final data = jsonDecode(payload);
          if (data is Map && data['url'] is String) {
            final url = data['url'] as String;
            if (url.isNotEmpty) onWarmTapUrl?.call(url);
          }
        } catch (_) {}
      },
    );

    if (!Platform.isAndroid) return;
    final droid = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await droid?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelTitle,
        description: _channelDesc,
        importance: Importance.high,
      ),
    );
  }

  /// Asks the OS to show the permission dialog. On denial we mark the
  /// vault so we never show the promo screen again.
  Future<bool> askForPermission() async {
    if (_fcm == null) return false;
    final settings = await _fcm!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final status = settings.authorizationStatus;
    final granted = status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;

    await _vault.writeNotificationGranted(granted);
    if (status == AuthorizationStatus.denied) {
      await _vault.markNotificationBlockedByOs();
    }
    return granted;
  }

  void _handleForegroundMessage(RemoteMessage message) async {
    final notif = message.notification;
    if (notif == null) return;
    if (!Platform.isAndroid) return;

    final imageUrl = notif.android?.imageUrl;
    AndroidNotificationDetails? details;

    if (imageUrl != null && imageUrl.isNotEmpty) {
      final bytes = await _downloadImage(imageUrl);
      if (bytes != null) {
        details = AndroidNotificationDetails(
          _channelId,
          _channelTitle,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: _iconRes,
          styleInformation: BigPictureStyleInformation(
            ByteArrayAndroidBitmap(bytes),
            largeIcon:
                const DrawableResourceAndroidBitmap('@mipmap/launcher_icon'),
          ),
        );
      }
    }

    details ??= const AndroidNotificationDetails(
      _channelId,
      _channelTitle,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: _iconRes,
    );

    final encodedPayload =
        message.data.isNotEmpty ? jsonEncode(message.data) : null;

    await _local.show(
      notif.hashCode,
      notif.title,
      notif.body,
      NotificationDetails(android: details),
      payload: encodedPayload,
    );
  }

  void _handleColdStartTap(RemoteMessage message) {
    final url = message.data['url'];
    if (url is String && url.isNotEmpty) {
      _vault.stashPushUrl(url);
    }
  }

  void _handleWarmTap(RemoteMessage message) {
    final url = message.data['url'];
    if (url is String && url.isNotEmpty) {
      onWarmTapUrl?.call(url);
    }
  }

  Future<Uint8List?> _downloadImage(String url) async {
    try {
      final resp = await TransportPipe.instance
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) return resp.bodyBytes;
    } catch (_) {}
    return null;
  }
}
