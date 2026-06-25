import 'package:shared_preferences/shared_preferences.dart';
import '../game/upgrades.dart';

class StorageService {
  static final StorageService _instance = StorageService._();
  factory StorageService() => _instance;
  StorageService._();

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static const _kCoins     = 'ed_coins';
  static const _kHighScore = 'ed_high_score';
  static const _kBestLevel = 'ed_best_level';
  static const _kXp        = 'ed_xp';
  static const _kName      = 'ed_name';
  static String _kUpgrade(UpgradeId id) => 'ed_up_${id.name}';

  int    get coins     => _prefs?.getInt(_kCoins)     ?? 0;
  int    get highScore => _prefs?.getInt(_kHighScore) ?? 0;
  int    get bestLevel => _prefs?.getInt(_kBestLevel) ?? 1;
  int    get xp        => _prefs?.getInt(_kXp)        ?? 0;
  String get playerName => _prefs?.getString(_kName)  ?? 'Player';

  Future<void> setCoins(int v)      async => _prefs?.setInt(_kCoins,     v < 0 ? 0 : v);
  Future<void> addCoins(int v)      async => setCoins(coins + v);
  Future<void> setHighScore(int v)  async => _prefs?.setInt(_kHighScore, v);
  Future<void> setBestLevel(int v)  async => _prefs?.setInt(_kBestLevel, v);
  Future<void> setXp(int v)         async => _prefs?.setInt(_kXp,        v);
  Future<void> addXp(int v)         async => setXp(xp + v);
  Future<void> setPlayerName(String v) async => _prefs?.setString(_kName, v);

  UpgradeState loadUpgrades() {
    final map = <UpgradeId, int>{};
    for (final u in allUpgrades) {
      map[u.id] = _prefs?.getInt(_kUpgrade(u.id)) ?? 0;
    }
    return UpgradeState(map);
  }

  Future<void> setUpgradeLevel(UpgradeId id, int level) async =>
      _prefs?.setInt(_kUpgrade(id), level);
}
