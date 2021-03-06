import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flame/gestures.dart';
import 'package:flame/position.dart';
import 'package:flutter/gestures.dart';

import 'analytics.dart';
import 'audio.dart';
import 'collections.dart';
import 'components/background.dart';
import 'components/coin.dart';
import 'components/hud.dart';
import 'components/my_camera.dart';
import 'components/planet.dart';
import 'components/player.dart';
import 'components/revamped/powerups.dart';
import 'components/stars.dart';
import 'components/tutorial.dart';
import 'components/wall.dart';
import 'game_data.dart';
import 'palette.dart';
import 'pause_overlay.dart';
import 'rotation_manager.dart';
import 'rumble.dart';
import 'scoreboard.dart';
import 'spawner.dart';
import 'util.dart';

final _black = Palette.black.paint;

class MyGame extends BaseGame with TapDetector {
  static Spawner planetSpawner = Spawner(0.12);

  // Setup by the flutter components to allow this game instance
  // to callback to the flutter code and go back to the menu
  void Function() backToMenu;

  void Function(bool) showGameOver;

  RotationManager rotationManager;
  double lastGeneratedX;
  Player player;
  double gravity;
  int coins;
  bool hasUsedExtraLife;

  /* -1 : do not show, 0: show first, 1: show second */
  int showTutorial;
  Tutorial tutorial;

  Hud hud;
  Wall wall;
  MyCamera cameraHandler;

  bool sleeping;
  bool paused;

  Size rawSize, scaledSize;
  Position resizeOffset = Position.empty();
  double scale = 2.0;

  Powerups powerups;

  MyGame(Size size) {
    resize(size);
    hud = Hud(this);
    powerups = Powerups(this);
  }

  void prepare() {
    final isFirstTime = GameData.instance.isFirstTime();

    sleeping = true;
    paused = false;

    gravity = GRAVITY_ACC;
    double firstX = -CHUNCK_SIZE / 2.0 * BLOCK_SIZE;
    lastGeneratedX = firstX;
    coins = 0;
    hasUsedExtraLife = false;

    components.clear();
    if (isFirstTime) {
      showTutorial = 0;
      _addBg(Background.tutorial(lastGeneratedX));
    } else {
      showTutorial = -1;
      _addBg(Background.plains(lastGeneratedX));
    }

    add(cameraHandler = MyCamera());
    add(player = Player());
    add(wall = Wall(firstX - size.width));
    add(Stars(size));

    rotationManager = RotationManager();
  }

  void start() {
    Analytics.log(
      powerups.enabled ? EventName.START_REVAMPED : EventName.START_CLASSIC,
    );
    sleeping = false;
    powerups.reset();
    generateNextChunck();
    Audio.gameMusic();
  }

  void restart() {
    prepare();
    start();
  }

  Background findBackgroundForX(double x) {
    return components.firstWhere((e) => e is Background && e.contains(x));
  }

  void generateNextChunck() {
    while (lastGeneratedX < player.x + size.width) {
      Background bg = Background(lastGeneratedX);
      _addBg(bg);

      int amountCoints = 2 + R.nextInt(3);
      final List<Coin> coins = [];
      for (int i = 0; i < amountCoints; i++) {
        Rect spot = bg.findRectFor(bg.columns.randomIdx(R));
        bool top = R.nextBool();
        double x = spot.center.dx;
        double yOffset = Coin.SIZE / 2;
        double y = top ? spot.top + yOffset : spot.bottom - yOffset;
        if (coins.any((c) => c.overlaps(x, y))) {
          continue;
        }
        Coin c = Coin(x, y);
        coins.add(c);
        add(c);
      }
    }
  }

  void _addBg(Background bg) {
    add(bg);
    lastGeneratedX = bg.endX;
  }

  void recalculateScaleFactor(Size rawSize) {
    int blocksWidth = 32;
    int blocksHeight = 18;

    double width = blocksWidth * BLOCK_SIZE;
    double height = blocksHeight * BLOCK_SIZE;

    double scaleX = rawSize.width / width;
    double scaleY = rawSize.height / height;

    this.scale = math.min(scaleX, scaleY);

    this.rawSize = rawSize;
    this.size = Size(width, height);
    this.scaledSize = Size(scale * width, scale * height);
    this.resizeOffset = Position(
      (rawSize.width - scaledSize.width) / 2,
      (rawSize.height - scaledSize.height) / 2,
    );
  }

  int get score => player.x ~/ 100;

  @override
  void resize(Size rawSize) {
    recalculateScaleFactor(rawSize);
    super.resize(size);
  }

  void doShowTutorial() {
    add(tutorial = Tutorial());
    pause();
  }

  @override
  void update(double t) {
    if (paused) {
      tutorial?.update(t);
      return;
    }

    super.update(t);
    if (showTutorial > -1 && player.x >= Tutorial.positions[showTutorial]) {
      doShowTutorial();
      showTutorial++;
      if (showTutorial > 1) {
        showTutorial = -1;
      }
    }

    if (!sleeping) {
      maybeGeneratePlanet(t);
      powerups.maybeGeneratePowerups(t);
      generateNextChunck();
      rotationManager?.tick(t);
    }
  }

  void maybeGeneratePlanet(double dt) {
    planetSpawner.maybeSpawn(dt, () => addLater(Planet(size)));
  }

  void gainExtraLife() {
    hasUsedExtraLife = true;
    player.extraLife();
    paused = true;
    if (showGameOver != null) showGameOver(false);
    sleeping = false;
  }

  @override
  void render(Canvas c) {
    c.save();
    c.translate(resizeOffset.x, resizeOffset.y);
    c.scale(scale, scale);

    c.drawRect(
      Rect.fromLTWH(0.0, 0.0, size.width, size.height),
      Palette.background.paint,
    );
    renderGame(c);

    c.restore();
    c.drawRect(Rect.fromLTWH(0.0, 0.0, rawSize.width, resizeOffset.y), _black);
    c.drawRect(
      Rect.fromLTWH(0.0, resizeOffset.y + scaledSize.height, rawSize.width,
          resizeOffset.y),
      _black,
    );
    c.drawRect(Rect.fromLTWH(0.0, 0.0, resizeOffset.x, rawSize.height), _black);
    c.drawRect(
      Rect.fromLTWH(resizeOffset.x + scaledSize.width, 0.0, resizeOffset.x,
          rawSize.height),
      _black,
    );
  }

  void renderGame(Canvas canvas) {
    renderComponents(canvas);
    if (!sleeping) {
      hud.render(canvas);
    }
    if (paused) {
      bool showMessage = tutorial == null;
      PauseOverlay.render(canvas, size, showMessage);
    }
  }

  void renderComponents(Canvas canvas) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(rotationManager.angle);
    canvas.translate(-size.width / 2, -size.height / 2);
    super.render(canvas);
    canvas.restore();
  }

  Position fixScaleFor(Position rawP) {
    return rawP.clone().minus(resizeOffset).div(scale);
  }

  @override
  void onTapDown(TapDownDetails details) {
    if (player.regularJetpack) {
      player.hoverStart();
    }
  }

  @override
  void onTapUp(TapUpDetails details) {
    if (sleeping) {
      return;
    }
    if (paused) {
      bool isTutorial = tutorial != null;
      resume();
      if (!isTutorial) {
        return;
      }
    }
    super.onTapUp(details);
    if (showTutorial == 0) {
      showTutorial = -1; // if the player jumps don't show the tutorial
    }
    if (player.jetpack) {
      player.boost();
    } else {
      gravity *= -1;
    }
  }

  void pause() {
    Audio.pauseMusic();
    if (sleeping || paused) {
      return;
    }
    paused = true;
  }

  void resume() {
    tutorial?.remove();
    tutorial = null;
    paused = false;
    Audio.resumeMusic();
  }

  @override
  void lifecycleStateChange(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      pause();
    } else {
      Audio.resumeMusic();
    }
  }

  void gameOver() async {
    Audio.die();
    Audio.stopMusic();

    if (score != null && coins != null) {
      GameData.instance.addCoins(coins);
      ScoreBoard.submitScore(score);
    }

    sleeping = true;
    if (showGameOver != null) showGameOver(true);
  }

  void collectCoin() {
    coins++;
    Audio.coin();
  }

  void vibrate() {
    Rumble.rumble();
    cameraHandler.shake();
  }
}
