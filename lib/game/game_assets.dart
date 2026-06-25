import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'game_config.dart';

class GameAssets {
  static final GameAssets _instance = GameAssets._();
  factory GameAssets() => _instance;
  GameAssets._();

  late ui.Image chicken;
  late ui.Image chickenRunFast;
  late ui.Image chickenRunSlow;
  late ui.Image bucket;
  late ui.Image eggNormal;
  late ui.Image eggGolden;
  late ui.Image eggPoisoned;
  late ui.Image bomb;
  late ui.Image eggBroken;
  late ui.Image boom;

  final Map<String, ui.Image> backgrounds = {};
  bool loaded = false;

  Future<void> loadAll() async {
    if (loaded) return;

    final core = await Future.wait([
      _load('assets/chicken_asset.webp'),
      _load('assets/chicken_run_fast_asset.webp'),
      _load('assets/chicken_run_slow_asset.webp'),
      _load('assets/bucket_asset.webp'),
      _load('assets/egg_asset.webp'),
      _load('assets/egg_golden_asset.webp'),
      _load('assets/egg_poisoned_asset.webp'),
      _load('assets/bomb_asset.webp'),
      _load('assets/egg_broken_effect.webp'),
      _load('assets/boom_effect.webp'),
    ]);

    chicken        = core[0];
    chickenRunFast = core[1];
    chickenRunSlow = core[2];
    bucket         = core[3];
    eggNormal      = core[4];
    eggGolden      = core[5];
    eggPoisoned    = core[6];
    bomb           = core[7];
    eggBroken      = core[8];
    boom           = core[9];

    for (final path in levelBackgrounds) {
      backgrounds[path] = await _load(path);
    }

    loaded = true;
  }

  ui.Image imageForEgg(EggType type) {
    switch (type) {
      case EggType.normal:   return eggNormal;
      case EggType.golden:   return eggGolden;
      case EggType.poisoned: return eggPoisoned;
      case EggType.bomb:     return bomb;
    }
  }

  ui.Image backgroundFor(String path) =>
      backgrounds[path] ?? backgrounds.values.first;

  Future<ui.Image> _load(String path) async {
    final data  = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}
