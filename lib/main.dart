import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Game constants for easier tweaking
class GameColors {
  static final wall = Colors.blue.shade800;
  static const background = Colors.black;
  static final pellet = Colors.yellow.shade200;
  static final pacman = Colors.yellow.shade600;
  static final ghosts = [
    Colors.red.shade500,
    Colors.pink.shade300,
    Colors.cyan.shade300,
    Colors.orange.shade500,
  ];
}

void main() {
  runApp(const PacManApp());
}

class PacManApp extends StatelessWidget {
  const PacManApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pac-Man (Flutter)',
      theme: ThemeData(
        brightness: Brightness.dark,
        canvasColor: GameColors.background,
        primarySwatch: Colors.blue,
        textTheme: GoogleFonts.pressStart2pTextTheme(
          Theme.of(context).textTheme.apply(
            bodyColor: Colors.white,
            displayColor: Colors.white,
          ),
        ),
      ),
      home: const GamePage(),
    );
  }
}

// --- Enums ---
enum Dir { up, down, left, right, none }

enum GameLevel { easy, medium, hard }

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with TickerProviderStateMixin {
  // Map layout (0=pellet, 1=wall, 2=empty, 3=ghost house)
  static const List<String> _mapLayout = [
    "111111111111111111111",
    "100000000010000000001",
    "101101101111101101101",
    "100000000000000000001",
    "101101011111101011011", // Corrected length to 21, was 20
    "100001000010000100001",
    "111101101111101101111",
    "111101000000000101111",
    "111101011331101011111", // Corrected length to 21, was 20
    "111100013331300011111", // Corrected length to 21, was 20
    "111101013331101011111", // Corrected length to 21, was 20
    "111101000000000101111",
    "111101011111101011111", // Corrected length to 21, was 20
    "100000000010000000001",
    "101101101111101101101",
    "100100000000000001001",
    "110101011111101010111", // Corrected length to 21, was 20
    "100001000010000100001",
    "101111101111101111101",
    "100000000000000000001",
    "111111111111111111111",
  ];

  // Grid configuration - DERIVE from _mapLayout to prevent out-of-bounds errors
  static final int rows = _mapLayout.length;
  static final int cols = _mapLayout[0].length;

  // Game state
  // Initialized to a default empty grid to prevent LateInitializationError.
  // This will be overwritten by _newMap in initState.
  List<List<int>> map = List.generate(
    rows,
    (r) => List.generate(cols, (c) => 2),
  );

  late Timer _timer;
  late GameLevel _level; // Initialized in initState
  int tickMs = 150;
  double ghostAggression = 0.4;
  int score = 0;
  int pelletsLeft = 0;
  bool isRunning = false;
  final Random rand = Random();

  // Pac-man state
  Point<int> pac = const Point<int>(10, 17);
  Dir pacDir = Dir.left;
  Dir _nextPacDir = Dir.left;
  late AnimationController _mouthAnimation;

  // Ghosts state
  final List<Point<int>> ghosts = [
    const Point(10, 9),
    const Point(9, 10),
    const Point(10, 10),
    const Point(11, 10),
  ];
  final List<Dir> ghostDirs = [Dir.left, Dir.right, Dir.up, Dir.down];

  @override
  void initState() {
    super.initState();
    _mouthAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..repeat(reverse: true);

    // Initialize a default level and map immediately so build can function.
    _level = GameLevel.easy;
    _newMap(); // This will populate the map with the actual layout.

    // Show level selection dialog when the widget is first built.
    // This will then call _resetGame and start the actual game timer based on user choice.
    WidgetsBinding.instance.addPostFrameCallback((_) => _showLevelSelection());
  }

  void _showLevelSelection() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.blueGrey.shade900,
        title: const Text('SELECT LEVEL'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: GameLevel.values
              .map<Widget>(
                (level) => ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _resetGame(level);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GameColors.wall,
                  ),
                  child: Text(level.name.toUpperCase()),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  void _resetGame(GameLevel level) {
    // If a timer is already running (e.g., from a previous game), cancel it.
    if (isRunning) {
      _timer.cancel();
    }

    setState(() {
      _level = level;
      switch (level) {
        case GameLevel.easy:
          tickMs = 150;
          ghostAggression = 0.4;
          break;
        case GameLevel.medium:
          tickMs = 120;
          ghostAggression = 0.65;
          break;
        case GameLevel.hard:
          tickMs = 90;
          ghostAggression = 0.85;
          break;
      }
      score = 0;
      _newMap(); // Re-initialize map and other related game objects
      isRunning = true;
      _timer = Timer.periodic(Duration(milliseconds: tickMs), (_) => _tick());
    });
  }

  void _newMap() {
    map = _mapLayout
        .map<List<int>>((row) => row.split('').map<int>(int.parse).toList())
        .toList();

    pelletsLeft = 0;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (map[r][c] == 0) pelletsLeft++;
      }
    }

    pac = const Point(10, 17);
    pacDir = Dir.left;
    _nextPacDir = Dir.left;
    ghosts.setAll(0, [
      const Point(10, 9),
      const Point(9, 10),
      const Point(10, 10),
      const Point(11, 10),
    ]);
  }

  void _tick() {
    if (!isRunning) return;

    setState(() {
      // --- Pac-Man Movement ---
      var nextPacTry = _nextPoint(pac, _nextPacDir);
      if (!_isBlocked(nextPacTry, forPacman: true)) {
        pacDir = _nextPacDir;
        pac = nextPacTry;
      } else {
        var nextPacCurrent = _nextPoint(pac, pacDir);
        if (!_isBlocked(nextPacCurrent, forPacman: true)) {
          pac = nextPacCurrent;
        }
      }

      // --- Eat Pellet ---
      if (map[pac.y][pac.x] == 0) {
        map[pac.y][pac.x] = 2; // Mark as eaten
        score += 10;
        pelletsLeft--;
        if (pelletsLeft <= 0) {
          _showDialog('YOU WIN!', 'Score: $score');
          isRunning = false;
        }
      }

      // --- Ghost Movement ---
      for (int i = 0; i < ghosts.length; i++) {
        final g = ghosts[i];
        final options = _availableDirs(g);
        if (options.isEmpty) continue;

        // Prevent ghosts from reversing direction
        final oppositeDir = _getOpposite(ghostDirs[i]);
        if (options.length > 1 && options.contains(oppositeDir)) {
          options.remove(oppositeDir);
        }

        Dir chosen = ghostDirs[i];
        if (rand.nextDouble() < ghostAggression) {
          // Greedy choice: get closer to Pac-Man
          options.sort((a, b) {
            final pa = _nextPoint(g, a);
            final pb = _nextPoint(g, b);
            final da = (pa.x - pac.x).abs() + (pa.y - pac.y).abs();
            final db = (pb.x - pac.x).abs() + (pb.y - pac.y).abs();
            return da.compareTo(db);
          });
          chosen = options.first;
        } else {
          // Random choice
          chosen = options[rand.nextInt(options.length)];
        }
        ghostDirs[i] = chosen;
        ghosts[i] = _nextPoint(g, chosen);
      }

      // --- Check Collisions ---
      for (final g in ghosts) {
        if (g == pac) {
          _showDialog('GAME OVER', 'Score: $score');
          isRunning = false;
          break;
        }
      }
    });
  }

  Point<int> _nextPoint(Point<int> p, Dir d) {
    // Handle tunnel logic
    if (p.x == 0 && d == Dir.left) return Point(cols - 1, p.y);
    if (p.x == cols - 1 && d == Dir.right) return Point(0, p.y);

    switch (d) {
      case Dir.up:
        return Point(p.x, p.y - 1);
      case Dir.down:
        return Point(p.x, p.y + 1);
      case Dir.left:
        return Point(p.x - 1, p.y);
      case Dir.right:
        return Point(p.x + 1, p.y);
      case Dir.none:
        return p;
    }
  }

  bool _isBlocked(Point<int> p, {bool forPacman = false}) {
    // Check for out of bounds (excluding tunnel wraps)
    if (p.x < 0 || p.x >= cols || p.y < 0 || p.y >= rows) return true;
    final cell = map[p.y][p.x];
    return cell == 1 || (forPacman && cell == 3);
  }

  List<Dir> _availableDirs(Point<int> p) {
    final out = <Dir>[];
    for (final d in [Dir.up, Dir.down, Dir.left, Dir.right]) {
      if (!_isBlocked(_nextPoint(p, d))) out.add(d);
    }
    return out;
  }

  Dir _getOpposite(Dir d) {
    switch (d) {
      case Dir.up:
        return Dir.down;
      case Dir.down:
        return Dir.up;
      case Dir.left:
        return Dir.right;
      case Dir.right:
        return Dir.left;
      default:
        return Dir.none;
    }
  }

  void _changeDirection(Dir d) {
    _nextPacDir = d;
  }

  void _showDialog(String title, String content) {
    if (!mounted) return;
    _timer.cancel(); // Cancel timer when dialog is shown
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.blueGrey.shade900,
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _showLevelSelection();
            },
            child: const Text('Play Again'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Ensure timer is cancelled if it was initialized
    if (isRunning && _timer.isActive) {
      // Check _timer.isActive before cancelling
      _timer.cancel();
    }
    _mouthAnimation.dispose();
    super.dispose();
  }

  // --- Widgets ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildGameCanvas(constraints)),
                _buildControls(),
                const SizedBox(height: 20),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('SCORE: $score', style: const TextStyle(fontSize: 14)),
          // _level is initialized in initState, so it's always safe to display.
          Text(
            'LEVEL: ${_level.name.toUpperCase()}',
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildGameCanvas(BoxConstraints constraints) {
    // Subtract space for header (approx 50) and controls (approx 120) for better calculation
    final availableHeight = constraints.maxHeight - (kToolbarHeight + 120);
    final w = constraints.maxWidth;
    // Ensure h is positive and finite; otherwise, use a reasonable proportion of total height.
    final h = availableHeight.isFinite && availableHeight > 0
        ? availableHeight
        : constraints.maxHeight * 0.7;

    final tileSize = min(w / cols, h / rows);

    return GestureDetector(
      onPanUpdate: (d) {
        if (d.delta.distance < 2) return; // Ignore small movements
        if (isRunning) {
          // Only allow direction changes if game is running
          if (d.delta.dx.abs() > d.delta.dy.abs()) {
            // Horizontal movement is dominant
            _changeDirection(d.delta.dx > 0 ? Dir.right : Dir.left);
          } else {
            // Vertical movement is dominant
            _changeDirection(d.delta.dy > 0 ? Dir.down : Dir.up);
          }
        }
      },
      child: Container(
        color: GameColors.background,
        child: Center(
          child: SizedBox(
            width: tileSize * cols,
            height: tileSize * rows,
            child: CustomPaint(
              painter: _GamePainter(
                map: map,
                pac: pac,
                pacDir: pacDir,
                ghosts: ghosts,
                tileSize: tileSize,
                mouthAnimation: _mouthAnimation,
              ),
            ),
          ),
        ),
      ), // Closing parenthesis for Container, and comma for GestureDetector's child
    ); // Closing parenthesis and semicolon for GestureDetector
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _controlButton(Icons.arrow_left, Dir.left),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _controlButton(Icons.arrow_upward, Dir.up),
              const SizedBox(height: 40),
              _controlButton(Icons.arrow_downward, Dir.down),
            ],
          ),
          _controlButton(Icons.arrow_right, Dir.right),
        ],
      ),
    );
  }

  Widget _controlButton(IconData icon, Dir dir) {
    return InkWell(
      onTap: () {
        if (isRunning) {
          // Only allow direction changes if game is running
          _changeDirection(dir);
        }
      },
      borderRadius: BorderRadius.circular(50),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.blueGrey.shade800.withValues(alpha: 0.8),
        ),
        child: Icon(icon, size: 30),
      ),
    );
  }
}

class _GamePainter extends CustomPainter {
  final List<List<int>> map;
  final Point<int> pac;
  final Dir pacDir;
  final List<Point<int>> ghosts;
  final double tileSize;
  final Animation<double> mouthAnimation;

  _GamePainter({
    required this.map,
    required this.pac,
    required this.pacDir,
    required this.ghosts,
    required this.tileSize,
    required this.mouthAnimation,
  }) : super(repaint: mouthAnimation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // --- Draw Map and Pellets ---
    for (int r = 0; r < map.length; r++) {
      for (int c = 0; c < map[r].length; c++) {
        final rect = Rect.fromLTWH(
          c * tileSize,
          r * tileSize,
          tileSize,
          tileSize,
        );
        if (map[r][c] == 1) {
          // Wall
          paint.color = GameColors.wall;
          paint.style = PaintingStyle.fill;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              rect.deflate(2.0),
              const Radius.circular(4),
            ),
            paint,
          );
        } else if (map[r][c] == 0) {
          // Pellet
          paint.color = GameColors.pellet;
          canvas.drawCircle(rect.center, tileSize * 0.1, paint);
        }
      }
    }

    // --- Draw Pac-Man ---
    final pacRect = Rect.fromLTWH(
      pac.x * tileSize,
      pac.y * tileSize,
      tileSize,
      tileSize,
    );
    paint.color = GameColors.pacman;

    final mouthAngle = (pi / 4) * (1 - mouthAnimation.value);
    double startAngle;

    switch (pacDir) {
      case Dir.right:
        startAngle = mouthAngle;
        break;
      case Dir.left:
        startAngle = pi + mouthAngle;
        break;
      case Dir.up:
        startAngle = -pi / 2 + mouthAngle;
        break;
      case Dir.down:
        startAngle = pi / 2 + mouthAngle;
        break;
      case Dir.none:
        startAngle = mouthAngle;
        break;
    }
    final sweepAngle = 2 * pi - (mouthAngle * 2);
    canvas.drawArc(
      pacRect.deflate(tileSize * 0.1),
      startAngle,
      sweepAngle,
      true,
      paint,
    );

    // --- Draw Ghosts ---
    for (int i = 0; i < ghosts.length; i++) {
      final g = ghosts[i];
      final gr = Rect.fromLTWH(
        g.x * tileSize,
        g.y * tileSize,
        tileSize,
        tileSize,
      ).deflate(tileSize * 0.1);
      paint.color = GameColors.ghosts[i % GameColors.ghosts.length];

      // Ghost body shape
      final path = Path();
      path.moveTo(gr.left, gr.center.dy);
      path.arcTo(
        Rect.fromCircle(
          center: Offset(gr.center.dx, gr.top + gr.height / 4),
          radius: gr.width / 2,
        ),
        pi,
        pi,
        false,
      );
      path.lineTo(gr.right, gr.center.dy);
      // Wavy bottom
      path.quadraticBezierTo(
        gr.right - gr.width / 4,
        gr.bottom + gr.height / 8,
        gr.center.dx,
        gr.bottom,
      );
      path.quadraticBezierTo(
        gr.left + gr.width / 4,
        gr.bottom - gr.height / 8,
        gr.left,
        gr.center.dy,
      );
      path.close();
      canvas.drawPath(path, paint);

      // Eyes
      final eyeRadius = gr.width * 0.15;
      final eyeOffsetX = gr.width * 0.22;
      final eyeOffsetY = gr.height * -0.1;
      final pupilRadius = eyeRadius * 0.5;

      // Left eye
      paint.color = Colors.white;
      canvas.drawCircle(
        gr.center.translate(-eyeOffsetX, eyeOffsetY),
        eyeRadius,
        paint,
      );
      paint.color = Colors.black;
      canvas.drawCircle(
        gr.center.translate(-eyeOffsetX, eyeOffsetY),
        pupilRadius,
        paint,
      );

      // Right eye
      paint.color = Colors.white;
      canvas.drawCircle(
        gr.center.translate(eyeOffsetX, eyeOffsetY),
        eyeRadius,
        paint,
      );
      paint.color = Colors.black;
      canvas.drawCircle(
        gr.center.translate(eyeOffsetX, eyeOffsetY),
        pupilRadius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GamePainter newDelegate) {
    return true;
  }
}
