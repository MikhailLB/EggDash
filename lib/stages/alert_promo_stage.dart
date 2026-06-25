import 'package:flutter/material.dart';

import '../core/alert_center.dart';
import '../core/data_vault.dart';
import '../core/net_sensor.dart';
import '../setup/core_settings.dart';
import 'shell_stage.dart' deferred as shell;

// ============================================================
// ALERT PROMO STAGE — Push notification opt-in promo
// ============================================================
// Shown exactly once before the very first WebView entry, only
// if the OS hasn't already denied push and the user hasn't opted
// in yet. "Skip" applies a 3-day cooldown.
//
// Visual design notes — intentionally different from the gold
// glow buttons used by sibling gray-flow projects:
//
//   • Background: per-orientation PNG (Vertical / Horizontal).
//   • Primary action ("Accept"): rounded-square egg-yolk yellow
//     button with a dark-brown stroke, slight 3-D drop shadow.
//   • Secondary action ("Skip"): smaller ghost button with a
//     warm cream fill and brown outline (NOT a transparent text
//     link). Sits below Accept with 14dp gap.
//   • In landscape the two buttons sit side-by-side in a single
//     row, both about a third of the screen wide.
// ============================================================

class AlertPromoStage extends StatefulWidget {
  const AlertPromoStage({
    super.key,
    required this.vault,
    required this.center,
    required this.netSensor,
    required this.targetUrl,
  });

  final DataVault vault;
  final AlertCenter center;
  final NetSensor netSensor;
  final String targetUrl;

  @override
  State<AlertPromoStage> createState() => _AlertPromoStageState();
}

class _AlertPromoStageState extends State<AlertPromoStage> {
  bool _busy = false;

  Future<void> _onAccept() async {
    if (_busy) return;
    setState(() => _busy = true);

    final granted = await widget.center.askForPermission();
    if (!granted) {
      final until = DateTime.now().millisecondsSinceEpoch ~/ 1000 +
          CoreSettings.notificationRetryDelaySeconds;
      await widget.vault.writeNotificationCooldownEnd(until);
    }
    if (!mounted) return;
    _continue();
  }

  Future<void> _onSkip() async {
    if (_busy) return;
    setState(() => _busy = true);
    final until = DateTime.now().millisecondsSinceEpoch ~/ 1000 +
        CoreSettings.notificationRetryDelaySeconds;
    await widget.vault.writeNotificationCooldownEnd(until);
    if (!mounted) return;
    _continue();
  }

  Future<void> _continue() async {
    await shell.loadLibrary();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => shell.ShellStage(
          initialUrl: widget.targetUrl,
          vault: widget.vault,
          center: widget.center,
          netSensor: widget.netSensor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final bg = isLandscape
        ? 'assets/Notifications/Horizontal_Notifications_Screen.webp'
        : 'assets/Notifications/Vertical_Notifications_Screen.webp';

    return Scaffold(
      backgroundColor: const Color(0xFFFFEFC4),
      body: SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              bg,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: const Color(0xFFFFEFC4),
              ),
            ),
            if (!isLandscape)
              Positioned(
                left: size.width * 0.09,
                right: size.width * 0.09,
                bottom: size.height * 0.08,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PrimaryEggButton(
                      label: 'Accept',
                      busy: _busy,
                      onTap: _onAccept,
                    ),
                    const SizedBox(height: 14),
                    _GhostEggButton(
                      label: 'Skip',
                      enabled: !_busy,
                      onTap: _onSkip,
                    ),
                  ],
                ),
              )
            else
              Positioned(
                left: size.width * 0.10,
                right: size.width * 0.10,
                bottom: size.height * 0.08,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: _PrimaryEggButton(
                        label: 'Accept',
                        busy: _busy,
                        onTap: _onAccept,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _GhostEggButton(
                        label: 'Skip',
                        enabled: !_busy,
                        onTap: _onSkip,
                        compact: true,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryEggButton extends StatefulWidget {
  const _PrimaryEggButton({
    required this.label,
    required this.busy,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final bool busy;
  final VoidCallback onTap;
  final bool compact;

  @override
  State<_PrimaryEggButton> createState() => _PrimaryEggButtonState();
}

class _PrimaryEggButtonState extends State<_PrimaryEggButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final h = widget.compact ? 50.0 : 62.0;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: Container(
          height: h,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFD23F), Color(0xFFFFB200)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF4A2300), width: 2.4),
            boxShadow: const [
              BoxShadow(
                color: Color(0xFF4A2300),
                blurRadius: 0,
                offset: Offset(0, 5),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: widget.busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xFF4A2300)),
                  ),
                )
              : Text(
                  widget.label,
                  style: TextStyle(
                    color: const Color(0xFF3A1B00),
                    fontSize: widget.compact ? 17 : 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
        ),
      ),
    );
  }
}

class _GhostEggButton extends StatefulWidget {
  const _GhostEggButton({
    required this.label,
    required this.enabled,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final bool compact;

  @override
  State<_GhostEggButton> createState() => _GhostEggButtonState();
}

class _GhostEggButtonState extends State<_GhostEggButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final h = widget.compact ? 50.0 : 56.0;
    return GestureDetector(
      onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: widget.enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onTap();
            }
          : null,
      onTapCancel: widget.enabled
          ? () => setState(() => _pressed = false)
          : null,
      child: AnimatedOpacity(
        opacity: widget.enabled ? (_pressed ? 0.7 : 1.0) : 0.45,
        duration: const Duration(milliseconds: 80),
        child: Container(
          height: h,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3D0),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF4A2300), width: 2.4),
            boxShadow: const [
              BoxShadow(
                color: Color(0xFF4A2300),
                blurRadius: 0,
                offset: Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: TextStyle(
              color: const Color(0xFF4A2300),
              fontSize: widget.compact ? 16 : 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
