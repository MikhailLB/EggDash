import 'dart:math';

enum EggType { normal, golden, poisoned, bomb }

extension EggTypeInfo on EggType {
  bool get isGood => this == EggType.normal || this == EggType.golden;

  int get baseScore {
    switch (this) {
      case EggType.normal:   return 10;
      case EggType.golden:   return 35;
      case EggType.poisoned: return 0;
      case EggType.bomb:     return 0;
    }
  }

  int get coinReward {
    switch (this) {
      case EggType.normal:   return 1;
      case EggType.golden:   return 8;
      case EggType.poisoned: return 0;
      case EggType.bomb:     return 0;
    }
  }

  String get asset {
    switch (this) {
      case EggType.normal:   return 'assets/egg_asset.webp';
      case EggType.golden:   return 'assets/egg_golden_asset.webp';
      case EggType.poisoned: return 'assets/egg_poisoned_asset.webp';
      case EggType.bomb:     return 'assets/bomb_asset.webp';
    }
  }
}

const List<String> levelBackgrounds = [
  'assets/bg_day_asset.webp',
  'assets/bg_sunset_asset.webp',
  'assets/bg_night_asset.webp',
  'assets/bg_rain_asset.webp',
  'assets/bg_storm_asset.webp',
  'assets/bg_falls_asset.webp',
  'assets/bg_space_asset.webp',
];

String backgroundForLevel(int level) {
  final idx = (level - 1) % levelBackgrounds.length;
  return levelBackgrounds[idx.clamp(0, levelBackgrounds.length - 1)];
}

class LevelParams {
  final int level;
  final int chickenCount;
  final double eggFallSpeed;
  final double spawnInterval;
  final double badChance;
  final double goldenChance;
  final double chickenSpeed;
  final int scoreToAdvanceLevel;

  const LevelParams({
    required this.level,
    required this.chickenCount,
    required this.eggFallSpeed,
    required this.spawnInterval,
    required this.badChance,
    required this.goldenChance,
    required this.chickenSpeed,
    required this.scoreToAdvanceLevel,
  });
}

LevelParams paramsForLevel(int level) {
  final l = level.clamp(1, 9999);
  final t = (l - 1).toDouble();

  return LevelParams(
    level: l,
    chickenCount: (1 + (t / 3).floor()).clamp(1, 4),
    eggFallSpeed: (210 + t * 26).clamp(210, 720).toDouble(),
    spawnInterval: (1.9 - t * 0.11).clamp(0.55, 1.9).toDouble(),
    badChance: (0.10 + t * 0.022).clamp(0.10, 0.42).toDouble(),
    goldenChance: (0.08 + t * 0.004).clamp(0.08, 0.16).toDouble(),
    chickenSpeed: (70 + t * 12).clamp(70, 240).toDouble(),
    scoreToAdvanceLevel: (180 + t * 60).round(),
  );
}

class PlayerProgress {
  static int levelForXp(int xp) {
    int level = 1;
    int remaining = xp;
    while (remaining >= xpForNext(level)) {
      remaining -= xpForNext(level);
      level++;
    }
    return level;
  }

  static int xpForNext(int level) => 100 + (level - 1) * 60;

  static int xpIntoLevel(int xp) {
    int level = 1;
    int remaining = xp;
    while (remaining >= xpForNext(level)) {
      remaining -= xpForNext(level);
      level++;
    }
    return remaining;
  }
}

final Random sharedRng = Random();
