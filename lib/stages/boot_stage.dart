import 'dart:io';

import 'package:flutter/material.dart';

import '../core/alert_center.dart';
import '../core/attribution_tracker.dart';
import '../core/data_vault.dart';
import '../core/net_sensor.dart';
import '../core/sync_gateway.dart';
import '../game/game_assets.dart';
import '../game/game_screen.dart';
import '../services/storage_service.dart';
import '../types/shell_mode.dart';
import 'alert_promo_stage.dart';
import 'dropout_stage.dart';
import 'shell_stage.dart' deferred as shell;

// ============================================================
// BOOT STAGE — Loading splash + gray/white routing brain
// ============================================================
// Replaces the original splash. Plays the existing WEBP loading
// art (portrait & landscape) and runs the state machine:
//
//   ShellMode.pending  → first-launch attribution flow
//   ShellMode.online   → returning gray user (push URL > config > saved)
//   ShellMode.offline  → returning white user (game-only forever)
//
// Visual differences from sibling gray-flow projects (fingerprint
// diversification):
//
//   • Static WEBP loading art (sibling uses MP4 video).
//   • Three discrete progress glyphs: hatching egg → cracked egg →
//     ready chicken — implemented as a custom painter ribbon, not
//     as 3 separate bar images.
//   • Bottom-anchored progress ribbon, not a centered single bar.
// ============================================================

enum _Progress { hatching, cracking, ready }

class BootStage extends StatefulWidget {
  const BootStage({
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
  State<BootStage> createState() => _BootStageState();
}

class _BootStageState extends State<BootStage>
    with SingleTickerProviderStateMixin {
  _Progress _stage = _Progress.hatching;
  bool _navigated = false;

  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _orchestrate();
  }

  @override
  void dispose() {
    widget.alertCenter.onTokenRefreshed = null;
    _shimmer.dispose();
    super.dispose();
  }

  Future<void> _orchestrate() async {
    widget.alertCenter.onTokenRefreshed = _onPushTokenRotated;
    await widget.alertCenter.warmUp();

    final mode = widget.vault.readShellMode();
    switch (mode) {
      case ShellMode.online:
        await _handleReturningOnline();
        break;
      case ShellMode.offline:
        await _handleReturningOffline();
        break;
      case ShellMode.pending:
        await _handleFirstLaunch();
        break;
    }
  }

  Future<void> _handleFirstLaunch() async {
    _setStage(_Progress.hatching);

    final online = await widget.netSensor.isOnline();
    if (!online) {
      _routeToDropout();
      return;
    }

    _setStage(_Progress.cracking);
    await widget.tracker.boot();
    await Future.wait<dynamic>([
      widget.tracker.waitForConversion(),
      widget.tracker.waitForDeepLink(),
    ]);

    final locale = Platform.localeName.replaceAll('-', '_');
    final payload = await widget.tracker.buildPayload(
      locale: locale,
      pushToken: widget.alertCenter.currentToken,
    );
    final reply = await widget.gateway.handshake(payload);

    if (reply.hasUsableUrl) {
      await widget.vault.writeShellMode(ShellMode.online);
      _setStage(_Progress.ready);
      await Future<void>.delayed(const Duration(milliseconds: 380));
      _routeToShell(reply.destination!);
    } else {
      await widget.vault.writeShellMode(ShellMode.offline);
      await GameAssets().loadAll();
      _setStage(_Progress.ready);
      await Future<void>.delayed(const Duration(milliseconds: 380));
      _routeToGame();
    }
  }

  Future<void> _handleReturningOnline() async {
    _setStage(_Progress.cracking);

    final online = await widget.netSensor.isOnline();
    if (!online) {
      _setStage(_Progress.ready);
      await Future<void>.delayed(const Duration(milliseconds: 280));
      _routeToDropout();
      return;
    }

    // Cold-start push: highest priority.
    final pushUrl = await widget.vault.takePushUrl();
    if (pushUrl != null && pushUrl.isNotEmpty) {
      _setStage(_Progress.ready);
      await Future<void>.delayed(const Duration(milliseconds: 280));
      _routeToShell(pushUrl);
      return;
    }

    final saved = await widget.vault.loadDestination();

    await widget.tracker.boot();
    await Future.wait<dynamic>([
      widget.tracker.waitForConversion(cap: const Duration(seconds: 10)),
      widget.tracker.waitForDeepLink(),
    ]);

    final locale = Platform.localeName.replaceAll('-', '_');
    final payload = await widget.tracker.buildPayload(
      locale: locale,
      pushToken: widget.alertCenter.currentToken,
    );
    final reply = await widget.gateway.handshake(payload);

    _setStage(_Progress.ready);
    await Future<void>.delayed(const Duration(milliseconds: 360));

    if (reply.hasUsableUrl) {
      _routeToShell(reply.destination!);
      return;
    }
    if (saved != null && saved.isNotEmpty) {
      _routeToShell(saved);
    } else {
      _routeToDropout();
    }
  }

  Future<void> _handleReturningOffline() async {
    _setStage(_Progress.cracking);
    await GameAssets().loadAll();
    // Preload the game's local storage so the GameScreen ticker
    // can read the player's saved coins/XP without waiting.
    await StorageService().init();
    _setStage(_Progress.ready);
    await Future<void>.delayed(const Duration(milliseconds: 520));
    _routeToGame();
  }

  void _onPushTokenRotated(String token) async {
    final locale = Platform.localeName.replaceAll('-', '_');
    final payload = await widget.tracker.buildPayload(
      locale: locale,
      pushToken: token,
    );
    // Fire-and-forget — backend reads the new token; we don't
    // need to update UI off the result.
    widget.gateway.handshake(payload);
  }

  void _setStage(_Progress p) {
    if (mounted) setState(() => _stage = p);
  }

  Future<void> _routeToShell(String url) async {
    if (_navigated || !mounted) return;
    _navigated = true;
    await shell.loadLibrary();
    await shell.primeShellEngine();
    if (!mounted) return;

    if (widget.vault.shouldOfferNotifications()) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AlertPromoStage(
            vault: widget.vault,
            center: widget.alertCenter,
            netSensor: widget.netSensor,
            targetUrl: url,
          ),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => shell.ShellStage(
            initialUrl: url,
            vault: widget.vault,
            center: widget.alertCenter,
            netSensor: widget.netSensor,
          ),
        ),
      );
    }
  }

  void _routeToGame() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const GameScreen()),
    );
  }

  void _routeToDropout() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DropoutStage(
          recoveryRoute: (_) => BootStage(
            vault: widget.vault,
            netSensor: widget.netSensor,
            tracker: widget.tracker,
            gateway: widget.gateway,
            alertCenter: widget.alertCenter,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final bg = isLandscape
        ? 'assets/Horizontal_Loading_Screen.webp'
        : 'assets/Vertical_Loading_Screen.webp';

    return Scaffold(
      backgroundColor: const Color(0xFF8ED0F0),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(bg, fit: BoxFit.cover),
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 38,
            child: Center(
              child: _ProgressRibbon(
                stage: _stage,
                shimmer: _shimmer,
                width: MediaQuery.of(context).size.width *
                    (isLandscape ? 0.45 : 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressRibbon extends StatelessWidget {
  const _ProgressRibbon({
    required this.stage,
    required this.shimmer,
    required this.width,
  });

  final _Progress stage;
  final AnimationController shimmer;
  final double width;

  double get _fillFraction {
    switch (stage) {
      case _Progress.hatching:
        return 0.18;
      case _Progress.cracking:
        return 0.62;
      case _Progress.ready:
        return 1.0;
    }
  }

  String get _caption {
    switch (stage) {
      case _Progress.hatching:
        return 'Warming the nest...';
      case _Progress.cracking:
        return 'Cracking shells...';
      case _Progress.ready:
        return 'Ready!';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: width,
          height: 22,
          child: AnimatedBuilder(
            animation: shimmer,
            builder: (_, _) => CustomPaint(
              painter: _RibbonPainter(
                fraction: _fillFraction,
                shimmer: shimmer.value,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _caption,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
          ),
        ),
      ],
    );
  }
}

class _RibbonPainter extends CustomPainter {
  _RibbonPainter({required this.fraction, required this.shimmer});

  final double fraction;
  final double shimmer;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(12),
    );

    final base = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, base);

    final border = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRRect(rrect, border);

    final fillWidth = size.width * fraction;
    if (fillWidth <= 0) return;

    final fillRect = Rect.fromLTWH(2, 2, fillWidth - 4, size.height - 4);
    final fillRRect =
        RRect.fromRectAndRadius(fillRect, const Radius.circular(10));

    canvas.save();
    canvas.clipRRect(fillRRect);

    final gradient = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFFC25C), Color(0xFFFFE9A6), Color(0xFFFFC25C)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, gradient);

    final shimmerX = (shimmer * (size.width + 80)) - 80;
    final shimmerPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(shimmerX, 0, 60, size.height));
    canvas.drawRect(
      Rect.fromLTWH(shimmerX, 0, 60, size.height),
      shimmerPaint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RibbonPainter old) =>
      old.fraction != fraction || old.shimmer != shimmer;
}
