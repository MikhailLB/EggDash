import 'analytics_secrets.dart';
import 'transport_secrets.dart';

// ============================================================
// CORE SETTINGS — Single source of truth for app constants.
// ============================================================
// All values that vary per-build (bundle id, app name, retry
// delays) live here. Sensitive credentials are decoded lazily
// through their respective secret files.
// ============================================================

class CoreSettings {
  CoreSettings._();

  /// Android applicationId / iOS bundle identifier.
  static const String bundleIdentifier = 'com.eggdash.eggdashgame';

  /// Same as [bundleIdentifier] for Android. Used as `store_id`
  /// in the sync request body.
  static const String storeIdentifier = 'com.eggdash.eggdashgame';

  /// Human-readable name used in the User-Agent suffix and as a
  /// notification subtitle. Must be space-free (PascalCase) so it
  /// does not break the UA grammar.
  static const String appNameToken = 'EggDash';

  /// iOS only — leave blank for Android distributions.
  static const String iosStoreId = '';

  /// Privacy & support URLs (visible inside the game settings).
  static const String privacyPolicyUrl =
      'https://eeggdassh.com/privacy-policy.html';
  static const String supportUrl =
      'https://eeggdassh.com/support.html';
  static const String marketingSiteUrl = 'https://eeggdassh.com';

  /// Decoded full URL of the config endpoint
  /// (POST → `{ ok, url, expires }`).
  static String get syncGatewayUrl => decodeTransportEndpoint();

  /// Decoded AppsFlyer dev key.
  static String get attributionDevKey => decodeAttributionKey();

  /// Decoded Firebase sender / project number.
  static String get firebaseProjectNumber => decodeMessagingProjectId();

  /// Notification-promo cooldown when the user taps "Skip".
  /// 3 days, per TZ.
  static const int notificationRetryDelaySeconds = 3 * 24 * 60 * 60;

  /// How long to wait before retrying GCD when AppsFlyer initially
  /// reports Organic (false positive on first callback).
  static const int gcdFalseOrganicDelaySeconds = 5;

  /// Maximum time we allow `onInstallConversionData` to fire on the
  /// very first launch before giving up and posting whatever we have.
  static const Duration firstLaunchAttributionWindow = Duration(seconds: 30);

  /// Same window for returning users — they already passed once and
  /// shouldn't sit on the splash for half a minute.
  static const Duration warmAttributionWindow = Duration(seconds: 10);

  /// Total sync POST budget.
  static const Duration syncRequestTimeout = Duration(seconds: 15);
}
