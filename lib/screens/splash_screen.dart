import 'package:flutter/material.dart';
import '../game/game_assets.dart';
import '../game/game_screen.dart';
import '../services/storage_service.dart';

/// Splash / loading screen — shows oriented art while assets load.
/// Supports BOTH portrait and landscape (game itself locks to portrait).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bar;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _bar = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
    _boot();
  }

  Future<void> _boot() async {
    final start = DateTime.now();
    await StorageService().init();
    await GameAssets().loadAll();
    final elapsed = DateTime.now().difference(start);
    const min = Duration(milliseconds: 1400);
    if (elapsed < min) await Future.delayed(min - elapsed);
    _goToGame();
  }

  void _goToGame() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (context, animation, secondary) => const GameScreen(),
        transitionsBuilder: (context, anim, secondary, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _bar.dispose();
    super.dispose();
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
      body: Stack(fit: StackFit.expand, children: [
        Image.asset(bg, fit: BoxFit.cover),
        Positioned(
          left: 0, right: 0,
          bottom: MediaQuery.of(context).padding.bottom + 36,
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.55,
                child: _LoadingBar(controller: _bar),
              ),
              const SizedBox(height: 12),
              const Text('Loading…', style: TextStyle(
                color: Colors.white, fontSize: 15,
                fontWeight: FontWeight.w800, letterSpacing: 2,
                shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
              )),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _LoadingBar extends StatelessWidget {
  final AnimationController controller;
  const _LoadingBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 16,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, child) => LayoutBuilder(
            builder: (context, c) {
              final w    = c.maxWidth;
              final barW = w * 0.4;
              return Stack(children: [
                Positioned(
                  left: controller.value * (w + barW) - barW,
                  child: Container(
                    width: barW, height: 16,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [
                        Color(0xFFFFB300), Color(0xFFFFE082), Color(0xFFFFB300),
                      ]),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}
