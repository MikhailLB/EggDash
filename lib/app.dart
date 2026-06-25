import 'package:flutter/material.dart';

import 'core/alert_center.dart';
import 'core/attribution_tracker.dart';
import 'core/data_vault.dart';
import 'core/net_sensor.dart';
import 'core/sync_gateway.dart';
import 'stages/boot_stage.dart';

class EggDashApp extends StatelessWidget {
  const EggDashApp({
    super.key,
    required this.vault,
    required this.netSensor,
    required this.tracker,
    required this.gateway,
    required this.alertCenter,
  });

  final DataVault vault;
  final NetSensor netSensor;
  final AttributionTracker tracker;
  final SyncGateway gateway;
  final AlertCenter alertCenter;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Egg Dash',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0E1430),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFB300),
          secondary: Color(0xFF66BB6A),
          surface: Color(0xFF1B2347),
        ),
      ),
      home: BootStage(
        vault: vault,
        netSensor: netSensor,
        tracker: tracker,
        gateway: gateway,
        alertCenter: alertCenter,
      ),
    );
  }
}
