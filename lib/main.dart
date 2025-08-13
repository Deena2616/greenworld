import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math';

void main() {
  runApp(ForestCarGameApp());
}

class ForestCarGameApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Forest Mountain Drive',
      theme: ThemeData(
        primarySwatch: Colors.green,
      ),
      home: GameScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class GameScreen extends StatefulWidget {
  @override
  _GameScreenState createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  late AnimationController _gameController;
  late AnimationController _carController;

  double carY = 300;
  double scrollOffset = 0;
  int score = 0;
  bool gameStarted = false;
  bool gameOver = false;
  bool showStory = true;

  List<Obstacle> obstacles = [];
  List<Tree> trees = [];
  List<Rock> rocks = [];
  List<WaterDrop> waterDrops = [];

  final Random random = Random();

  @override
  void initState() {
    super.initState();

    _gameController = AnimationController(
      duration: Duration(milliseconds: 16),
      vsync: this,
    );

    _carController = AnimationController(
      duration: Duration(milliseconds: 200),
      vsync: this,
    );

    _initializeGame();
  }

  void _initializeGame() {
    // Generate initial obstacles
    for (int i = 0; i < 10; i++) {
      _generateObstacles(i * 200.0);
    }
  }

  void _generateObstacles(double x) {
    // Generate trees
    if (random.nextDouble() < 0.7) {
      trees.add(Tree(
        x: x + random.nextDouble() * 100,
        y: random.nextDouble() < 0.5 ? 100 : 400,
        type: random.nextInt(3),
      ));
    }

    // Generate rocks
    if (random.nextDouble() < 0.4) {
      rocks.add(Rock(
        x: x + random.nextDouble() * 150,
        y: 300 + random.nextDouble() * 100,
        size: 20 + random.nextDouble() * 30,
      ));
    }

    // Generate water drops
    if (random.nextDouble() < 0.3) {
      waterDrops.add(WaterDrop(
        x: x + random.nextDouble() * 200,
        y: 200 + random.nextDouble() * 200,
      ));
    }
  }

  void _startGame() {
    setState(() {
      showStory = false;
      gameStarted = true;
    });

    _gameController.repeat();

    Timer.periodic(Duration(milliseconds: 16), (timer) {
      if (!gameStarted || gameOver) {
        timer.cancel();
        return;
      }

      _updateGame();
    });
  }

  void _updateGame() {
    setState(() {
      scrollOffset += 3;
      score = (scrollOffset / 10).round();

      // Generate new obstacles as we scroll
      if (scrollOffset % 200 == 0) {
        _generateObstacles(scrollOffset + 800);
      }

      // Remove off-screen obstacles
      trees.removeWhere((tree) => tree.x < scrollOffset - 100);
      rocks.removeWhere((rock) => rock.x < scrollOffset - 100);
      waterDrops.removeWhere((drop) => drop.x < scrollOffset - 100);

      // Check collisions with rocks (game over)
      for (Rock rock in rocks) {
        if (_checkCollision(rock.x, rock.y, rock.size)) {
          _endGame();
          return;
        }
      }

      // Collect water drops (bonus points)
      waterDrops.removeWhere((drop) {
        if (_checkCollision(drop.x, drop.y, 20)) {
          score += 10;
          return true;
        }
        return false;
      });
    });
  }

  bool _checkCollision(double obstacleX, double obstacleY, double obstacleSize) {
    double carX = 100;
    double carWidth = 60;
    double carHeight = 30;

    return (obstacleX - scrollOffset < carX + carWidth &&
        obstacleX - scrollOffset + obstacleSize > carX &&
        obstacleY < carY + carHeight &&
        obstacleY + obstacleSize > carY);
  }

  void _endGame() {
    setState(() {
      gameOver = true;
      gameStarted = false;
    });
    _gameController.stop();
  }

  void _resetGame() {
    setState(() {
      carY = 300;
      scrollOffset = 0;
      score = 0;
      gameStarted = false;
      gameOver = false;
      showStory = false;

      obstacles.clear();
      trees.clear();
      rocks.clear();
      waterDrops.clear();
    });

    _initializeGame();
    _startGame();
  }

  void _moveCar(double deltaY) {
    setState(() {
      carY = (carY + deltaY).clamp(50.0, 450.0);
    });

    _carController.forward().then((_) => _carController.reverse());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onPanUpdate: (details) {
          if (gameStarted) {
            _moveCar(details.delta.dy);
          }
        },
        onTap: () {
          if (showStory) {
            _startGame();
          } else if (gameOver) {
            _resetGame();
          }
        },
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF87CEEB), // Sky blue
                Color(0xFF98FB98), // Pale green
                Color(0xFF228B22), // Forest green
              ],
            ),
          ),
          child: Stack(
            children: [
              // Background mountains
              _buildMountains(),

              // Game elements
              if (!showStory) ...[
                // Trees
                ...trees.map((tree) => _buildTree(tree)).toList(),

                // Rocks
                ...rocks.map((rock) => _buildRock(rock)).toList(),

                // Water drops
                ...waterDrops.map((drop) => _buildWaterDrop(drop)).toList(),

                // Car
                _buildCar(),

                // UI
                _buildUI(),
              ],

              // Story overlay
              if (showStory) _buildStoryOverlay(),

              // Game over overlay
              if (gameOver) _buildGameOverOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMountains() {
    return CustomPaint(
      size: Size(double.infinity, double.infinity),
      painter: MountainPainter(scrollOffset),
    );
  }

  Widget _buildCar() {
    return AnimatedBuilder(
      animation: _carController,
      builder: (context, child) {
        return Positioned(
          left: 100 - (_carController.value * 5),
          top: carY,
          child: Container(
            width: 60,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 5,
                  offset: Offset(2, 2),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Car body details
                Positioned(
                  left: 10,
                  top: 5,
                  child: Container(
                    width: 40,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.blue[200],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                // Wheels
                Positioned(
                  left: 5,
                  bottom: -5,
                  child: Container(
                    width: 15,
                    height: 15,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  right: 5,
                  bottom: -5,
                  child: Container(
                    width: 15,
                    height: 15,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTree(Tree tree) {
    return Positioned(
      left: tree.x - scrollOffset,
      top: tree.y,
      child: Container(
        width: 40,
        height: 80,
        child: Column(
          children: [
            Container(
              width: 30,
              height: 50,
              decoration: BoxDecoration(
                color: tree.type == 0
                    ? Colors.green[600]
                    : tree.type == 1
                    ? Colors.green[700]
                    : Colors.green[500],
                shape: BoxShape.circle,
              ),
            ),
            Container(
              width: 8,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.brown[600],
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRock(Rock rock) {
    return Positioned(
      left: rock.x - scrollOffset,
      top: rock.y,
      child: Container(
        width: rock.size,
        height: rock.size,
        decoration: BoxDecoration(
          color: Colors.grey[600],
          borderRadius: BorderRadius.circular(rock.size / 4),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 3,
              offset: Offset(2, 2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaterDrop(WaterDrop drop) {
    return Positioned(
      left: drop.x - scrollOffset,
      top: drop.y,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: Colors.blue[300],
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withOpacity(0.3),
              blurRadius: 5,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(
          Icons.opacity,
          color: Colors.white,
          size: 12,
        ),
      ),
    );
  }

  Widget _buildUI() {
    return Positioned(
      top: 50,
      left: 20,
      right: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Score: $score',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Distance: ${(scrollOffset / 10).round()}m',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoryOverlay() {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.directions_car,
                size: 80,
                color: Colors.white,
              ),
              SizedBox(height: 30),
              Text(
                'FOREST MOUNTAIN ADVENTURE',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 30),
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(
                  'You are driving through the mystical Forest Mountains on a quest to reach the ancient Crystal Springs. Navigate carefully through the dense forest filled with towering trees and dangerous rocks. Collect magical water drops along the way to boost your score!\n\nAvoid the rocks or your journey ends!\n\nDrag to move your car up and down.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(height: 40),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.5),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Text(
                  'TAP TO START ADVENTURE',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGameOverOverlay() {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.warning,
              size: 80,
              color: Colors.red,
            ),
            SizedBox(height: 20),
            Text(
              'JOURNEY ENDED!',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            SizedBox(height: 20),
            Text(
              'You crashed into a rock!\nYour adventure has come to an end.',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 30),
            Container(
              padding: EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Text(
                    'Final Score: $score',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  Text(
                    'Distance Traveled: ${(scrollOffset / 10).round()}m',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 40),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(25),
              ),
              child: Text(
                'TAP TO RESTART',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _gameController.dispose();
    _carController.dispose();
    super.dispose();
  }
}

class MountainPainter extends CustomPainter {
  final double scrollOffset;

  MountainPainter(this.scrollOffset);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // Draw distant mountains
    paint.color = Colors.grey[400]!;
    final path1 = Path();
    path1.moveTo(-scrollOffset * 0.1, size.height * 0.4);
    path1.lineTo(200 - scrollOffset * 0.1, size.height * 0.2);
    path1.lineTo(400 - scrollOffset * 0.1, size.height * 0.3);
    path1.lineTo(600 - scrollOffset * 0.1, size.height * 0.1);
    path1.lineTo(800 - scrollOffset * 0.1, size.height * 0.25);
    path1.lineTo(size.width + 100, size.height * 0.35);
    path1.lineTo(size.width + 100, size.height);
    path1.lineTo(-100, size.height);
    path1.close();
    canvas.drawPath(path1, paint);

    // Draw closer mountains
    paint.color = Colors.grey[600]!;
    final path2 = Path();
    path2.moveTo(-scrollOffset * 0.2, size.height * 0.6);
    path2.lineTo(150 - scrollOffset * 0.2, size.height * 0.4);
    path2.lineTo(350 - scrollOffset * 0.2, size.height * 0.5);
    path2.lineTo(550 - scrollOffset * 0.2, size.height * 0.3);
    path2.lineTo(750 - scrollOffset * 0.2, size.height * 0.45);
    path2.lineTo(size.width + 100, size.height * 0.55);
    path2.lineTo(size.width + 100, size.height);
    path2.lineTo(-100, size.height);
    path2.close();
    canvas.drawPath(path2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class Obstacle {
  double x, y;

  Obstacle({required this.x, required this.y});
}

class Tree extends Obstacle {
  int type;

  Tree({required double x, required double y, required this.type})
      : super(x: x, y: y);
}

class Rock extends Obstacle {
  double size;

  Rock({required double x, required double y, required this.size})
      : super(x: x, y: y);
}

class WaterDrop extends Obstacle {
  WaterDrop({required double x, required double y}) : super(x: x, y: y);
}