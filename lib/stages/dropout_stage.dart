import 'package:flutter/material.dart';

// ============================================================
// DROPOUT STAGE — "No Internet" recovery screen
// ============================================================
// Shown either at boot if the very first sync can't go out, or
// after a connectivity drop inside ShellStage. The retry action
// pushes a fresh root screen supplied by the caller, so the
// stage doesn't need to know whether we're recovering from the
// splash, the WebView or anywhere else.
//
// The PNG asset already paints the full "No Internet Connection"
// composition (chicken + signal arc + headline + helper text), so
// we only overlay the single Try-Again button at the bottom.
// ============================================================

class DropoutStage extends StatefulWidget {
  const DropoutStage({super.key, required this.recoveryRoute});

  /// Builder used after the user taps Retry. Whatever the caller
  /// returns becomes the new root.
  final WidgetBuilder recoveryRoute;

  @override
  State<DropoutStage> createState() => _DropoutStageState();
}

class _DropoutStageState extends State<DropoutStage> {
  bool _waiting = false;

  Future<void> _tryAgain() async {
    if (_waiting) return;
    setState(() => _waiting = true);
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: widget.recoveryRoute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final bgAsset = isLandscape
        ? 'assets/Nowifi/Horizontal_Nowifi_Screen.webp'
        : 'assets/Nowifi/Vertical_Nowifi_Screen.webp';

    return Scaffold(
      backgroundColor: const Color(0xFFFFF6D9),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            bgAsset,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              color: const Color(0xFFFFF6D9),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final landscape = constraints.maxWidth > constraints.maxHeight;
                final btnWidth =
                    landscape ? constraints.maxWidth * 0.34 : double.infinity;

                return Padding(
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 36),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: btnWidth,
                        child: _ShellButton(
                          label: _waiting ? 'Cracking...' : 'Try Again',
                          busy: _waiting,
                          onTap: _tryAgain,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ShellButton extends StatefulWidget {
  const _ShellButton({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  State<_ShellButton> createState() => _ShellButtonState();
}

class _ShellButtonState extends State<_ShellButton>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 58,
          decoration: BoxDecoration(
            // Egg-shaped pill: high border radius + warm sunshine gradient
            // that we never reuse on AlertPromoStage / ShellStage UI.
            gradient: widget.busy
                ? LinearGradient(
                    colors: [
                      const Color(0xFFFFE9A6).withValues(alpha: 0.95),
                      const Color(0xFFFFD062).withValues(alpha: 0.95),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : const LinearGradient(
                    colors: [Color(0xFFFF9D43), Color(0xFFFFC25C)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
            borderRadius: const BorderRadius.all(Radius.elliptical(38, 28)),
            border: Border.all(color: const Color(0xFF5C2C00), width: 2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF5C2C00).withValues(alpha: 0.35),
                blurRadius: 0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: widget.busy
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.6,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Color(0xFF5C2C00)),
                      ),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Cracking...',
                      style: TextStyle(
                        color: Color(0xFF3A1F00),
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                )
              : Text(
                  widget.label,
                  style: const TextStyle(
                    color: Color(0xFF3A1F00),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
        ),
      ),
    );
  }
}
