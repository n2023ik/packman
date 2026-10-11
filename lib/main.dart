import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

class GameColors {
  static final wall = Colors.blue.shade700;
  static final wallFill = const Color(0xFF0A1560);
  static const background = Colors.black;
  static final pellet = Colors.yellow.shade200;
  static final pacman = Colors.yellow.shade600;
  static final frightened = Colors.blue.shade600;
  static final door = Colors.pink.shade200;
  static final ghosts = [
    Colors.red.shade500, // Blinky – chases directly
    Colors.pink.shade300, // Pinky  – ambushes ahead of Pac-Man
    Colors.cyan.shade300, // Inky   – unpredictable flanker
    Colors.orange.shade500, // Clyde  – chases, then gets shy
  ];
}

/// Tile codes used by the maze.
class Tile {
  static const pellet = 0;
  static const wall = 1;
  static const empty = 2;
  static const house = 3; // ghost-house interior
  static const door = 4; // ghost-house door
  static const power = 5; // power pellet
}

enum Dir { up, down, left, right, none }

enum GameLevel { easy, medium, hard }

Point<int> dirVector(Dir d) {
  switch (d) {
    case Dir.up:
      return const Point(0, -1);
    case Dir.down:
      return const Point(0, 1);
    case Dir.left:
      return const Point(-1, 0);
    case Dir.right:
      return const Point(1, 0);
    case Dir.none:
      return const Point(0, 0);
  }
}

Dir oppositeOf(Dir d) {
  switch (d) {
    case Dir.up:
      return Dir.down;
    case Dir.down:
      return Dir.up;
    case Dir.left:
      return Dir.right;
    case Dir.right:
      return Dir.left;
    case Dir.none:
      return Dir.none;
  }
}

class Ghost {
  Ghost({required this.color, required this.type, required this.home})
      : pos = home,
        prev = home;

  final Color color;
  final int type; // 0 Blinky, 1 Pinky, 2 Inky, 3 Clyde
  final Point<int> home;

  Point<int> pos;
  Point<int> prev;
  Dir dir = Dir.left;
  bool eaten = false;
  bool skip = false; // used to slow ghosts down while frightened
  int releaseAt = 0; // tick at which the ghost leaves the house

  void reset(int release) {
    pos = home;
    prev = home;
    dir = Dir.left;
    eaten = false;
    skip = false;
    releaseAt = release;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// App
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  runApp(const PacManApp());
}

class PacManApp extends StatelessWidget {
  const PacManApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: GameColors.background,
      canvasColor: GameColors.background,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pac-Man (Flutter)',
      theme: base.copyWith(
        textTheme: GoogleFonts.pressStart2pTextTheme(base.textTheme).apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
      ),
      home: const GamePage(),
    );
  }
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // Maze: 0 pellet, 1 wall, 2 empty, 3 ghost house, 4 ghost door, 5 power pellet.
  // Symmetric 21x21, with a tunnel on row 9.
  static const List<String> _mapLayout = [
    "111111111111111111111",
    "100000000010000000001",
    "101101111010111101101",
    "150000000000000000051",
    "101101011111110101101",
    "100001000000000100001",
    "101111011111110111101",
    "100000000000000000001",
    "111101111141111101111",
    "222000013333310000222",
    "111101111111111101111",
    "100000000000000000001",
    "101101111010111101101",
    "100100000000000001001",
    "110101011111110101011",
    "100000000010000000001",
    "101101111010111101101",
    "150000000000000000051",
    "101101011111110101101",
    "100000000000000000001",
    "111111111111111111111",
  ];

  static final int rows = _mapLayout.length;
  static final int cols = _mapLayout[0].length;

  static const Point<int> _pacStart = Point(10, 17);
  static const Point<int> _houseCenter = Point(10, 9);
  static const Point<int> _houseExit = Point(10, 7);
  static const List<Dir> _moveDirs = [Dir.up, Dir.down, Dir.left, Dir.right];

  // ── Game state ──
  late List<List<int>> map;
  GameLevel _level = GameLevel.easy;
  int tickMs = 150;
  double ghostAggression = 0.4;
  int _frightTicks = 55;
  int _releaseGap = 30;

  int score = 0;
  int highScore = 0;
  int lives = 3;
  int pelletsLeft = 0;
  int tickCount = 0;
  int frightenedTicks = 0;
  int ghostCombo = 0;

  bool isRunning = false; // game loop is ticking
  bool gameOver = true; // no game in progress
  bool paused = false;
  bool ready = false; // "READY!" countdown

  Timer? _timer;
  Timer? _readyTimer;
  final Random rand = Random();
  final FocusNode _focusNode = FocusNode();

  late final AnimationController _mouthAnimation;
  late final AnimationController _tickAnimation; // smooth tile-to-tile motion

  // Pac-Man
  Point<int> pac = _pacStart;
  Point<int> prevPac = _pacStart;
  Dir pacDir = Dir.left;
  Dir _nextPacDir = Dir.left;

  // Ghosts
  late final List<Ghost> ghosts = [
    Ghost(color: GameColors.ghosts[0], type: 0, home: const Point(10, 7)),
    Ghost(color: GameColors.ghosts[1], type: 1, home: const Point(10, 9)),
    Ghost(color: GameColors.ghosts[2], type: 2, home: const Point(9, 9)),
    Ghost(color: GameColors.ghosts[3], type: 3, home: const Point(11, 9)),
  ];

  // ── Lifecycle ──
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _mouthAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..repeat(reverse: true);

    _tickAnimation = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: tickMs),
      value: 1.0,
    );

    _newMap();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showLevelSelection());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Auto-pause when the app goes to the background.
    if (state != AppLifecycleState.resumed && !gameOver && !paused) {
      _stopLoop();
      setState(() => paused = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _readyTimer?.cancel();
    _mouthAnimation.dispose();
    _tickAnimation.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Game flow ──
  void _showLevelSelection() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.blueGrey.shade900,
        title: const Text('SELECT LEVEL', style: TextStyle(fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: GameLevel.values
              .map<Widget>(
                (level) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _resetGame(level);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GameColors.wall,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(
                      level.name.toUpperCase(),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  void _applyLevel(GameLevel level) {
    _level = level;
    switch (level) {
      case GameLevel.easy:
        tickMs = 150;
        ghostAggression = 0.4;
        _frightTicks = 55;
        _releaseGap = 30;
        break;
      case GameLevel.medium:
        tickMs = 120;
        ghostAggression = 0.65;
        _frightTicks = 40;
        _releaseGap = 22;
        break;
      case GameLevel.hard:
        tickMs = 90;
        ghostAggression = 0.85;
        _frightTicks = 28;
        _releaseGap = 15;
        break;
    }
    _tickAnimation.duration = Duration(milliseconds: tickMs);
  }

  void _resetGame(GameLevel level) {
    _stopLoop();
    _readyTimer?.cancel();
    _applyLevel(level);
    score = 0;
    lives = 3;
    gameOver = false;
    paused = false;
    _newMap();
    _beginReady();
    _focusNode.requestFocus();
  }

  void _newMap() {
    map = _mapLayout
        .map<List<int>>((row) => row.split('').map<int>(int.parse).toList())
        .toList();
    map[_pacStart.y][_pacStart.x] = Tile.empty; // no pellet under Pac-Man

    pelletsLeft = 0;
    for (final row in map) {
      for (final cell in row) {
        if (cell == Tile.pellet || cell == Tile.power) pelletsLeft++;
      }
    }
    _resetPositions();
  }

  void _resetPositions() {
    pac = _pacStart;
    prevPac = _pacStart;
    pacDir = Dir.left;
    _nextPacDir = Dir.left;
    tickCount = 0;
    frightenedTicks = 0;
    ghostCombo = 0;
    for (int i = 0; i < ghosts.length; i++) {
      ghosts[i].reset(i * _releaseGap);
    }
    _tickAnimation.value = 1.0;
  }

  void _beginReady() {
    _readyTimer?.cancel();
    setState(() => ready = true);
    _readyTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() => ready = false);
      if (!paused && !gameOver) _startLoop();
    });
  }

  void _startLoop() {
    _timer?.cancel();
    isRunning = true;
    _timer = Timer.periodic(Duration(milliseconds: tickMs), (_) => _tick());
  }

  void _stopLoop() {
    _timer?.cancel();
    _timer = null;
    isRunning = false;
    _tickAnimation.value = 1.0; // settle sprites exactly on their tiles
  }

  void _togglePause() {
    if (gameOver || ready) return;
    setState(() => paused = !paused);
    if (paused) {
      _stopLoop();
    } else {
      _startLoop();
    }
    _focusNode.requestFocus();
  }

  void _loseLife() {
    _stopLoop();
    lives--;
    if (lives <= 0) {
      _finish(won: false);
      return;
    }
    _resetPositions();
    _beginReady();
  }

  void _finish({required bool won}) {
    _stopLoop();
    if (score > highScore) highScore = score;
    setState(() => gameOver = true);
    _showDialog(
      won ? 'YOU WIN!' : 'GAME OVER',
      'Score: $score\nBest: $highScore',
    );
  }

  void _showDialog(String title, String content) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.blueGrey.shade900,
        title: Text(title, style: const TextStyle(fontSize: 16)),
        content: Text(content, style: const TextStyle(fontSize: 12, height: 1.6)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _showLevelSelection();
            },
            child: const Text('Play Again', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ── Game loop ──
  void _tick() {
    if (!isRunning) return;
    tickCount++;

    if (frightenedTicks > 0) {
      frightenedTicks--;
      if (frightenedTicks == 0) ghostCombo = 0;
    }

    _movePac();
    _collect();

    if (pelletsLeft <= 0) {
      _finish(won: true);
      return;
    }
    if (_handleCollisions(ghostsMoved: false)) return;

    for (final g in ghosts) {
      _moveGhost(g);
    }
    if (_handleCollisions(ghostsMoved: true)) return;

    setState(() {});
    _tickAnimation.forward(from: 0);
  }

  void _movePac() {
    prevPac = pac;
    final wanted = _nextPoint(pac, _nextPacDir);
    if (!_isBlocked(wanted)) {
      pacDir = _nextPacDir;
      pac = wanted;
    } else {
      final straight = _nextPoint(pac, pacDir);
      if (!_isBlocked(straight)) pac = straight;
    }
  }

  void _collect() {
    final cell = map[pac.y][pac.x];
    if (cell == Tile.pellet) {
      map[pac.y][pac.x] = Tile.empty;
      score += 10;
      pelletsLeft--;
    } else if (cell == Tile.power) {
      map[pac.y][pac.x] = Tile.empty;
      score += 50;
      pelletsLeft--;
      frightenedTicks = _frightTicks;
      ghostCombo = 0;
      for (final g in ghosts) {
        if (!g.eaten && !_inHouse(g.pos)) g.dir = oppositeOf(g.dir);
      }
    }
    if (score > highScore) highScore = score;
  }

  /// Returns true if the game state changed in a way that ends this tick
  /// (a life was lost).
  bool _handleCollisions({required bool ghostsMoved}) {
    for (final g in ghosts) {
      if (g.eaten) continue;
      final hit = g.pos == pac ||
          (ghostsMoved && g.pos == prevPac && g.prev == pac); // swapped places
      if (!hit) continue;

      if (frightenedTicks > 0) {
        g.eaten = true;
        score += 200 * (1 << ghostCombo);
        ghostCombo = min(ghostCombo + 1, 3);
        if (score > highScore) highScore = score;
      } else {
        _loseLife();
        return true;
      }
    }
    return false;
  }

  // ── Ghost AI ──
  bool _inHouse(Point<int> p) {
    final c = map[p.y][p.x];
    return c == Tile.house || c == Tile.door;
  }

  void _moveGhost(Ghost g) {
    g.prev = g.pos;
    if (tickCount < g.releaseAt) return; // still waiting in the house

    final frightened = frightenedTicks > 0 && !g.eaten;
    if (frightened) {
      g.skip = !g.skip;
      if (g.skip) return; // frightened ghosts move at half speed
    }

    // Eaten ghosts rush back to the house, then revive.
    if (g.eaten) {
      if (g.pos == _houseCenter) {
        g.eaten = false;
        g.dir = Dir.up;
      } else {
        final d = _bfsDir(g.pos, _houseCenter);
        if (d != null) {
          g.dir = d;
          g.pos = _nextPoint(g.pos, d);
        }
        return;
      }
    }

    final inHouse = _inHouse(g.pos);
    final options = <Dir>[
      for (final d in _moveDirs)
        if (!_isBlocked(_nextPoint(g.pos, d), house: inHouse)) d,
    ];
    if (options.isEmpty) return;

    // Don't reverse unless it's the only choice.
    final back = oppositeOf(g.dir);
    if (options.length > 1) options.remove(back);

    Dir chosen;
    if (inHouse) {
      // Head for the exit.
      chosen = _bestToward(g.pos, options, _houseExit);
    } else if (frightened) {
      chosen = options[rand.nextInt(options.length)];
    } else if (rand.nextDouble() < ghostAggression) {
      chosen = _bestToward(g.pos, options, _ghostTarget(g));
    } else {
      chosen = options[rand.nextInt(options.length)];
    }

    g.dir = chosen;
    g.pos = _nextPoint(g.pos, chosen);
  }

  Dir _bestToward(Point<int> from, List<Dir> options, Point<int> target) {
    Dir best = options.first;
    int bestDist = 1 << 30;
    for (final d in options) {
      final n = _nextPoint(from, d);
      final dist = pow(n.x - target.x, 2).toInt() + pow(n.y - target.y, 2).toInt();
      if (dist < bestDist) {
        bestDist = dist;
        best = d;
      }
    }
    return best;
  }

  Point<int> _ghostTarget(Ghost g) {
    final v = dirVector(pacDir);
    switch (g.type) {
      case 0: // Blinky: straight at Pac-Man
        return pac;
      case 1: // Pinky: four tiles ahead of Pac-Man
        return Point<int>(pac.x + v.x * 4, pac.y + v.y * 4);
      case 2: // Inky: mirror Blinky around a point two tiles ahead of Pac-Man
        final ax = pac.x + v.x * 2;
        final ay = pac.y + v.y * 2;
        final b = ghosts[0].pos;
        return Point<int>(2 * ax - b.x, 2 * ay - b.y);
      default: // Clyde: chase when far away, retreat to a corner when close
        final dist = (g.pos.x - pac.x).abs() + (g.pos.y - pac.y).abs();
        return dist > 8 ? pac : Point<int>(1, rows - 2);
    }
  }

  /// Shortest-path first step from [from] to [to] (ghosts may use the house).
  Dir? _bfsDir(Point<int> from, Point<int> to) {
    if (from == to) return null;
    final startKey = from.y * cols + from.x;
    final visited = <int>{startKey};
    final first = <int, Dir>{};
    final queue = <Point<int>>[from];
    int head = 0;
    while (head < queue.length) {
      final cur = queue[head++];
      final curKey = cur.y * cols + cur.x;
      for (final d in _moveDirs) {
        final n = _nextPoint(cur, d);
        if (_isBlocked(n, house: true)) continue;
        final key = n.y * cols + n.x;
        if (!visited.add(key)) continue;
        first[key] = curKey == startKey ? d : first[curKey]!;
        if (n == to) return first[key];
        queue.add(n);
      }
    }
    return null;
  }

  // ── Movement helpers ──
  Point<int> _nextPoint(Point<int> p, Dir d) {
    // Tunnel wrap
    if (p.x == 0 && d == Dir.left) return Point(cols - 1, p.y);
    if (p.x == cols - 1 && d == Dir.right) return Point(0, p.y);
    final v = dirVector(d);
    return Point(p.x + v.x, p.y + v.y);
  }

  bool _isBlocked(Point<int> p, {bool house = false}) {
    if (p.x < 0 || p.x >= cols || p.y < 0 || p.y >= rows) return true;
    final cell = map[p.y][p.x];
    if (cell == Tile.wall) return true;
    if (cell == Tile.house || cell == Tile.door) return !house;
    return false;
  }

  void _changeDirection(Dir d) {
    if (gameOver) return;
    _nextPacDir = d;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.keyW) {
      _changeDirection(Dir.up);
    } else if (k == LogicalKeyboardKey.arrowDown ||
        k == LogicalKeyboardKey.keyS) {
      _changeDirection(Dir.down);
    } else if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.keyA) {
      _changeDirection(Dir.left);
    } else if (k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.keyD) {
      _changeDirection(Dir.right);
    } else if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.keyP) {
      _togglePause();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ── UI ──
  @override
  Widget build(BuildContext context) {
    final showPad = MediaQuery.sizeOf(context).width < 800;
    return Scaffold(
      body: SafeArea(
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildGameCanvas()),
              if (showPad) _buildControls(),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    const small = TextStyle(fontSize: 10);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('SCORE $score', style: small),
              Text('BEST $highScore', style: small),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: List.generate(
                  max(lives, 0),
                  (_) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(Icons.circle, color: GameColors.pacman, size: 14),
                  ),
                ),
              ),
              Text(_level.name.toUpperCase(), style: small),
              SizedBox(
                height: 28,
                width: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 22,
                  tooltip: paused ? 'Resume' : 'Pause',
                  onPressed: _togglePause,
                  icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGameCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileSize = min(
          constraints.maxWidth / cols,
          constraints.maxHeight / rows,
        );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (d) {
            if (d.delta.distance < 2) return;
            if (d.delta.dx.abs() > d.delta.dy.abs()) {
              _changeDirection(d.delta.dx > 0 ? Dir.right : Dir.left);
            } else {
              _changeDirection(d.delta.dy > 0 ? Dir.down : Dir.up);
            }
          },
          child: Center(
            child: SizedBox(
              width: tileSize * cols,
              height: tileSize * rows,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _GamePainter(
                        map: map,
                        pac: pac,
                        prevPac: prevPac,
                        pacDir: pacDir,
                        ghosts: ghosts,
                        frightenedTicks: frightenedTicks,
                        tileSize: tileSize,
                        mouthAnimation: _mouthAnimation,
                        tickAnimation: _tickAnimation,
                      ),
                    ),
                  ),
                  if (ready || paused)
                    Center(
                      child: Padding(
                        padding: EdgeInsets.only(top: tileSize * 3),
                        child: Text(
                          ready ? 'READY!' : 'PAUSED',
                          style: TextStyle(
                            fontSize: max(10, tileSize * 0.7),
                            color: GameColors.pacman,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _controlButton(Icons.keyboard_arrow_up, Dir.up),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _controlButton(Icons.keyboard_arrow_left, Dir.left),
            const SizedBox(width: 48),
            _controlButton(Icons.keyboard_arrow_right, Dir.right),
          ],
        ),
        _controlButton(Icons.keyboard_arrow_down, Dir.down),
      ],
    );
  }

  Widget _controlButton(IconData icon, Dir dir) {
    return InkWell(
      onTap: () => _changeDirection(dir),
      borderRadius: BorderRadius.circular(50),
      child: Container(
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.blueGrey.shade800.withValues(alpha: 0.8),
        ),
        child: Icon(icon, size: 30),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painter
// ─────────────────────────────────────────────────────────────────────────────

class _GamePainter extends CustomPainter {
  final List<List<int>> map;
  final Point<int> pac;
  final Point<int> prevPac;
  final Dir pacDir;
  final List<Ghost> ghosts;
  final int frightenedTicks;
  final double tileSize;
  final Animation<double> mouthAnimation;
  final Animation<double> tickAnimation;

  _GamePainter({
    required this.map,
    required this.pac,
    required this.prevPac,
    required this.pacDir,
    required this.ghosts,
    required this.frightenedTicks,
    required this.tileSize,
    required this.mouthAnimation,
    required this.tickAnimation,
  }) : super(repaint: Listenable.merge([mouthAnimation, tickAnimation]));

  /// Interpolated tile position (in tile units). Skips the lerp for tunnel wraps.
  Offset _lerp(Point<int> from, Point<int> to) {
    if ((to.x - from.x).abs() > 1 || (to.y - from.y).abs() > 1) {
      return Offset(to.x.toDouble(), to.y.toDouble());
    }
    final t = tickAnimation.value;
    return Offset(
      from.x + (to.x - from.x) * t,
      from.y + (to.y - from.y) * t,
    );
  }

  Rect _spriteRect(Offset tilePos) => Rect.fromLTWH(
        tilePos.dx * tileSize,
        tilePos.dy * tileSize,
        tileSize,
        tileSize,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final wallFill = Paint()..color = GameColors.wallFill;
    final wallStroke = Paint()
      ..color = GameColors.wall
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.5, tileSize * 0.1);

    // ── Maze ──
    for (int r = 0; r < map.length; r++) {
      for (int c = 0; c < map[r].length; c++) {
        final rect = Rect.fromLTWH(c * tileSize, r * tileSize, tileSize, tileSize);
        switch (map[r][c]) {
          case Tile.wall:
            final rr = RRect.fromRectAndRadius(
              rect.deflate(tileSize * 0.08),
              Radius.circular(tileSize * 0.25),
            );
            canvas.drawRRect(rr, wallFill);
            canvas.drawRRect(rr, wallStroke);
            break;
          case Tile.pellet:
            paint.color = GameColors.pellet;
            canvas.drawCircle(rect.center, tileSize * 0.1, paint);
            break;
          case Tile.power:
            paint.color = GameColors.pellet;
            canvas.drawCircle(
              rect.center,
              tileSize * (0.24 + 0.06 * mouthAnimation.value),
              paint,
            );
            break;
          case Tile.door:
            paint
              ..color = GameColors.door
              ..style = PaintingStyle.stroke
              ..strokeWidth = max(2, tileSize * 0.14);
            canvas.drawLine(rect.centerLeft, rect.centerRight, paint);
            paint.style = PaintingStyle.fill;
            break;
          default:
            break;
        }
      }
    }
    paint.style = PaintingStyle.fill;

    // ── Pac-Man ──
    final pacRect = _spriteRect(_lerp(prevPac, pac)).deflate(tileSize * 0.08);
    paint.color = GameColors.pacman;

    final mouth = (pi / 4) * (1 - mouthAnimation.value);
    double startAngle;
    switch (pacDir) {
      case Dir.right:
      case Dir.none:
        startAngle = mouth;
        break;
      case Dir.left:
        startAngle = pi + mouth;
        break;
      case Dir.up:
        startAngle = -pi / 2 + mouth;
        break;
      case Dir.down:
        startAngle = pi / 2 + mouth;
        break;
    }
    canvas.drawArc(pacRect, startAngle, 2 * pi - mouth * 2, true, paint);

    // ── Ghosts ──
    for (final g in ghosts) {
      final gr = _spriteRect(_lerp(g.prev, g.pos)).deflate(tileSize * 0.08);
      _drawGhost(canvas, paint, g, gr);
    }
  }

  void _drawGhost(Canvas canvas, Paint paint, Ghost g, Rect gr) {
    final frightened = frightenedTicks > 0 && !g.eaten;
    final flash = frightened && frightenedTicks <= 10 && frightenedTicks.isEven;

    if (!g.eaten) {
      paint.color =
          frightened ? (flash ? Colors.white : GameColors.frightened) : g.color;
      canvas.drawPath(_ghostBody(gr), paint);
    }

    final eyeR = gr.width * 0.16;
    final eyeDx = gr.width * 0.2;
    final eyeY = gr.center.dy - gr.height * 0.08;
    final left = Offset(gr.center.dx - eyeDx, eyeY);
    final right = Offset(gr.center.dx + eyeDx, eyeY);

    if (frightened) {
      paint.color = flash ? Colors.red.shade400 : Colors.pink.shade100;
      canvas.drawCircle(left, eyeR * 0.6, paint);
      canvas.drawCircle(right, eyeR * 0.6, paint);
    } else {
      final v = dirVector(g.dir);
      final shift = Offset(v.x.toDouble(), v.y.toDouble()) * (eyeR * 0.45);
      paint.color = Colors.white;
      canvas.drawCircle(left, eyeR, paint);
      canvas.drawCircle(right, eyeR, paint);
      paint.color = Colors.blue.shade900;
      canvas.drawCircle(left + shift, eyeR * 0.5, paint);
      canvas.drawCircle(right + shift, eyeR * 0.5, paint);
    }
  }

  Path _ghostBody(Rect gr) {
    final r = gr.width / 2;
    final waveH = gr.height * 0.14;
    final seg = gr.width / 3;
    final path = Path()
      ..moveTo(gr.left, gr.bottom)
      ..lineTo(gr.left, gr.top + r)
      ..arcToPoint(
        Offset(gr.right, gr.top + r),
        radius: Radius.circular(r),
      )
      ..lineTo(gr.right, gr.bottom);
    // Scalloped bottom edge, right to left.
    for (int i = 0; i < 3; i++) {
      final x0 = gr.right - seg * i;
      final x1 = x0 - seg;
      path.quadraticBezierTo((x0 + x1) / 2, gr.bottom - waveH * 2, x1, gr.bottom);
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _GamePainter oldDelegate) => true;
}
