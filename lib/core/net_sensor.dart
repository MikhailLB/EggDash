import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

// ============================================================
// NET SENSOR — Connectivity & DNS reachability monitor
// ============================================================
// Goes a few steps further than the bare `connectivity_plus`
// check, on purpose:
//
//   • Treats VPN, Bluetooth and "other" interfaces as real
//     connectivity. Without the VPN whitelist, switching VPN
//     on/off briefly flips the app to the No-Internet screen
//     even though traffic still flows.
//
//   • Performs a 7-second DNS probe (not 3) — VPN tunnels
//     occasionally need more than three seconds to resolve a
//     hostname, and a real offline state throws a SocketException
//     almost instantly, so the bigger budget is essentially free.
//
//   • Exposes a debounced `offlineStream` for screens that want
//     to react to "really lost connection" instead of the brief
//     none-flashes that happen during a tunnel handshake.
// ============================================================

class NetSensor {
  NetSensor._();

  static final NetSensor instance = NetSensor._();

  final Connectivity _plug = Connectivity();

  // Interfaces we consider "good enough" to attempt a request.
  static const Set<ConnectivityResult> _activeResults = {
    ConnectivityResult.wifi,
    ConnectivityResult.mobile,
    ConnectivityResult.ethernet,
    ConnectivityResult.vpn,
    ConnectivityResult.bluetooth,
    ConnectivityResult.other,
  };

  // Hostname we ping for the DNS probe. Anycast and very stable.
  static const String _probeHost = 'cloudflare.com';
  static const Duration _probeBudget = Duration(seconds: 7);
  static const Duration _offlineDebounce = Duration(milliseconds: 700);

  /// Returns true if the device has a usable network interface AND
  /// the DNS probe succeeded within the budget.
  Future<bool> isOnline() async {
    final results = await _plug.checkConnectivity();
    if (!results.any(_activeResults.contains)) return false;
    try {
      final r = await InternetAddress.lookup(_probeHost).timeout(_probeBudget);
      return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Raw connectivity events from the OS — useful when a screen wants
  /// to react instantly (e.g. enabling/disabling a Retry button).
  Stream<List<ConnectivityResult>> get rawStream =>
      _plug.onConnectivityChanged;

  /// Emits a single event ~700 ms after the connection appears to
  /// have dropped on every interface. Suppresses transient
  /// none-flashes that happen while a VPN is establishing its tunnel.
  Stream<void> get offlineStream {
    final controller = StreamController<void>.broadcast();
    Timer? debounce;
    final sub = _plug.onConnectivityChanged.listen((statuses) {
      final allNone =
          statuses.every((s) => s == ConnectivityResult.none);
      if (!allNone) {
        debounce?.cancel();
        return;
      }
      debounce?.cancel();
      debounce = Timer(_offlineDebounce, () {
        if (!controller.isClosed) controller.add(null);
      });
    });
    controller.onCancel = () {
      debounce?.cancel();
      sub.cancel();
    };
    return controller.stream;
  }
}
