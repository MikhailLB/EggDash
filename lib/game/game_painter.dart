import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'game_assets.dart';
import 'game_config.dart';
import 'game_engine.dart';

class GamePainter extends CustomPainter {
  final GameEngine engine;
  final GameAssets assets;

  const GamePainter({required this.engine, required this.assets})
      : super(repaint: null);

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);

    canvas.save();
    canvas.translate(engine.shakeX, engine.shakeY);

    if (engine.state != GameState.menu) _drawChickens(canvas);
    if (engine.state != GameState.menu) {
      _drawEggs(canvas);
      _drawBasket(canvas);
    }
    _drawFx(canvas);
    _drawTexts(canvas);

    canvas.restore();
    _drawFlashes(canvas, size);
  }

  void _drawBackground(Canvas canvas, Size size) {
    if (engine.bgFade < 1.0) {
      _drawCover(canvas, assets.backgroundFor(engine.prevBg),    size, 1.0);
      _drawCover(canvas, assets.backgroundFor(engine.currentBg), size, engine.bgFade);
    } else {
      _drawCover(canvas, assets.backgroundFor(engine.currentBg), size, 1.0);
    }
  }

  void _drawCover(Canvas canvas, ui.Image img, Size size, double opacity) {
    final iw = img.width.toDouble();
    final ih = img.height.toDouble();
    final scale = max(size.width / iw, size.height / ih);
    final dw = iw * scale;
    final dh = ih * scale;
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, iw, ih),
      Rect.fromLTWH(
        (size.width  - dw) / 2,
        (size.height - dh) / 2,
        dw, dh,
      ),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Colors.white.withValues(alpha: opacity),
    );
  }

  void _drawChickens(Canvas canvas) {
    final size = engine.screenWidth * 0.22;
    for (final c in engine.chickens) {
      final bob    = sin(c.bobPhase) * size * 0.04;
      final squash = 1.0 - c.layAnim * 0.18;
      final stretch = 1.0 + c.layAnim * 0.05;

      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(c.x, c.y + size * 0.42),
          width: size * 0.55, height: size * 0.16,
        ),
        Paint()..color = const Color(0x33000000),
      );

      canvas.save();
      canvas.translate(c.x, c.y + bob);
      if (c.dir > 0) canvas.scale(-1, 1);
      canvas.scale(stretch, squash);
      _drawImageCentered(canvas, assets.chicken, size);
      canvas.restore();
    }
  }

  void _drawEggs(Canvas canvas) {
    for (final egg in engine.eggs) {
      if (egg.resolved) continue;
      final img = assets.imageForEgg(egg.type);
      var s = engine.eggSize;
      if (egg.type == EggType.bomb)   s *= 1.08;
      if (egg.type == EggType.golden) s *= 1.04;
      final pop    = Curves.easeOutBack.transform(egg.spawnPop.clamp(0.0, 1.0));
      final wobble = sin(egg.wobblePhase) * 0.08;

      if (egg.type == EggType.golden) {
        canvas.drawCircle(
          Offset(egg.x, egg.y), s * 0.6,
          Paint()
            ..color = const Color(0x55FFE082)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
        );
      }

      canvas.save();
      canvas.translate(egg.x, egg.y);
      canvas.rotate(egg.rot + wobble);
      canvas.scale(pop);
      _drawImageCentered(canvas, img, s);
      canvas.restore();
    }
  }

  void _drawBasket(Canvas canvas) {
    final w = engine.basketWidth;
    final h = engine.basketHeight;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(engine.basketX, engine.basketY + h * 0.42),
        width: w * 0.7, height: h * 0.18,
      ),
      Paint()..color = const Color(0x44000000),
    );
    canvas.drawImageRect(
      assets.bucket,
      Rect.fromLTWH(0, 0, assets.bucket.width.toDouble(), assets.bucket.height.toDouble()),
      Rect.fromCenter(center: Offset(engine.basketX, engine.basketY), width: w, height: h),
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  void _drawFx(Canvas canvas) {
    for (final f in engine.fx) {
      final p = (f.t / f.dur).clamp(0.0, 1.0);
      switch (f.kind) {
        case FxKind.catchSpark:  _drawSpark(canvas, f.x, f.y, p);
        case FxKind.splat:       _drawImageFx(canvas, assets.eggBroken, f.x, f.y, p, from: 0.5, to: engine.eggSize / 360);
        case FxKind.boom:        _drawImageFx(canvas, assets.boom,      f.x, f.y, p, from: 0.4, to: engine.eggSize / 300);
        case FxKind.shieldBlock: _drawShield(canvas, f.x, f.y, p);
      }
    }
  }

  void _drawSpark(Canvas canvas, double x, double y, double p) {
    final a = (1 - p).clamp(0.0, 1.0);
    final r = engine.eggSize * (0.3 + p * 0.7);
    canvas.drawCircle(
      Offset(x, y), r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * a
        ..color = Colors.white.withValues(alpha: a * 0.9),
    );
    for (int i = 0; i < 6; i++) {
      final angle = i / 6 * pi * 2;
      canvas.drawCircle(
        Offset(x + cos(angle) * r * 1.1, y + sin(angle) * r * 1.1),
        2.5 * a + 1,
        Paint()..color = const Color(0xFFFFE082).withValues(alpha: a),
      );
    }
  }

  void _drawShield(Canvas canvas, double x, double y, double p) {
    final a = (1 - p).clamp(0.0, 1.0);
    canvas.drawCircle(
      Offset(x, y),
      engine.basketWidth * (0.5 + p * 0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5 * a
        ..color = const Color(0xFF26C6DA).withValues(alpha: a),
    );
  }

  void _drawImageFx(Canvas canvas, ui.Image img, double x, double y, double p,
      {required double from, required double to}) {
    final a     = (1 - p * p).clamp(0.0, 1.0);
    final scale = from + (to - from) * Curves.easeOut.transform(p);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromCenter(
        center: Offset(x, y),
        width:  img.width  * scale,
        height: img.height * scale,
      ),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Colors.white.withValues(alpha: a),
    );
  }

  void _drawTexts(Canvas canvas) {
    for (final t in engine.texts) {
      final p     = (t.t / t.dur).clamp(0.0, 1.0);
      final alpha = (1 - p).clamp(0.0, 1.0);
      final y     = t.y0 - p * 42;
      final tp = TextPainter(
        text: TextSpan(
          text: t.text,
          style: TextStyle(
            color: Color(t.colorValue).withValues(alpha: alpha),
            fontSize: 22, fontWeight: FontWeight.w900,
            shadows: [Shadow(color: Colors.black.withValues(alpha: alpha * 0.6), blurRadius: 4, offset: const Offset(0, 2))],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(t.x - tp.width / 2, y - tp.height / 2));
    }
  }

  void _drawFlashes(Canvas canvas, Size size) {
    if (engine.flashRed > 0) {
      canvas.drawRect(Offset.zero & size,
          Paint()..color = Colors.red.withValues(alpha: engine.flashRed * 0.35));
    }
    if (engine.flashGold > 0) {
      canvas.drawRect(Offset.zero & size,
          Paint()..color = const Color(0xFFFFD54F).withValues(alpha: engine.flashGold * 0.22));
    }
  }

  void _drawImageCentered(Canvas canvas, ui.Image img, double size) {
    final w = size;
    final h = size / (img.width / img.height);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromCenter(center: Offset.zero, width: w, height: h),
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  @override
  bool shouldRepaint(covariant GamePainter old) => true;
}
