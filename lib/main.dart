import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/alert_center.dart';
import 'core/attribution_tracker.dart';
import 'core/data_vault.dart';
import 'core/net_sensor.dart';
import 'core/sync_gateway.dart';
import 'core/transport_pipe.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase + App Check come first so any downstream HTTP/FCM call
  // already has a valid attestation header. Swallow exceptions — when
  // google-services.json isn't wired in yet we still want the game
  // half of the app to boot for QA / asset checks.
  try {
    await Firebase.initializeApp();
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
    );
  } catch (_) {}

  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // Build the HTTP UA cache before any service that uses it.
  await TransportPipe.instance.prepare();

  final vault = DataVault.instance;
  await vault.bootstrap();

  final netSensor = NetSensor.instance;
  final tracker = AttributionTracker.instance;
  final gateway = SyncGateway(vault);
  final alertCenter = AlertCenter(vault);

  runApp(EggDashApp(
    vault: vault,
    netSensor: netSensor,
    tracker: tracker,
    gateway: gateway,
    alertCenter: alertCenter,
  ));
}
