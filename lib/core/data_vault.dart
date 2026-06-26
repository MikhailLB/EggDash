import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../types/shell_mode.dart';

// ============================================================
// DATA VAULT — Gray-side persistence layer.
// ============================================================
// Coexists with the game's StorageService (which uses `ed_*`
// keys) without colliding — every key in this class is prefixed
// with `gw_*` (gray-wave). The only genuinely sensitive value
// (the one-shot push URL) lives in secure storage instead of
// SharedPreferences.
//
// NOT cached anywhere: the /config.php destination URL. Each
// cold start re-asks the backend; we never write the URL into
// the vault. Earlier builds did — we purge that legacy key on
// bootstrap() so upgrading users don't drift onto a stale URL.
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
  static const _keyNotifGrant = 'gw_notif_granted';
  static const _keyNotifOsDeny = 'gw_notif_os_blocked';
  static const _keyNotifCooldown = 'gw_notif_cooldown';

  // Secure-storage keys.
  // _vaultLegacyDestination existed in earlier builds — see comment
  // in bootstrap() for the migration rationale.
  static const _vaultLegacyDestination = 'gw_v_dest';
  static const _vaultPushOneShot = 'gw_v_push';

  late SharedPreferences _prefs;
  final FlutterSecureStorage _safe = const FlutterSecureStorage();

  Future<void> bootstrap() async {
    _prefs = await SharedPreferences.getInstance();
    // Drop any URL that older builds left cached so the new
    // re-ask-on-every-launch contract is honoured even after an
    // app upgrade. Failure to delete is silently ignored — secure
    // storage occasionally throws on first read after install.
    try {
      await _safe.delete(key: _vaultLegacyDestination);
      await _prefs.remove('gw_expires_at');
      await _prefs.remove('gw_last_sync_ts');
    } catch (_) {}
  }

  // ---- Shell mode --------------------------------------------------------

  ShellMode readShellMode() {
    return ShellMode.parse(_prefs.getString(_keyShellMode));
  }

  Future<void> writeShellMode(ShellMode mode) =>
      _prefs.setString(_keyShellMode, mode.toStorageValue());

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
}
