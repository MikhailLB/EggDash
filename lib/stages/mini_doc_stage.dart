import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

// ============================================================
// MINI DOC STAGE — Lightweight WebView for legal pages.
// ============================================================
// Used by the game (white side) to render Privacy Policy and
// Support pages inside an in-app browser, instead of bouncing
// out to Chrome. Deliberately stripped down — no immersive
// mode, no JS injections, basic AppBar.
// ============================================================

class MiniDocStage extends StatefulWidget {
  const MiniDocStage({
    super.key,
    required this.title,
    required this.url,
  });

  final String title;
  final String url;

  @override
  State<MiniDocStage> createState() => _MiniDocStageState();
}

class _MiniDocStageState extends State<MiniDocStage> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFF6D9))
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF6D9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5A623),
        foregroundColor: const Color(0xFF3A1F00),
        title: Text(widget.title),
        elevation: 0,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9D43)),
              ),
            ),
        ],
      ),
    );
  }
}
