import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../config/game_endpoints.dart';
import '../screens/webview_screen.dart';
import '../services/storage_service.dart';
import 'game_assets.dart';
import 'game_config.dart';
import 'game_engine.dart';
import 'game_painter.dart';
import 'upgrades.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  final _engine  = GameEngine();
  final _assets  = GameAssets();
  final _storage = StorageService();

  late final Ticker _ticker;
  Duration _last = Duration.zero;

  bool _showShop     = false;
  bool _runFinalized = false;

  int    _coins = 0;
  int    _xp    = 0;
  String _name  = 'Player';

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _coins = _storage.coins;
    _xp    = _storage.xp;
    _name  = _storage.playerName;
    _engine.configure(_storage.loadUpgrades());
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 0.016
        : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _engine.update(dt.clamp(0.0, 0.05));

    if (_engine.state == GameState.gameOver && !_runFinalized) _finalizeRun();
    if (_engine.state == GameState.playing)  _runFinalized = false;
    if (mounted) setState(() {});
  }

  Future<void> _finalizeRun() async {
    _runFinalized = true;
    _coins += _engine.runCoins;
    await _storage.setCoins(_coins);
    if (_engine.score > _storage.highScore) await _storage.setHighScore(_engine.score);
    if (_engine.level > _storage.bestLevel)  await _storage.setBestLevel(_engine.level);
    _xp += _engine.xpEarned;
    await _storage.setXp(_xp);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onPanDown(DragDownDetails d)   => _engine.pointerMove(d.localPosition.dx);
  void _onPanUpdate(DragUpdateDetails d) => _engine.pointerMove(d.localPosition.dx);
  void _onTapDown(TapDownDetails d)    => _engine.pointerMove(d.localPosition.dx);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1430),
      body: LayoutBuilder(
        builder: (context, constraints) {
          _engine.setSize(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown:   _onTapDown,
            onPanDown:   _onPanDown,
            onPanUpdate: _onPanUpdate,
            child: Stack(children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: GamePainter(engine: _engine, assets: _assets),
                ),
              ),
              if (_engine.state == GameState.menu)    _buildMenu(constraints),
              if (_engine.state == GameState.playing ||
                  _engine.state == GameState.levelUp) _buildHud(),
              if (_engine.state == GameState.levelUp) _buildLevelUp(),
              if (_engine.state == GameState.paused)  _buildPause(),
              if (_engine.state == GameState.gameOver) _buildGameOver(),
              if (_showShop) _buildShop(),
            ]),
          );
        },
      ),
    );
  }

  // ════════════ MENU ════════════
  Widget _buildMenu(BoxConstraints c) {
    final glow  = (sin(_engine.menuTime * 3) + 1) / 2;
    final plvl  = PlayerProgress.levelForXp(_xp);
    final into  = PlayerProgress.xpIntoLevel(_xp);
    final need  = PlayerProgress.xpForNext(plvl);

    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(children: [
            _levelBadge(plvl),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                GestureDetector(
                  onTap: _editName,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(
                      child: Text(_name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 16,
                            fontWeight: FontWeight.bold,
                            shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.edit, size: 13, color: Colors.white70),
                  ]),
                ),
                const SizedBox(height: 4),
                _xpBar(into, need),
              ]),
            ),
            const SizedBox(width: 10),
            _coinChip(_coins),
          ]),
        ),
        const Spacer(flex: 3),
        Image.asset('assets/Game_Name.webp',
            width: c.maxWidth * 0.8, fit: BoxFit.contain),
        const Spacer(flex: 3),
        _menuButton(
          label: 'PLAY', icon: Icons.play_arrow_rounded,
          colors: const [Color(0xFF66BB6A), Color(0xFF43A047)],
          glow: glow, big: true,
          onTap: () => setState(_engine.startGame),
        ),
        const SizedBox(height: 16),
        _menuButton(
          label: 'UPGRADES', icon: Icons.upgrade_rounded,
          colors: const [Color(0xFFFFB300), Color(0xFFFB8C00)],
          glow: glow,
          onTap: () => setState(() => _showShop = true),
        ),
        const SizedBox(height: 18),
        if (_storage.highScore > 0) _bestStrip(),
        const Spacer(flex: 1),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _linkButton('Privacy Policy', 'Privacy Policy', privacyPolicyUrl),
              Container(
                width: 1,
                height: 14,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: Colors.white.withValues(alpha: 0.3),
              ),
              _linkButton('Support', 'Support', supportUrl),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _linkButton(String label, String title, String url) => GestureDetector(
    onTap: () => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WebViewScreen(title: title, url: url),
    )),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    ),
  );

  Widget _bestStrip() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.star_rounded, color: Colors.amber, size: 20),
      const SizedBox(width: 6),
      Text('Best ${_storage.highScore}',
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
      const SizedBox(width: 16),
      const Icon(Icons.flag_rounded, color: Color(0xFF80DEEA), size: 20),
      const SizedBox(width: 6),
      Text('Lv ${_storage.bestLevel}',
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
    ]),
  );

  // ════════════ HUD ════════════
  Widget _buildHud() {
    final progress =
        (_engine.levelScore / _engine.params.scoreToAdvanceLevel).clamp(0.0, 1.0);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _pill(Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                const SizedBox(width: 4),
                Text('${_engine.score}', style: const TextStyle(
                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ])),
              const SizedBox(height: 6),
              _pill(Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.monetization_on, color: Color(0xFFFFD54F), size: 15),
                const SizedBox(width: 4),
                Text('${_engine.runCoins}', style: const TextStyle(
                    color: Color(0xFFFFD54F), fontSize: 14, fontWeight: FontWeight.bold)),
              ])),
            ]),
            const Spacer(),
            _heartsRow(),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(_engine.togglePause),
              child: _pill(const Icon(Icons.pause_rounded, color: Colors.white, size: 22)),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _pill(Text('LEVEL ${_engine.level}', style: const TextStyle(
                color: Colors.white, fontSize: 13,
                fontWeight: FontWeight.w900, letterSpacing: 1))),
            const SizedBox(width: 10),
            Expanded(child: _progressBar(progress)),
            const SizedBox(width: 10),
            if (_engine.combo >= 2)
              _pill(Text('×${_engine.comboMultiplier.toStringAsFixed(1)}',
                  style: const TextStyle(color: Color(0xFFFFB74D),
                      fontSize: 15, fontWeight: FontWeight.w900))),
          ]),
          if (_engine.shields > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                for (int i = 0; i < _engine.shields; i++)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.shield, color: Color(0xFF26C6DA), size: 18),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _heartsRow() => Row(mainAxisSize: MainAxisSize.min, children: [
    for (int i = 0; i < _engine.maxLives; i++)
      Padding(
        padding: const EdgeInsets.only(left: 3),
        child: Icon(
          i < _engine.lives ? Icons.favorite : Icons.favorite_border,
          color: i < _engine.lives ? const Color(0xFFEF5350) : Colors.white38,
          size: 22,
        ),
      ),
  ]);

  Widget _progressBar(double p) => Container(
    height: 14,
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: p,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF66BB6A), Color(0xFFAED581)]),
            ),
          ),
        ),
      ),
    ),
  );

  // ════════════ LEVEL UP ════════════
  Widget _buildLevelUp() {
    final t     = (_engine.levelUpTimer / 1.7).clamp(0.0, 1.0);
    final scale = Curves.elasticOut.transform((t * 1.6).clamp(0.0, 1.0));
    final fade  = t < 0.85 ? 1.0 : (1 - (t - 0.85) / 0.15);
    return IgnorePointer(
      child: Center(
        child: Opacity(
          opacity: fade.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.4 + scale * 0.6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFFB300), Color(0xFFFB8C00)]),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(color: Colors.orange.withValues(alpha: 0.6),
                      blurRadius: 30, spreadRadius: 4),
                ],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('LEVEL UP!', style: TextStyle(
                    color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    shadows: [Shadow(color: Colors.black38, blurRadius: 6)])),
                const SizedBox(height: 4),
                Text('Level ${_engine.level}', style: const TextStyle(
                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ════════════ PAUSE ════════════
  Widget _buildPause() => Container(
    color: Colors.black.withValues(alpha: 0.65),
    child: SafeArea(
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.pause_circle_filled_rounded, color: Colors.white, size: 84),
          const SizedBox(height: 14),
          const Text('PAUSED', style: TextStyle(
              color: Colors.white, fontSize: 32,
              fontWeight: FontWeight.w900, letterSpacing: 4)),
          const SizedBox(height: 28),
          _menuButton(
            label: 'RESUME', icon: Icons.play_arrow_rounded,
            colors: const [Color(0xFF66BB6A), Color(0xFF43A047)],
            glow: 0.4, onTap: () => setState(_engine.togglePause),
          ),
          const SizedBox(height: 14),
          _ghostButton('MENU', Icons.home_rounded, () => setState(_engine.returnToMenu)),
        ]),
      ),
    ),
  );

  // ════════════ GAME OVER ════════════
  Widget _buildGameOver() {
    final newBest = _engine.score >= _storage.highScore && _engine.score > 0;
    return Container(
      color: Colors.black.withValues(alpha: 0.82),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 10),
              Image.asset('assets/egg_broken_effect.webp', width: 110),
              const Text('GAME OVER', style: TextStyle(
                  color: Color(0xFFEF5350), fontSize: 34, fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                  shadows: [Shadow(color: Colors.black, blurRadius: 10)])),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Row(children: [
                  Expanded(child: _statCard(Icons.star_rounded,  'SCORE', '${_engine.score}', Colors.amber)),
                  const SizedBox(width: 10),
                  Expanded(child: _statCard(Icons.flag_rounded,  'LEVEL', '${_engine.level}', const Color(0xFF80DEEA))),
                ]),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Row(children: [
                  Expanded(child: _statCard(Icons.monetization_on, 'COINS', '+${_engine.runCoins}', const Color(0xFFFFD54F))),
                  const SizedBox(width: 10),
                  Expanded(child: _statCard(Icons.bolt_rounded, 'MAX COMBO',
                      '×${(1 + _engine.maxCombo * 0.1).clamp(1, 5).toStringAsFixed(1)}',
                      const Color(0xFFFFB74D))),
                ]),
              ),
              const SizedBox(height: 14),
              if (newBest)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFFFB300), Color(0xFFFB8C00)]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('NEW BEST SCORE!', style: TextStyle(
                      color: Colors.white, fontSize: 15,
                      fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _menuButton(
                  label: 'RETRY', icon: Icons.replay_rounded,
                  colors: const [Color(0xFF66BB6A), Color(0xFF43A047)],
                  glow: 0.5, onTap: () => setState(_engine.startGame),
                ),
                const SizedBox(width: 12),
                _ghostButton('MENU', Icons.home_rounded, () => setState(_engine.returnToMenu)),
              ]),
              const SizedBox(height: 14),
              _menuButton(
                label: 'UPGRADES', icon: Icons.upgrade_rounded,
                colors: const [Color(0xFFFFB300), Color(0xFFFB8C00)],
                glow: 0.4, onTap: () => setState(() => _showShop = true),
              ),
              const SizedBox(height: 20),
            ]),
          ),
        ),
      ),
    );
  }

  // ════════════ SHOP ════════════
  Widget _buildShop() {
    final levels = _storage.loadUpgrades();
    return Container(
      color: Colors.black.withValues(alpha: 0.92),
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(children: [
              const Icon(Icons.upgrade_rounded, color: Color(0xFFFFB300), size: 26),
              const SizedBox(width: 8),
              const Text('UPGRADES', style: TextStyle(
                  color: Colors.white, fontSize: 22,
                  fontWeight: FontWeight.w900, letterSpacing: 2)),
              const Spacer(),
              _coinChip(_coins),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: allUpgrades.length,
              itemBuilder: (ctx, i) =>
                  _upgradeRow(allUpgrades[i], levels.levelOf(allUpgrades[i].id)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _ghostButton('CLOSE', Icons.close_rounded,
                () => setState(() => _showShop = false)),
          ),
        ]),
      ),
    );
  }

  Widget _upgradeRow(UpgradeDef def, int level) {
    final maxed     = level >= def.maxLevel;
    final cost      = def.costForLevel(level);
    final canAfford = _coins >= cost && !maxed;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: def.color.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: def.color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(def.icon, color: def.color, size: 28),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(def.name, style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(def.description, style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6), fontSize: 11)),
            const SizedBox(height: 6),
            Row(children: [
              for (int i = 0; i < def.maxLevel; i++)
                Container(
                  width: 16, height: 6,
                  margin: const EdgeInsets.only(right: 3),
                  decoration: BoxDecoration(
                    color: i < level ? def.color : Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ]),
          ]),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: maxed || !canAfford ? null : () => _buyUpgrade(def, level),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: !maxed && canAfford
                  ? LinearGradient(colors: [def.color, def.color.withValues(alpha: 0.7)])
                  : null,
              color: maxed ? Colors.green.withValues(alpha: 0.2) :
                     !canAfford ? Colors.white.withValues(alpha: 0.1) : null,
              borderRadius: BorderRadius.circular(14),
            ),
            child: maxed
                ? const Text('MAX', style: TextStyle(
                    color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.monetization_on, color: Colors.white, size: 15),
                    const SizedBox(width: 4),
                    Text('$cost', style: TextStyle(
                        color: canAfford ? Colors.white : Colors.white54,
                        fontWeight: FontWeight.bold, fontSize: 13)),
                  ]),
          ),
        ),
      ]),
    );
  }

  Future<void> _buyUpgrade(UpgradeDef def, int level) async {
    final cost = def.costForLevel(level);
    if (_coins < cost || level >= def.maxLevel) return;
    _coins -= cost;
    await _storage.setCoins(_coins);
    await _storage.setUpgradeLevel(def.id, level + 1);
    _engine.configure(_storage.loadUpgrades());
    setState(() {});
  }

  // ════════════ SHARED WIDGETS ════════════
  Widget _pill(Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
    ),
    child: child,
  );

  Widget _coinChip(int coins) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFF3A2E12), Color(0xFF4A3A14)]),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFFFD54F).withValues(alpha: 0.5)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.monetization_on, color: Color(0xFFFFD54F), size: 18),
      const SizedBox(width: 5),
      Text('$coins', style: const TextStyle(
          color: Color(0xFFFFE082), fontSize: 15, fontWeight: FontWeight.bold)),
    ]),
  );

  Widget _levelBadge(int level) => Container(
    width: 46, height: 46,
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFF66BB6A), Color(0xFF2E7D32)]),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: [BoxShadow(color: Colors.green.withValues(alpha: 0.4), blurRadius: 8)],
    ),
    child: Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('$level', style: const TextStyle(
            color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, height: 1)),
        const Text('LVL', style: TextStyle(
            color: Colors.white70, fontSize: 8, fontWeight: FontWeight.bold, height: 1)),
      ]),
    ),
  );

  Widget _xpBar(int into, int need) => Container(
    height: 9,
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: (into / need).clamp(0.0, 1.0),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF42A5F5), Color(0xFF80D8FF)]),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _menuButton({
    required String label,
    required IconData icon,
    required List<Color> colors,
    required double glow,
    required VoidCallback onTap,
    bool big = false,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: EdgeInsets.symmetric(
          horizontal: big ? 50 : 30, vertical: big ? 18 : 13),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
        boxShadow: [BoxShadow(
            color: colors[0].withValues(alpha: 0.4 + glow * 0.3),
            blurRadius: 18 + glow * 10, offset: const Offset(0, 5))],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: Colors.white, size: big ? 30 : 24),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(
            color: Colors.white, fontSize: big ? 26 : 18,
            fontWeight: FontWeight.w900, letterSpacing: 2,
            shadows: const [Shadow(color: Colors.black38, blurRadius: 4)])),
      ]),
    ),
  );

  Widget _ghostButton(String label, IconData icon, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: Colors.white70, size: 22),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(
                color: Colors.white70, fontSize: 17,
                fontWeight: FontWeight.w900, letterSpacing: 1)),
          ]),
        ),
      );

  Widget _statCard(IconData icon, String label, String value, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(
              color: color.withValues(alpha: 0.8), fontSize: 10,
              fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(
              color: color, fontSize: 19, fontWeight: FontWeight.w900)),
        ]),
      );

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B2347),
        title: const Text('Your name', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl, maxLength: 14,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter name',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFFFB300))),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFFFD54F))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Save', style: TextStyle(color: Color(0xFFFFD54F)))),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      _name = result;
      await _storage.setPlayerName(_name);
      if (mounted) setState(() {});
    }
  }
}
