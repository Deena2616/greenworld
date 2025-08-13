import 'dart:math';
import 'package:flame/camera.dart';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      theme: ThemeData(
        textTheme: GoogleFonts.signikaTextTheme(),
      ),
      home: GameWidget(
        game: NeonRunnerGame(),
        overlayBuilderMap: {
          'MainMenu': (ctx, game) => MainMenu(gameRef: game as NeonRunnerGame),
          'HUD': (ctx, game) => HUDOverlay(gameRef: game as NeonRunnerGame),
          'PauseMenu': (ctx, game) => PauseMenu(gameRef: game as NeonRunnerGame),
          'GameOver': (ctx, game) => GameOverOverlay(gameRef: game as NeonRunnerGame),
          'Shop': (ctx, game) => ShopOverlay(gameRef: game as NeonRunnerGame),
        },
        initialActiveOverlays: const ['MainMenu'],
      ),
    ),
  );
}

/// Main Game
class NeonRunnerGame extends FlameGame with TapDetector, HasCollisionDetection {
  late Player player;
  final Random _rand = Random();
  double _spawnTimer = 0;
  double spawnInterval = 1.0;
  int score = 0;
  int coins = 0;
  int highScore = 0;
  int lives = 3;
  bool shield = false;
  double shieldTimer = 0.0;
  bool slowTime = false;
  double slowTimer = 0.0;
  double difficultyTimer = 0.0;
  double distance = 0.0;

  @override
  Color backgroundColor() => const Color(0xFF0B0F1C);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    // Set up camera with fixed resolution
    camera = CameraComponent.withFixedResolution(width: 420, height: 800);

    player = Player()
      ..position = Vector2(420 / 2, 800 - 120)
      ..anchor = Anchor.center;
    add(player);

    // Load persisted data
    final prefs = await SharedPreferences.getInstance();
    highScore = prefs.getInt('neon_high_score') ?? 0;
    coins = prefs.getInt('neon_coins') ?? 0;
  }

  @override
  void update(double dt) {
    if (paused) return;
    super.update(dt);

    final effectiveDt = slowTime ? dt * 0.4 : dt;
    _spawnTimer += effectiveDt;
    difficultyTimer += effectiveDt;
    distance += effectiveDt * (1 + score / 200);

    // Gradually make it harder
    if (difficultyTimer > 10) {
      difficultyTimer = 0;
      spawnInterval = max(0.4, spawnInterval - 0.08);
    }

    // Spawn obstacles and coins
    if (_spawnTimer >= spawnInterval) {
      _spawnTimer = 0;
      spawnPattern();
    }

    // Shield timer
    if (shield) {
      shieldTimer -= dt;
      if (shieldTimer <= 0) {
        shield = false;
      }
    }

    if (slowTime) {
      slowTimer -= dt;
      if (slowTimer <= 0) slowTime = false;
    }

    // Small score increase by distance
    score = (distance * 1.2).toInt();

    // Clamp lives
    lives = lives.clamp(0, 99);
  }

  void spawnPattern() {
    final y = -40.0;
    const laneCount = 5;
    final laneW = 420 / laneCount; // Use fixed width
    // Pick random pattern
    final pattern = _rand.nextInt(4);
    if (pattern == 0) {
      // Single obstacle
      final lane = _rand.nextInt(laneCount);
      add(Obstacle(Vector2(laneW * lane + laneW / 2, y)));
    } else if (pattern == 1) {
      // Two obstacles
      final l1 = _rand.nextInt(laneCount);
      int l2 = _rand.nextInt(laneCount);
      while (l2 == l1) l2 = _rand.nextInt(laneCount);
      add(Obstacle(Vector2(laneW * l1 + laneW / 2, y)));
      add(Obstacle(Vector2(laneW * l2 + laneW / 2, y)));
    } else if (pattern == 2) {
      // Zigzag fast obstacles
      final lane = _rand.nextInt(laneCount);
      add(Obstacle(Vector2(laneW * lane + laneW / 2, y), isFast: true, zigzag: true));
    } else {
      // Spawn a coin or power-up
      final pick = _rand.nextDouble();
      final lane = _rand.nextInt(laneCount);
      final pos = Vector2(laneW * lane + laneW / 2, y);
      if (pick < 0.6) {
        add(Coin(pos));
      } else if (pick < 0.85) {
        add(PowerUp(pos, PowerType.shield));
      } else {
        add(PowerUp(pos, PowerType.slow));
      }
    }
  }

  @override
  void onTapDown(TapDownInfo info) {
    if (overlays.isActive('MainMenu')) return;
    final touch = camera.globalToLocal(info.eventPosition.global); // Fix: Use globalToLocal
    player.moveTo(touch.x);
  }

  Future<void> playerHit() async {
    if (shield) {
      shield = false;
      return;
    }
    lives--;
    if (lives <= 0) {
      pauseEngine();
      final prefs = await SharedPreferences.getInstance();
      if (score > highScore) {
        highScore = score;
        await prefs.setInt('neon_high_score', highScore);
      }
      await prefs.setInt('neon_coins', coins);
      overlays.remove('HUD');
      overlays.add('GameOver');
    }
  }

  void collectCoin() {
    coins += 1;
  }

  void activatePower(PowerType type) {
    if (type == PowerType.shield) {
      shield = true;
      shieldTimer = 6.0;
    } else if (type == PowerType.slow) {
      slowTime = true;
      slowTimer = 5.0;
    }
  }

  void resetGame() {
    children.whereType<Obstacle>().forEach((c) => c.removeFromParent());
    children.whereType<Coin>().forEach((c) => c.removeFromParent());
    children.whereType<PowerUp>().forEach((c) => c.removeFromParent());
    player.position = Vector2(420 / 2, 800 - 120);
    shield = false;
    slowTime = false;
    shieldTimer = 0;
    slowTimer = 0;
    score = 0;
    distance = 0;
    spawnInterval = 1.0;
    lives = 3;
    overlays.remove('GameOver');
    overlays.add('HUD');
    resumeEngine();
  }
}

/// Player component
class Player extends PositionComponent with HasGameRef<NeonRunnerGame>, CollisionCallbacks {
  final Paint _paint = Paint()
    ..shader = const LinearGradient(
      colors: [Color(0xFF00FFD5), Color(0xFF00A7FF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ).createShader(Rect.fromLTWH(0, 0, 58, 58));
  double speed = 900.0;

  Player() : super(size: Vector2(58, 58), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox()..collisionType = CollisionType.active);
  }

  void moveTo(double x) {
    final clampedX = x.clamp(size.x / 2, 420 - size.x / 2); // Use fixed width
    position.x = clampedX;
  }

  @override
  void render(Canvas canvas) {
    final r = size.x / 2;
    final center = Offset(r, r);
    final glow = Paint()..color = const Color(0x40FFFFFF);
    canvas.drawCircle(center, r + 6, glow);
    final shapePaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFFFFFFFF), Color(0xFF00FFD5)],
      ).createShader(Rect.fromCircle(center: center, radius: r));
    canvas.drawCircle(center, r - 3, shapePaint);
  }
}

/// Obstacle
class Obstacle extends PositionComponent with HasGameRef<NeonRunnerGame>, CollisionCallbacks {
  final bool isFast;
  final bool zigzag;
  final double fallSpeed; // Fix: Initialize in constructor
  double zigWave = 0;
  final Paint paint = Paint();

  Obstacle(Vector2 start, {this.isFast = false, this.zigzag = false})
      : fallSpeed = isFast ? 420 : 220, // Initialize fallSpeed
        super(position: start, size: Vector2(48, 48), anchor: Anchor.center) {
    paint.shader = const LinearGradient(
      colors: [Color(0xFFEA4C89), Color(0xFF8A2BE2)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ).createShader(Rect.fromLTWH(0, 0, 48, 48));
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox()..collisionType = CollisionType.passive);
  }

  @override
  void update(double dt) {
    super.update(dt);
    final effectiveSpeed = gameRef.slowTime ? fallSpeed * 0.45 : fallSpeed;
    position.add(Vector2(0, effectiveSpeed * dt));
    if (zigzag) {
      zigWave += dt * 6;
      position.x += sin(zigWave) * 40 * dt;
    }
    if (position.y > 800 + 80) {
      removeFromParent();
      gameRef.distance += 0.2;
    }
  }

  @override
  void render(Canvas canvas) {
    final rrect = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.x, size.y), const Radius.circular(10));
    canvas.drawRRect(rrect, paint);
    final inner = Paint()..color = Colors.white.withOpacity(0.08);
    canvas.drawRRect(rrect.deflate(4), inner);
  }

  @override
  void onCollision(Set<Vector2> points, PositionComponent other) {
    if (other is Player) {
      removeFromParent();
      gameRef.playerHit();
    }
    super.onCollision(points, other);
  }
}

/// Coin
class Coin extends PositionComponent with HasGameRef<NeonRunnerGame>, CollisionCallbacks {
  final Paint _paint = Paint()
    ..shader = const SweepGradient(
      colors: [Color(0xFFFFD166), Color(0xFFFFA726)],
    ).createShader(Rect.fromLTWH(0, 0, 28, 28));
  double fallSpeed = 200;

  Coin(Vector2 start) : super(position: start, size: Vector2(28, 28), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox()..collisionType = CollisionType.passive);
  }

  @override
  void update(double dt) {
    super.update(dt);
    final effectiveSpeed = gameRef.slowTime ? fallSpeed * 0.45 : fallSpeed;
    position.add(Vector2(0, effectiveSpeed * dt));
    if (position.y > 800 + 60) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    canvas.drawCircle(Offset(size.x / 2, size.y / 2), size.x / 2, _paint);
  }

  @override
  void onCollision(Set<Vector2> points, PositionComponent other) {
    if (other is Player) {
      removeFromParent();
      gameRef.collectCoin();
    }
    super.onCollision(points, other);
  }
}

enum PowerType { shield, slow }

/// Power-up
class PowerUp extends PositionComponent with HasGameRef<NeonRunnerGame>, CollisionCallbacks {
  final PowerType type;
  double fallSpeed = 180;

  PowerUp(Vector2 start, this.type) : super(position: start, size: Vector2(34, 34), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox()..collisionType = CollisionType.passive);
    final text = TextComponent(
      text: type == PowerType.shield ? 'S' : 'T',
      textRenderer: TextPaint(
        style: GoogleFonts.signika(
          fontSize: type == PowerType.shield ? 18 : 16,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      position: Vector2(8, 6),
    );
    add(text);
  }

  @override
  void update(double dt) {
    super.update(dt);
    final effectiveSpeed = gameRef.slowTime ? fallSpeed * 0.45 : fallSpeed;
    position.add(Vector2(0, effectiveSpeed * dt));
    if (position.y > 800 + 60) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final p = Paint()
      ..shader = (type == PowerType.shield
          ? const LinearGradient(colors: [Color(0xFF7EF9A6), Color(0xFF00FFD5)])
          : const LinearGradient(colors: [Color(0xFF8AC7FF), Color(0xFF5E8BFB)]))
          .createShader(Rect.fromLTWH(0, 0, 34, 34));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.x, size.y), p);
  }

  @override
  void onCollision(Set<Vector2> points, PositionComponent other) {
    if (other is Player) {
      removeFromParent();
      gameRef.activatePower(type);
    }
    super.onCollision(points, other);
  }
}

/// Overlays (Flutter widgets)
class MainMenu extends StatelessWidget {
  final NeonRunnerGame gameRef;
  const MainMenu({Key? key, required this.gameRef}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'NEON RUNNER',
              style: GoogleFonts.signika(
                fontSize: 44,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                shadows: [Shadow(blurRadius: 14, color: Colors.cyanAccent)],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Dodge • Collect • Survive',
              style: GoogleFonts.signika(color: Colors.white70),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
                backgroundColor: Colors.purpleAccent,
              ),
              onPressed: () {
                gameRef.overlays.remove('MainMenu');
                gameRef.overlays.add('HUD');
                gameRef.resetGame();
              },
              child: Text('Play', style: GoogleFonts.signika(fontSize: 18)),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
              onPressed: () {
                gameRef.overlays.remove('MainMenu');
                gameRef.overlays.add('Shop');
              },
              child: Text('Shop', style: GoogleFonts.signika(fontSize: 16)),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[800]),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: Text('About', style: GoogleFonts.signika()),
                    content: Text('Neon Runner — Heavy Edition\nBuilt with Flame & Flutter.', style: GoogleFonts.signika()),
                    actions: [
                      TextButton(
                        child: Text('OK', style: GoogleFonts.signika()),
                        onPressed: () => Navigator.of(c).pop(),
                      ),
                    ],
                  ),
                );
              },
              child: Text('About', style: GoogleFonts.signika(fontSize: 16)),
            ),
            const SizedBox(height: 36),
            Text('High Score: ${gameRef.highScore}', style: GoogleFonts.signika(color: Colors.white70)),
            const SizedBox(height: 8),
            Text('Coins: ${gameRef.coins}', style: GoogleFonts.signika(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

class HUDOverlay extends StatelessWidget {
  final NeonRunnerGame gameRef;
  const HUDOverlay({Key? key, required this.gameRef}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Score: ${gameRef.score}',
                  style: GoogleFonts.signika(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Coins: ${gameRef.coins}',
                  style: GoogleFonts.signika(color: Colors.white70),
                ),
              ],
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Lives: ${gameRef.lives}',
                  style: GoogleFonts.signika(color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  'High: ${gameRef.highScore}',
                  style: GoogleFonts.signika(color: Colors.green),
                ),
              ],
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black54,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onPressed: () {
                gameRef.pauseEngine();
                gameRef.overlays.add('PauseMenu');
              },
              child: const Icon(Icons.pause, color: Colors.green),
            ),
          ],
        ),
      ),
    );
  }
}

class PauseMenu extends StatelessWidget {
  final NeonRunnerGame gameRef;
  const PauseMenu({Key? key, required this.gameRef}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black38,
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Paused', style: GoogleFonts.signika(fontSize: 28, color: Colors.white)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  gameRef.overlays.remove('PauseMenu');
                  gameRef.resumeEngine();
                },
                child: Text('Resume', style: GoogleFonts.signika(fontSize: 16)),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () {
                  gameRef.overlays.remove('PauseMenu');
                  gameRef.overlays.remove('HUD');
                  gameRef.overlays.add('MainMenu');
                  gameRef.pauseEngine();
                },
                child: Text('Exit to Menu', style: GoogleFonts.signika(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GameOverOverlay extends StatelessWidget {
  final NeonRunnerGame gameRef;
  const GameOverOverlay({Key? key, required this.gameRef}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black45,
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          width: 340,
          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Game Over', style: GoogleFonts.signika(fontSize: 30, color: Colors.white)),
              const SizedBox(height: 8),
              Text('Score: ${gameRef.score}', style: GoogleFonts.signika(color: Colors.white70)),
              Text('High Score: ${gameRef.highScore}', style: GoogleFonts.signika(color: Colors.white70)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  gameRef.resetGame();
                },
                child: Text('Retry', style: GoogleFonts.signika(fontSize: 16)),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () {
                  gameRef.overlays.remove('GameOver');
                  gameRef.overlays.add('MainMenu');
                },
                child: Text('Main Menu', style: GoogleFonts.signika(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ShopOverlay extends StatelessWidget {
  final NeonRunnerGame gameRef;
  const ShopOverlay({Key? key, required this.gameRef}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black54,
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(14),
          width: 360,
          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Shop', style: GoogleFonts.signika(fontSize: 22, color: Colors.white)),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.shield, color: Colors.white),
                title: Text('Shield (1 use)', style: GoogleFonts.signika(color: Colors.white)),
                subtitle: Text('Cost: 10 coins', style: GoogleFonts.signika(color: Colors.white70)),
                trailing: ElevatedButton(
                  onPressed: () async {
                    if (gameRef.coins >= 10) {
                      gameRef.coins -= 10;
                      gameRef.activatePower(PowerType.shield);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setInt('neon_coins', gameRef.coins);
                      gameRef.overlays.remove('Shop');
                      gameRef.overlays.add('MainMenu');
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Not enough coins', style: GoogleFonts.signika())),
                      );
                    }
                  },
                  child: Text('Buy', style: GoogleFonts.signika(fontSize: 16)),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.timelapse, color: Colors.white),
                title: Text('Slow Time (1 use)', style: GoogleFonts.signika(color: Colors.white)),
                subtitle: Text('Cost: 14 coins', style: GoogleFonts.signika(color: Colors.white70)),
                trailing: ElevatedButton(
                  onPressed: () async {
                    if (gameRef.coins >= 14) {
                      gameRef.coins -= 14;
                      gameRef.activatePower(PowerType.slow);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setInt('neon_coins', gameRef.coins);
                      gameRef.overlays.remove('Shop');
                      gameRef.overlays.add('MainMenu');
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Not enough coins', style: GoogleFonts.signika())),
                      );
                    }
                  },
                  child: Text('Buy', style: GoogleFonts.signika(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () {
                  gameRef.overlays.remove('Shop');
                  gameRef.overlays.add('MainMenu');
                },
                child: Text('Close', style: GoogleFonts.signika(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}