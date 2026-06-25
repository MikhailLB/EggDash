import 'dart:math';
import 'game_config.dart';
import 'upgrades.dart';

enum GameState { menu, playing, paused, levelUp, gameOver }

class Egg {
  EggType type;
  double x;
  double y;
  double vy;
  double rot;
  double rotSpeed;
  double wobblePhase;
  double spawnPop = 0;
  bool resolved = false;

  Egg({
    required this.type,
    required this.x,
    required this.y,
    required this.vy,
    required this.rot,
    required this.rotSpeed,
    required this.wobblePhase,
  });
}

class Chicken {
  double x;
  double y;
  int dir;
  double speed;
  double layTimer;
  double layInterval;
  double bobPhase;
  double layAnim = 0;

  Chicken({
    required this.x,
    required this.y,
    required this.dir,
    required this.speed,
    required this.layTimer,
    required this.layInterval,
    required this.bobPhase,
  });
}

enum FxKind { catchSpark, splat, boom, shieldBlock }

class Fx {
  final FxKind kind;
  final double x;
  final double y;
  double t = 0;
  final double dur;
  Fx(this.kind, this.x, this.y, this.dur);
}

class FloatingText {
  final String text;
  final double x;
  final double y0;
  double t = 0;
  final double dur;
  final int colorValue;
  FloatingText(this.text, this.x, this.y0, this.dur, this.colorValue);
}

class GameEngine {
  final Random _rng = Random();

  double screenWidth  = 0;
  double screenHeight = 0;

  UpgradeState upgrades = UpgradeState.empty();

  GameState state = GameState.menu;
  int level = 1;
  late LevelParams params;
  int score      = 0;
  int levelScore = 0;
  int runCoins   = 0;
  int combo      = 0;
  int maxCombo   = 0;
  int lives      = 3;
  int maxLives   = 3;
  int shields    = 0;
  int xpEarned   = 0;
  int eggsCaught = 0;

  double slowStartRemaining = 0;
  double menuTime     = 0;
  double levelUpTimer = 0;

  double shake  = 0;
  double shakeX = 0;
  double shakeY = 0;
  double flashRed  = 0;
  double flashGold = 0;

  String currentBg = backgroundForLevel(1);
  String prevBg    = backgroundForLevel(1);
  double bgFade    = 1.0;

  final List<Egg>          eggs     = [];
  final List<Chicken>      chickens = [];
  final List<Fx>           fx       = [];
  final List<FloatingText> texts    = [];

  double basketX       = 0;
  double basketTargetX = 0;

  GameEngine() {
    params = paramsForLevel(1);
  }

  void configure(UpgradeState up) => upgrades = up;

  void setSize(double w, double h) {
    final first = screenWidth == 0;
    screenWidth  = w;
    screenHeight = h;
    if (first) {
      basketX       = w / 2;
      basketTargetX = w / 2;
    }
  }

  // ─── Geometry ───
  double get basketWidth    => screenWidth * 0.26 * upgrades.basketWidthMul;
  double get basketHeight   => basketWidth;
  double get basketY        => screenHeight * 0.84;
  double get basketRimY     => basketY - basketHeight * 0.16;
  double get basketMouthHalf => basketWidth * 0.40;
  double get groundY        => screenHeight * 0.95;
  double get eggSize        => screenWidth * 0.11;
  double get chickenTopY    => screenHeight * 0.24;
  double get comboMultiplier => (1.0 + combo * 0.1).clamp(1.0, 5.0);

  // ─── Lifecycle ───
  void startGame() {
    state      = GameState.playing;
    level      = 1;
    params     = paramsForLevel(1);
    score      = 0;
    levelScore = 0;
    runCoins   = 0;
    combo      = 0;
    maxCombo   = 0;
    maxLives   = 3 + upgrades.extraLives;
    lives      = maxLives;
    shields    = upgrades.startShields;
    xpEarned   = 0;
    eggsCaught = 0;
    slowStartRemaining = upgrades.slowStartDuration;
    shake = flashRed = flashGold = levelUpTimer = 0;
    currentBg = prevBg = backgroundForLevel(1);
    bgFade = 1.0;
    eggs.clear();
    fx.clear();
    texts.clear();
    basketTargetX = screenWidth / 2;
    _buildChickens();
  }

  void returnToMenu() {
    state = GameState.menu;
    eggs.clear();
    fx.clear();
    texts.clear();
  }

  void togglePause() {
    if (state == GameState.playing) {
      state = GameState.paused;
    } else if (state == GameState.paused) {
      state = GameState.playing;
    }
  }

  void _buildChickens() {
    chickens.clear();
    final count    = params.chickenCount;
    final interval = params.spawnInterval * count;
    for (int i = 0; i < count; i++) {
      chickens.add(Chicken(
        x:           screenWidth * (0.2 + 0.6 * _rng.nextDouble()),
        y:           chickenTopY + i * screenHeight * 0.045,
        dir:         _rng.nextBool() ? 1 : -1,
        speed:       params.chickenSpeed * (0.85 + _rng.nextDouble() * 0.3),
        layTimer:    i / count * interval,
        layInterval: interval,
        bobPhase:    _rng.nextDouble() * pi * 2,
      ));
    }
  }

  // ─── Input ───
  void pointerMove(double x) {
    if (state == GameState.playing) basketTargetX = x;
  }

  // ─── Update ───
  void update(double dt) {
    menuTime += dt;
    _decayFx(dt);
    switch (state) {
      case GameState.menu:     break; // chickens not shown in menu
      case GameState.playing:  _updatePlaying(dt);
      case GameState.levelUp:  _updateLevelUp(dt);
      case GameState.paused:   break;
      case GameState.gameOver: _updateGameOver(dt);
    }
  }

  void _decayFx(double dt) {
    shake  *= pow(0.003, dt).toDouble();
    shakeX  = (_rng.nextDouble() - 0.5) * 2 * shake;
    shakeY  = (_rng.nextDouble() - 0.5) * 2 * shake;
    flashRed  = (flashRed  - dt * 1.6).clamp(0.0, 1.0);
    flashGold = (flashGold - dt * 2.2).clamp(0.0, 1.0);
    if (bgFade < 1.0) bgFade = (bgFade + dt * 1.2).clamp(0.0, 1.0);
    fx.removeWhere((f) { f.t += dt; return f.t >= f.dur; });
    texts.removeWhere((t) { t.t += dt; return t.t >= t.dur; });
  }

  void _updateBasket(double dt) {
    final k = (upgrades.moveResponse * dt).clamp(0.0, 1.0);
    basketX = (basketX + (basketTargetX - basketX) * k)
        .clamp(basketWidth / 2, screenWidth - basketWidth / 2);
  }

  void _updatePlaying(double dt) {
    slowStartRemaining = (slowStartRemaining - dt).clamp(0.0, 999.0);
    _updateBasket(dt);
    _updateChickens(dt);
    _updateEggs(dt);
  }

  void _updateChickens(double dt) {
    for (final c in chickens) {
      c.bobPhase += dt * 6;
      c.layAnim   = (c.layAnim - dt * 2.5).clamp(0.0, 1.0);
      c.x += c.dir * c.speed * dt;
      if (c.x < screenWidth * 0.1) { c.x = screenWidth * 0.1; c.dir = 1; }
      if (c.x > screenWidth * 0.9) { c.x = screenWidth * 0.9; c.dir = -1; }
      c.layTimer -= dt;
      if (c.layTimer <= 0) {
        c.layTimer = c.layInterval * (0.8 + _rng.nextDouble() * 0.4);
        _layEgg(c);
      }
    }
  }

  void _layEgg(Chicken c) {
    c.layAnim = 1.0;
    final type = _pickEggType();
    var vy = params.eggFallSpeed * (screenHeight / 800.0) * (0.92 + _rng.nextDouble() * 0.16);
    if (type == EggType.golden) vy *= 1.2;
    if (type == EggType.bomb)   vy *= 0.92;
    eggs.add(Egg(
      type:        type,
      x:           c.x,
      y:           c.y + eggSize * 0.5,
      vy:          vy,
      rot:         (_rng.nextDouble() - 0.5) * 0.3,
      rotSpeed:    (_rng.nextDouble() - 0.5) * 1.2,
      wobblePhase: _rng.nextDouble() * pi * 2,
    ));
  }

  EggType _pickEggType() {
    if (_rng.nextDouble() < params.badChance) {
      return _rng.nextDouble() < 0.45 + (params.level / 40.0).clamp(0.0, 0.5)
          ? EggType.bomb
          : EggType.poisoned;
    }
    final golden = (params.goldenChance + upgrades.goldenBonus).clamp(0.0, 0.4);
    return _rng.nextDouble() < golden ? EggType.golden : EggType.normal;
  }

  void _updateEggs(double dt) {
    final slowMul = slowStartRemaining > 0 ? 0.55 : 1.0;
    final mag = upgrades.magnetStrength;
    final magR = upgrades.magnetRadius;

    for (final egg in eggs) {
      if (egg.resolved) continue;
      egg.spawnPop   = (egg.spawnPop + dt * 5).clamp(0.0, 1.0);
      final prevY = egg.y;
      egg.y         += egg.vy * slowMul * dt;
      egg.rot       += egg.rotSpeed * dt;
      egg.wobblePhase += dt * 4;

      if (mag > 0 && egg.type.isGood && egg.y > screenHeight * 0.45) {
        final dx = basketX - egg.x;
        if (dx.abs() < magR) {
          final step = mag * dt;
          egg.x += dx.abs() < step ? dx : step * dx.sign;
        }
      }

      if (!egg.resolved && prevY < basketRimY && egg.y >= basketRimY &&
          (egg.x - basketX).abs() <= basketMouthHalf) {
        _onCatch(egg); continue;
      }
      if (!egg.resolved && egg.y >= groundY) _onMiss(egg);
    }
    eggs.removeWhere((e) => e.resolved);
  }

  void _onCatch(Egg egg) {
    egg.resolved = true;
    if (egg.type.isGood) {
      final gained = (egg.type.baseScore * comboMultiplier).round();
      score      += gained;
      levelScore += gained;
      combo++;
      if (combo > maxCombo) maxCombo = combo;
      eggsCaught++;
      xpEarned += egg.type == EggType.golden ? 3 : 1;
      runCoins  += (egg.type.coinReward * upgrades.coinMul).round();
      fx.add(Fx(FxKind.catchSpark, egg.x, basketRimY, 0.45));
      texts.add(FloatingText(
        '+$gained', egg.x, basketRimY - 10, 0.8,
        egg.type == EggType.golden ? 0xFFFFD54F : 0xFFFFFFFF,
      ));
      if (egg.type == EggType.golden) flashGold = 0.5;
      _maybeLevelUp();
    } else {
      _penalty(egg);
    }
  }

  void _onMiss(Egg egg) {
    egg.resolved = true;
    if (egg.type.isGood) {
      fx.add(Fx(FxKind.splat, egg.x, groundY, 0.6));
      _loseLifeOrShield();
    } else {
      fx.add(egg.type == EggType.bomb
          ? Fx(FxKind.boom,  egg.x, groundY, 0.5)
          : Fx(FxKind.splat, egg.x, groundY, 0.6));
    }
  }

  void _penalty(Egg egg) {
    if (egg.type == EggType.bomb) {
      fx.add(Fx(FxKind.boom,  egg.x, basketRimY, 0.5));
      shake = max(shake, 22.0);
    } else {
      fx.add(Fx(FxKind.splat, egg.x, basketRimY, 0.6));
      shake = max(shake, 12.0);
    }
    _loseLifeOrShield();
  }

  void _loseLifeOrShield() {
    combo = 0;
    if (shields > 0) {
      shields--;
      fx.add(Fx(FxKind.shieldBlock, basketX, basketY, 0.5));
      texts.add(FloatingText('BLOCKED', basketX, basketY - 30, 0.9, 0xFF26C6DA));
      return;
    }
    lives--;
    flashRed = 0.6;
    shake = max(shake, 14.0);
    if (lives <= 0) { lives = 0; _die(); }
  }

  void _maybeLevelUp() {
    if (levelScore >= params.scoreToAdvanceLevel) {
      levelScore -= params.scoreToAdvanceLevel;
      level++;
      params = paramsForLevel(level);
      prevBg = currentBg;
      currentBg = backgroundForLevel(level);
      if (prevBg != currentBg) bgFade = 0.0;
      state = GameState.levelUp;
      levelUpTimer = 0;
      flashGold = 0.6;
    }
  }

  void _die() {
    state = GameState.gameOver;
    flashRed = 0.7;
    shake = max(shake, 24.0);
  }

  void _updateLevelUp(double dt) {
    levelUpTimer += dt;
    _updateBasket(dt);
    for (final c in chickens) { c.bobPhase += dt * 4; }
    if (levelUpTimer >= 1.7) {
      _buildChickens();
      state = GameState.playing;
    }
  }

  void _updateGameOver(double dt) {
    _updateBasket(dt);
    for (final egg in eggs) {
      if (egg.resolved) continue;
      egg.y += egg.vy * 0.4 * dt;
      egg.rot += egg.rotSpeed * dt;
      if (egg.y >= groundY) egg.resolved = true;
    }
    eggs.removeWhere((e) => e.resolved);
  }
}
