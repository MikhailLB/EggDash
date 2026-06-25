import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../types/shell_mode.dart';

// ============================================================
// DATA VAULT — Gray-side persistence layer.
// ============================================================
// Coexists with the game's StorageService (which uses `ed_*`
// keys) without colliding — every key in this class is prefixed
// with `gw_*` (gray-wave). The few values that are genuinely
// sensitive (saved URL, one-shot push URL) live in secure
// storage instead of SharedPreferences.
//
// The `notification_os_denied` flag is critical: once Android
// 13+ refuses the POST_NOTIFICATIONS dialog, the OS will never
// show it again. Without this flag the skip cooldown would
// expire after 3 days and "Accept" would silently no-op.
// ============================================================

class DataVault {
  DataVault._();

  static final DataVault instance = DataVault._();

  static const _keyShellMode = 'gw_shell_mode';
  static const _keyExpiresAt = 'gw_expires_at';
  static const _keyNotifGrant = 'gw_notif_granted';
  static const _keyNotifOsDeny = 'gw_notif_os_blocked';
  static const _keyNotifCooldown = 'gw_notif_cooldown';
  static const _keyLastSyncTs = 'gw_last_sync_ts';

  // Secure-storage keys — keep them opaque.
  static const _vaultDestination = 'gw_v_dest';
  static const _vaultPushOneShot = 'gw_v_push';

  late SharedPreferences _prefs;
  final FlutterSecureStorage _safe = const FlutterSecureStorage();

  Future<void> bootstrap() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ---- Shell mode --------------------------------------------------------

  ShellMode readShellMode() {
    return ShellMode.parse(_prefs.getString(_keyShellMode));
  }

  Future<void> writeShellMode(ShellMode mode) =>
      _prefs.setString(_keyShellMode, mode.toStorageValue());

  // ---- Saved destination URL --------------------------------------------

  Future<String?> loadDestination() => _safe.read(key: _vaultDestination);

  Future<void> saveDestination(String url) =>
      _safe.write(key: _vaultDestination, value: url);

  Future<void> clearDestination() => _safe.delete(key: _vaultDestination);

  // ---- URL expiry --------------------------------------------------------

  int? readExpiresAt() => _prefs.getInt(_keyExpiresAt);

  Future<void> writeExpiresAt(int unixSeconds) =>
      _prefs.setInt(_keyExpiresAt, unixSeconds);

  bool hasExpired() {
    final at = readExpiresAt();
    if (at == null) return true;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= at;
  }

  // ---- Notification flags ------------------------------------------------

  bool isNotificationGranted() =>
      _prefs.getBool(_keyNotifGrant) ?? false;

  Future<void> writeNotificationGranted(bool granted) =>
      _prefs.setBool(_keyNotifGrant, granted);

  bool isNotificationBlockedByOs() =>
      _prefs.getBool(_keyNotifOsDeny) ?? false;

  Future<void> markNotificationBlockedByOs() =>
      _prefs.setBool(_keyNotifOsDeny, true);

  int? readNotificationCooldownEnd() => _prefs.getInt(_keyNotifCooldown);

  Future<void> writeNotificationCooldownEnd(int unixSeconds) =>
      _prefs.setInt(_keyNotifCooldown, unixSeconds);

  /// Returns true when the notification-promo screen should be shown
  /// before opening the WebView. False if the OS already denied push,
  /// the user already granted, or we're inside the skip cooldown.
  bool shouldOfferNotifications() {
    if (isNotificationGranted()) return false;
    if (isNotificationBlockedByOs()) return false;
    final cooldown = readNotificationCooldownEnd();
    if (cooldown == null) return true;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= cooldown;
  }

  // ---- One-shot push URL (cold-start handoff) ---------------------------

  Future<void> stashPushUrl(String? url) async {
    if (url == null || url.isEmpty) {
      await _safe.delete(key: _vaultPushOneShot);
      return;
    }
    await _safe.write(key: _vaultPushOneShot, value: url);
  }

  Future<String?> takePushUrl() async {
    final v = await _safe.read(key: _vaultPushOneShot);
    if (v != null) await _safe.delete(key: _vaultPushOneShot);
    return v;
  }

  // ---- Misc --------------------------------------------------------------

  Future<void> stampLastSync() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _prefs.setInt(_keyLastSyncTs, now);
  }
}
