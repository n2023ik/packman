import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

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
      theme: ThemeData.dark(),
      home: const GamePage(),
    );
  }
}

enum Dir { up, down, left, right, none }

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with SingleTickerProviderStateMixin {
  // Grid configuration
  static const int rows = 21; // odd numbers keep center
  static const int cols = 21;

  late final double tilePadding = 2.0;
  late Timer _timer;
  final int tickMs = 120; // speed (lower = faster)

  // Map: 0 = empty/pellet, 1 = wall (blocked), 2 = eaten pellet (empty)
  late List<List<int>> map;

  // Pac-man
  Point<int> pac = Point<int>(10, 15);
  Dir pacDir = Dir.left;

  // Ghosts
  final List<Point<int>> ghosts = [Point(10, 9), Point(9, 9), Point(11, 9)];
  final List<Dir> ghostDirs = [Dir.left, Dir.right, Dir.up];

  int score = 0;
  int pelletsLeft = 0;
  bool isRunning = true;
  final Random rand = Random();

  @override
  void initState() {
    super.initState();
    _newMap();
    _timer = Timer.periodic(Duration(milliseconds: tickMs), (_) => _tick());
  }

  void _newMap() {
    // create simple map with outer walls and some interior walls
    map = List.generate(rows, (r) => List.generate(cols, (c) => 0));

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        // outer walls
        if (r == 0 || r == rows - 1 || c == 0 || c == cols - 1) {
          map[r][c] = 1;
        }
      }
    }

    // Simple pattern of walls
    for (int r = 2; r < rows - 2; r += 4) {
      for (int c = 2; c < cols - 2; c++) {
        if (c % 3 == 0) map[r][c] = 1;
      }
    }

    // Create some open corridors
    map[10][10] = 2; // center empty (ghost house open)

    // count pellets
    pelletsLeft = 0;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (map[r][c] == 0) {
          pelletsLeft++;
        }
      }
    }

    // Set starting positions
    pac = Point(10, 15);
    pacDir = Dir.left;
    ghosts.setAll(0, [Point(10, 9), Point(9, 9), Point(11, 9)]);
  }

  void _tick() {
    if (!isRunning) return;

    setState(() {
      // Move pacman
      final nextPac = _nextPoint(pac, pacDir);
      if (!_isBlocked(nextPac)) {
        pac = nextPac;
      }

      // Eat pellet
      if (map[pac.y][pac.x] == 0) {
        map[pac.y][pac.x] = 2;
        score += 10;
        pelletsLeft--;
        if (pelletsLeft <= 0) {
          // Win - regenerate map
          _showDialog('You win!', 'Score: \$score');
          isRunning = false;
        }
      }

      // Move ghosts (simple random / greedy behavior)
      for (int i = 0; i < ghosts.length; i++) {
        final g = ghosts[i];
        // simple chase: try to reduce Manhattan distance with some randomness
        final options = _availableDirs(g);
        if (options.isEmpty) continue;

        Dir chosen = ghostDirs[i];
        if (rand.nextDouble() < 0.6) {
          // greedy choice
          options.sort((a, b) {
            final pa = _nextPoint(g, a);
            final pb = _nextPoint(g, b);
            final da = (pa.x - pac.x).abs() + (pa.y - pac.y).abs();
            final db = (pb.x - pac.x).abs() + (pb.y - pac.y).abs();
            return da.compareTo(db);
          });
          chosen = options.first;
        } else {
          chosen = options[rand.nextInt(options.length)];
        }

        ghostDirs[i] = chosen;
        ghosts[i] = _nextPoint(g, chosen);
      }

      // Check collisions
      for (final g in ghosts) {
        if (g == pac) {
          _showDialog('Game Over', 'Score: \$score');
          isRunning = false;
          break;
        }
      }
    });
  }

  Point<int> _nextPoint(Point<int> p, Dir d) {
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

  bool _isBlocked(Point<int> p) {
    if (p.x < 0 || p.x >= cols || p.y < 0 || p.y >= rows) return true;
    return map[p.y][p.x] == 1;
  }

  List<Dir> _availableDirs(Point<int> p) {
    final out = <Dir>[];
    for (final d in [Dir.up, Dir.down, Dir.left, Dir.right]) {
      final np = _nextPoint(p, d);
      if (!_isBlocked(np)) out.add(d);
    }
    return out;
  }

  void _changeDirection(Dir d) {
    // set pacman direction; it will only move if next cell is free
    setState(() {
      pacDir = d;
      final np = _nextPoint(pac, pacDir);
      if (_isBlocked(np)) {
        // keep previous direction if blocked
      }
    });
  }

  void _showDialog(String title, String content) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                setState(() {
                  score = 0;
                  _newMap();
                  isRunning = true;
                });
              },
              child: const Text('Play Again'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
              },
              child: const Text('Close'),
            ),
          ],
        ),
      );
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  // Swipe handling
  Offset? _dragStart;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pac-Man (Flutter) - Simple Demo'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Center(child: Text('Score: \$score')),
          )
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight - kToolbarHeight - MediaQuery.of(context).padding.top;
        final tileSize = min(w / cols, h / rows);

        return GestureDetector(
          onPanStart: (d) => _dragStart = d.localPosition,
          onPanUpdate: (d) {
            if (_dragStart == null) return;
            final delta = d.localPosition - _dragStart!;
            if (delta.distance > 20) {
              if (delta.dx.abs() > delta.dy.abs()) {
                if (delta.dx > 0) _changeDirection(Dir.right);
                else _changeDirection(Dir.left);
              } else {
                if (delta.dy > 0) _changeDirection(Dir.down);
                else _changeDirection(Dir.up);
              }
              _dragStart = d.localPosition;
            }
          },
          child: Column(
            children: [
              SizedBox(
                width: tileSize * cols,
                height: tileSize * rows,
                child: CustomPaint(
                  painter: _GamePainter(
                    map: map,
                    pac: pac,
                    pacDir: pacDir,
                    ghosts: ghosts,
                    tileSize: tileSize,
                    tilePadding: tilePadding,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _buildControls(),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ElevatedButton(
            onPressed: () => _changeDirection(Dir.left),
            child: const Icon(Icons.arrow_left),
          ),
          Column(
            children: [
              ElevatedButton(
                onPressed: () => _changeDirection(Dir.up),
                child: const Icon(Icons.arrow_upward),
              ),
              const SizedBox(height: 6),
              ElevatedButton(
                onPressed: () => _changeDirection(Dir.down),
                child: const Icon(Icons.arrow_downward),
              ),
            ],
          ),
          ElevatedButton(
            onPressed: () => _changeDirection(Dir.right),
            child: const Icon(Icons.arrow_right),
          ),
        ],
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
  final double tilePadding;

  _GamePainter({
    required this.map,
    required this.pac,
    required this.pacDir,
    required this.ghosts,
    required this.tileSize,
    required this.tilePadding,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // background grid
    for (int r = 0; r < map.length; r++) {
      for (int c = 0; c < map[r].length; c++) {
        final rect = Rect.fromLTWH(
          c * tileSize + tilePadding,
          r * tileSize + tilePadding,
          tileSize - tilePadding * 2,
          tileSize - tilePadding * 2,
        );

        if (map[r][c] == 1) {
          paint.color = Colors.blue.shade900;
          canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), paint);
        } else {
          paint.color = Colors.black;
          canvas.drawRect(rect, paint);

          if (map[r][c] == 0) {
            // pellet
            final cx = rect.left + rect.width / 2;
            final cy = rect.top + rect.height / 2;
            final pelletRadius = rect.width * 0.08;
            paint.color = Colors.white;
            canvas.drawCircle(Offset(cx, cy), pelletRadius, paint);
          }
        }
      }
    }

    // draw pacman as arc
    final pacRect = Rect.fromLTWH(
      pac.x * tileSize + tilePadding,
      pac.y * tileSize + tilePadding,
      tileSize - tilePadding * 2,
      tileSize - tilePadding * 2,
    );

    paint.color = Colors.yellow.shade600;
    final mouthAngle = pi / 4;
    double startAngle;

    switch (pacDir) {
      case Dir.right:
        startAngle = mouthAngle / 2;
        break;
      case Dir.left:
        startAngle = pi + mouthAngle / 2;
        break;
      case Dir.up:
        startAngle = -pi / 2 + mouthAngle / 2;
        break;
      case Dir.down:
        startAngle = pi / 2 + mouthAngle / 2;
        break;
      case Dir.none:
        startAngle = 0;
        break;
    }

    canvas.drawArc(pacRect.deflate(tileSize * 0.06), startAngle, 2 * pi - mouthAngle, true, paint);

    // ghosts
    final ghostColors = [Colors.red, Colors.pink, Colors.cyan, Colors.orange];
    for (int i = 0; i < ghosts.length; i++) {
      final g = ghosts[i];
      final gr = Rect.fromLTWH(
        g.x * tileSize + tilePadding,
        g.y * tileSize + tilePadding,
        tileSize - tilePadding * 2,
        tileSize - tilePadding * 2,
      );
      paint.color = ghostColors[i % ghostColors.length];
      canvas.drawOval(gr.deflate(tileSize * 0.06), paint);
      // eyes
      final eyeRadius = gr.width * 0.12;
      final eyeOffsetX = gr.width * 0.18;
      final eyeOffsetY = gr.height * 0.12;
      paint.color = Colors.white;
      canvas.drawCircle(Offset(gr.left + eyeOffsetX, gr.top + eyeOffsetY + eyeRadius), eyeRadius, paint);
      canvas.drawCircle(Offset(gr.right - eyeOffsetX, gr.top + eyeOffsetY + eyeRadius), eyeRadius, paint);
      paint.color = Colors.black;
      canvas.drawCircle(Offset(gr.left + eyeOffsetX, gr.top + eyeOffsetY + eyeRadius), eyeRadius * 0.5, paint);
      canvas.drawCircle(Offset(gr.right - eyeOffsetX, gr.top + eyeOffsetY + eyeRadius), eyeRadius * 0.5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GamePainter oldDelegate) => true;
}
