import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../core/alert_center.dart';
import '../core/data_vault.dart';
import '../core/net_sensor.dart';
import '../core/transport_pipe.dart';
import 'dropout_stage.dart';

// ============================================================
// SHELL STAGE — Full-screen WebView host (gray mode)
// ============================================================
// Lifecycle / behaviour highlights:
//
//   • Immersive system UI (status bar + nav bar both hidden).
//   • Both orientations enabled; status bar padding is added
//     manually in portrait but stripped in landscape.
//   • Hardware back goes through WebView history; never exits.
//   • Connectivity is monitored via NetSensor.offlineStream
//     (debounced ~700 ms) — short VPN handshake blips no longer
//     flash the no-internet screen.
//   • onWebResourceError flips a spinner overlay *immediately*
//     before re-probing DNS, so the user never sees Android's
//     native ERR_NAME_NOT_RESOLVED page.
//   • A small set of "DNS / disconnect" error codes skip the
//     redundant DNS probe and jump straight to DropoutStage.
//   • Push warm taps (received via AlertCenter.onWarmTapUrl) are
//     loaded into the running WebView, never persisted.
// ============================================================

Future<void> primeShellEngine() async {
  // Hook for future pre-warming work (e.g. webview platform init).
}

class ShellStage extends StatefulWidget {
  const ShellStage({
    super.key,
    required this.initialUrl,
    required this.vault,
    required this.center,
    required this.netSensor,
  });

  final String initialUrl;
  final DataVault vault;
  final AlertCenter center;
  final NetSensor netSensor;

  @override
  State<ShellStage> createState() => _ShellStageState();
}

class _ShellStageState extends State<ShellStage>
    with WidgetsBindingObserver {
  late final WebViewController _controller;
  bool _spinning = true;
  bool _routedAway = false;

  // Track the last main-frame URL we saw so we can retry a redirect
  // loop without losing the original landing target.
  String? _lastMainFrame;
  int _redirectRetries = 0;

  StreamSubscription<void>? _offlineSub;
  StreamSubscription<List<ConnectivityResult>>? _rawSub;

  // Known error codes for "the network is gone" — we skip the extra
  // DNS round-trip for these and jump straight to DropoutStage.
  static const Set<int> _dnsOrDisconnect = {
    -2,    // ERR_FAILED (Android WebView)
    -21,   // ERR_NETWORK_CHANGED
    -105,  // ERR_NAME_NOT_RESOLVED
    -106,  // ERR_INTERNET_DISCONNECTED
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _applyImmersive();

    _controller = _composeController();
    _configurePlatform();
    _controller.loadRequest(Uri.parse(widget.initialUrl));

    widget.center.onWarmTapUrl = (url) {
      if (!mounted) return;
      _controller.loadRequest(Uri.parse(url));
    };

    _offlineSub = widget.netSensor.offlineStream.listen((_) {
      _redirectIfReallyOffline();
    });
    _rawSub = widget.netSensor.rawStream.listen((statuses) {
      // No-op — kept as a hook for richer future UX without forcing a
      // refactor when the time comes.
      if (statuses.every((s) => s == ConnectivityResult.none)) {
        // The debounced offlineStream covers this.
      }
    });
  }

  void _applyImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _applyImmersive();
  }

  WebViewController _composeController() {
    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(TransportPipe.instance.userAgent)
      ..setBackgroundColor(Colors.black)
      ..enableZoom(false)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _spinning = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _spinning = false);
            _redirectRetries = 0;
            _injectSafeAreaShim();
            _injectKeyboardScroll();
          },
          onWebResourceError: _handleResourceError,
          onHttpError: (_) {},
          onNavigationRequest: (req) {
            final uri = Uri.tryParse(req.url);
            if (uri == null) return NavigationDecision.prevent;
            switch (uri.scheme) {
              case 'http':
              case 'https':
              case 'about':
              case 'data':
              case 'blob':
                if (req.isMainFrame) _lastMainFrame = req.url;
                return NavigationDecision.navigate;
              default:
                _openExternally(uri);
                return NavigationDecision.prevent;
            }
          },
        ),
      );
  }

  void _handleResourceError(WebResourceError err) {
    if (err.isForMainFrame != true) return;
    final desc = err.description.toLowerCase();

    final tooManyRedirects = desc.contains('too_many_redirects') ||
        desc.contains('too many redirects') ||
        err.errorCode == -1007 ||
        err.errorCode == -9;

    if (tooManyRedirects &&
        _lastMainFrame != null &&
        _redirectRetries < 3) {
      _redirectRetries++;
      _controller.loadRequest(Uri.parse(_lastMainFrame!));
      return;
    }

    // Cover Android's native error page IMMEDIATELY by raising the
    // spinner overlay, even before we re-check connectivity.
    if (mounted) setState(() => _spinning = true);

    final descMentionsDns =
        desc.contains('name_not_resolved') ||
            desc.contains('err_name_not_resolved') ||
            desc.contains('internet_disconnected') ||
            desc.contains('network_changed');

    final knownDnsCode = _dnsOrDisconnect.contains(err.errorCode);

    if (descMentionsDns || knownDnsCode) {
      _routeToDropoutImmediately();
    } else {
      _redirectIfReallyOffline();
    }
  }

  Future<void> _redirectIfReallyOffline() async {
    if (_routedAway) return;
    final ok = await widget.netSensor.isOnline();
    if (ok || !mounted) return;
    _routeToDropoutImmediately();
  }

  void _routeToDropoutImmediately() {
    if (_routedAway || !mounted) return;
    _routedAway = true;
    final live = _lastMainFrame ?? widget.initialUrl;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DropoutStage(
          recoveryRoute: (_) => ShellStage(
            initialUrl: live,
            vault: widget.vault,
            center: widget.center,
            netSensor: widget.netSensor,
          ),
        ),
      ),
    );
  }

  void _configurePlatform() {
    if (!Platform.isAndroid) return;
    if (_controller.platform is! AndroidWebViewController) return;

    final droid = _controller.platform as AndroidWebViewController;
    droid.setMediaPlaybackRequiresUserGesture(false);
    droid.setOnShowFileSelector(_handleFileChooser);

    final cookies = AndroidWebViewCookieManager(
      AndroidWebViewCookieManagerCreationParams
          .fromPlatformWebViewCookieManagerCreationParams(
        const PlatformWebViewCookieManagerCreationParams(),
      ),
    );
    cookies.setAcceptThirdPartyCookies(droid, true);
  }

  Future<List<String>> _handleFileChooser(FileSelectorParams params) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        allowMultiple: params.mode == FileSelectorMode.openMultiple,
        type: FileType.any,
      );
      if (picked == null) return const [];
      return picked.files
          .where((f) => f.path != null)
          .map((f) => Uri.file(f.path!).toString())
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _openExternally(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// Removes affiliate sites' notch-aware paddings (safe-area insets)
  /// that otherwise leave white bars on notched Android devices.
  void _injectSafeAreaShim() {
    _controller.runJavaScript(r'''
(function() {
  if (window.__edSafeShim) return;
  window.__edSafeShim = true;
  var TAG = '__ed_safe_shim';
  var BODY = ':root{' +
      '--safe-area-inset-top:0px!important;' +
      '--safe-area-inset-right:0px!important;' +
      '--safe-area-inset-bottom:0px!important;' +
      '--safe-area-inset-left:0px!important;' +
      '--sat:0px!important;--sar:0px!important;' +
      '--sab:0px!important;--sal:0px!important;' +
      '--safe-top:0px!important;--safe-right:0px!important;' +
      '--safe-bottom:0px!important;--safe-left:0px!important;' +
    '}' +
    'html,body,#__nuxt,#__layout,#app,#root,' +
    '.gameview-mobile-header,.app-shell-top{' +
      'padding-top:0!important;' +
      'padding-left:0!important;' +
      'padding-right:0!important;' +
      'margin-top:0!important;' +
    '}';

  function kbIsOpen() {
    if (!window.visualViewport) return false;
    return window.visualViewport.height < window.innerHeight * 0.75;
  }

  function applyShim() {
    if (kbIsOpen()) return;
    var head = document.head || document.documentElement;
    if (!head) return;
    var viewport = document.querySelector('meta[name="viewport"]');
    if (viewport && !/viewport-fit\s*=\s*contain/i.test(viewport.getAttribute('content') || '')) {
      var content = (viewport.getAttribute('content') || '')
        .replace(/,?\s*viewport-fit\s*=\s*\w+/ig, '').trim();
      viewport.setAttribute('content', content + (content ? ', ' : '') + 'viewport-fit=contain');
    }
    var s = document.getElementById(TAG);
    if (!s) {
      s = document.createElement('style');
      s.id = TAG;
      head.appendChild(s);
    }
    if (s.textContent !== BODY) s.textContent = BODY;
    if (head.lastElementChild !== s) head.appendChild(s);
  }

  applyShim();

  ['pushState', 'replaceState'].forEach(function(name) {
    var origin = history[name];
    history[name] = function() {
      var ret = origin.apply(this, arguments);
      setTimeout(applyShim, 80);
      setTimeout(applyShim, 420);
      return ret;
    };
  });
  window.addEventListener('popstate', function() { setTimeout(applyShim, 80); });
  setInterval(applyShim, 2500);
})();
''');
  }

  /// Scrolls focused inputs into view when the soft keyboard appears.
  /// IMPORTANT: behavior:'auto' — 'smooth' fights with the keyboard
  /// animation and produces visible jitter on some Android OEMs.
  void _injectKeyboardScroll() {
    _controller.runJavaScript(r'''
(function() {
  if (window.__edKbScroll) return;
  window.__edKbScroll = true;

  function isEditable(el) {
    if (!el) return false;
    var tag = el.tagName;
    return tag === 'INPUT' || tag === 'TEXTAREA' || el.isContentEditable;
  }

  function scrollIntoView() {
    var el = document.activeElement;
    if (!isEditable(el)) return;
    var vp = window.visualViewport;
    if (vp) {
      var rect = el.getBoundingClientRect();
      var bottom = vp.offsetTop + vp.height;
      if (rect.bottom > bottom - 24 || rect.top < vp.offsetTop) {
        el.scrollIntoView({ behavior: 'auto', block: 'nearest' });
      }
    } else {
      el.scrollIntoView({ behavior: 'auto', block: 'nearest' });
    }
  }

  document.addEventListener('focusin', function(e) {
    if (isEditable(e.target)) {
      setTimeout(scrollIntoView, 350);
    }
  });

  if (window.visualViewport) {
    var prev = window.visualViewport.height;
    window.visualViewport.addEventListener('resize', function() {
      var h = window.visualViewport.height;
      if (h < prev) setTimeout(scrollIntoView, 120);
      prev = h;
    });
  }
})();
''');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _offlineSub?.cancel();
    _rawSub?.cancel();
    widget.center.onWarmTapUrl = null;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  Future<bool> _handleBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    }
    return false; // never let the system pop the route
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final viewPadding = MediaQuery.of(context).viewPadding;

    // In landscape the OS reports the display cutout (camera punch
    // hole / iPhone notch / curved bezel) on the leading edge as
    // `viewPadding.left` / `.right`. We keep top/bottom at zero so
    // the WebView remains immersive, but we MUST reserve those side
    // gutters or the affiliate site renders behind the cutout and
    // its top-left logo / nav becomes unreadable.
    //
    // In portrait the cutout sits at the top edge — we keep the
    // existing top inset and let the WebView span edge-to-edge
    // horizontally.
    final webPadding = orientation == Orientation.landscape
        ? EdgeInsets.only(
            left: viewPadding.left,
            right: viewPadding.right,
          )
        : EdgeInsets.only(top: viewPadding.top);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: webPadding,
              child: WebViewWidget(controller: _controller),
            ),
            if (_spinning)
              Container(
                color: Colors.black.withValues(alpha: 0.55),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xFFFFC25C)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
