import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

class GameColors {
  static const background = Colors.black;
  static const wallFill = Color(0xFF080F52);
  static const wallLine = Color(0xFF4DA3FF);
  static const wallGlow = Color(0xFF2962FF);
  static const panel = Color(0xFF0B1030);
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

Color levelColor(GameLevel l) {
  switch (l) {
    case GameLevel.easy:
      return Colors.green.shade500;
    case GameLevel.medium:
      return Colors.orange.shade600;
    case GameLevel.hard:
      return Colors.red.shade500;
  }
}

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
  bool skip = false; // slows ghosts down while frightened
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
    // Global keyboard handler: works no matter which widget has focus.
    HardwareKeyboard.instance.addHandler(_onHardwareKey);

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
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _readyTimer?.cancel();
    _mouthAnimation.dispose();
    _tickAnimation.dispose();
    super.dispose();
  }

  // ── Input ──
  bool _onHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (gameOver) return false; // let dialogs handle keys
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
      return false;
    }
    return true;
  }

  void _changeDirection(Dir d) {
    if (gameOver) return;
    _nextPacDir = d;
  }

  // ── Game flow ──
  void _showLevelSelection() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: _panelDecoration(glow: GameColors.pacman),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _glowText('PAC-MAN', 22, GameColors.pacman),
              const SizedBox(height: 8),
              const Text(
                'SELECT LEVEL',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: Colors.white70),
              ),
              const SizedBox(height: 18),
              for (final level in GameLevel.values)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _resetGame(level);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: levelColor(level),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      level.name.toUpperCase(),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              const Text(
                'ARROWS / WASD  •  SPACE = PAUSE\nOR SWIPE / TAP THE PAD',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 7, color: Colors.white38, height: 1.8),
              ),
            ],
          ),
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
      'SCORE  $score\nBEST   $highScore',
      won ? Colors.greenAccent : Colors.redAccent,
    );
  }

  void _showDialog(String title, String content, Color accent) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: _panelDecoration(glow: accent),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _glowText(title, 20, accent),
              const SizedBox(height: 18),
              Text(
                content,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, height: 2),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _showLevelSelection();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: GameColors.pacman,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('PLAY AGAIN', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ),
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

  /// Returns true if a life was lost (the tick must stop).
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
      final dx = n.x - target.x;
      final dy = n.y - target.y;
      final dist = dx * dx + dy * dy;
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

  // ───────────────────────────────────────────────────────────────────────────
  // UI
  // ───────────────────────────────────────────────────────────────────────────

  BoxDecoration _panelDecoration({Color? glow}) {
    final c = glow ?? GameColors.wallGlow;
    return BoxDecoration(
      color: GameColors.panel,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: c.withValues(alpha: 0.7), width: 1.5),
      boxShadow: [BoxShadow(color: c.withValues(alpha: 0.3), blurRadius: 18)],
    );
  }

  Widget _glowText(String text, double size, Color color) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: size,
        color: color,
        letterSpacing: 2,
        shadows: [
          Shadow(color: color.withValues(alpha: 0.8), blurRadius: 14),
          Shadow(color: color.withValues(alpha: 0.5), blurRadius: 28),
        ],
      ),
    );
  }

  Widget _card(String label, Widget value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 8, color: Colors.white54),
          ),
          const SizedBox(height: 8),
          value,
        ],
      ),
    );
  }

  Widget _statCard(String label, String value) =>
      _card(label, Text(value, style: const TextStyle(fontSize: 14)));

  Widget _livesRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Icon(
              Icons.circle,
              size: 16,
              color: i < lives
                  ? GameColors.pacman
                  : Colors.white.withValues(alpha: 0.12),
              shadows: i < lives
                  ? [Shadow(color: GameColors.pacman, blurRadius: 8)]
                  : null,
            ),
          ),
      ],
    );
  }

  Widget _levelChip() {
    final c = levelColor(_level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c, width: 1.5),
      ),
      child: Text(
        _level.name.toUpperCase(),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 10, color: c),
      ),
    );
  }

  Widget _pauseButton() {
    return GestureDetector(
      onTap: _togglePause,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: GameColors.wallGlow.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: GameColors.wallLine, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(paused ? Icons.play_arrow : Icons.pause, size: 18),
            const SizedBox(width: 6),
            Text(paused ? 'RESUME' : 'PAUSE', style: const TextStyle(fontSize: 9)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1.2,
            colors: [Color(0xFF111A5A), Color(0xFF05071C), Colors.black],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth > c.maxHeight * 1.2;
              return wide ? _buildWide(c) : _buildTall();
            },
          ),
        ),
      ),
    );
  }

  /// Desktop / landscape: info panel | board | controls.
  Widget _buildWide(BoxConstraints c) {
    final panelW = (c.maxWidth * 0.22).clamp(160.0, 280.0).toDouble();
    return Row(
      children: [
        SizedBox(
          width: panelW,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: SizedBox(width: panelW - 28, child: _sidePanel()),
              ),
            ),
          ),
        ),
        Expanded(child: _buildGameCanvas()),
        SizedBox(
          width: panelW,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: _buildControls(62),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sidePanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _glowText('PAC-MAN', 18, GameColors.pacman),
        const SizedBox(height: 20),
        _statCard('SCORE', '$score'),
        const SizedBox(height: 10),
        _statCard('BEST', '$highScore'),
        const SizedBox(height: 10),
        _card('LIVES', _livesRow()),
        const SizedBox(height: 14),
        _levelChip(),
        const SizedBox(height: 10),
        _pauseButton(),
        const SizedBox(height: 16),
        const Text(
          'ARROWS / WASD\nSPACE = PAUSE',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 7, color: Colors.white38, height: 2),
        ),
      ],
    );
  }

  /// Phone / portrait: HUD on top, board, d-pad at the bottom.
  Widget _buildTall() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Column(
            children: [
              _glowText('PAC-MAN', 16, GameColors.pacman),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _statCard('SCORE', '$score')),
                  const SizedBox(width: 10),
                  Expanded(child: _statCard('BEST', '$highScore')),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _livesRow(),
                  _levelChip(),
                  _pauseButton(),
                ],
              ),
            ],
          ),
        ),
        Expanded(child: _buildGameCanvas()),
        Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 4),
          child: _buildControls(58),
        ),
      ],
    );
  }

  Widget _buildGameCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileSize = min(
          (constraints.maxWidth - 16) / cols,
          (constraints.maxHeight - 16) / rows,
        ).clamp(4.0, 1000.0).toDouble();

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (d) {
            if (d.delta.distance < 1.5) return;
            if (d.delta.dx.abs() > d.delta.dy.abs()) {
              _changeDirection(d.delta.dx > 0 ? Dir.right : Dir.left);
            } else {
              _changeDirection(d.delta.dy > 0 ? Dir.down : Dir.up);
            }
          },
          child: Center(
            child: Container(
              width: tileSize * cols,
              height: tileSize * rows,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: GameColors.wallGlow.withValues(alpha: 0.45),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Static maze (cached by the RepaintBoundary).
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _WallPainter(map: map, tileSize: tileSize),
                      ),
                    ),
                  ),
                  // Moving parts.
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
                        padding: EdgeInsets.only(top: tileSize * 3.2),
                        child: _glowText(
                          ready ? 'READY!' : 'PAUSED',
                          max(10, tileSize * 0.75),
                          GameColors.pacman,
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

  Widget _buildControls(double s) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PadButton(
          icon: Icons.keyboard_arrow_up_rounded,
          size: s,
          onPressed: () => _changeDirection(Dir.up),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PadButton(
              icon: Icons.keyboard_arrow_left_rounded,
              size: s,
              onPressed: () => _changeDirection(Dir.left),
            ),
            SizedBox(width: s + 16),
            _PadButton(
              icon: Icons.keyboard_arrow_right_rounded,
              size: s,
              onPressed: () => _changeDirection(Dir.right),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _PadButton(
          icon: Icons.keyboard_arrow_down_rounded,
          size: s,
          onPressed: () => _changeDirection(Dir.down),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// On-screen pad button (reacts instantly on touch / click down)
// ─────────────────────────────────────────────────────────────────────────────

class _PadButton extends StatefulWidget {
  const _PadButton({
    required this.icon,
    required this.size,
    required this.onPressed,
  });

  final IconData icon;
  final double size;
  final VoidCallback onPressed;

  @override
  State<_PadButton> createState() => _PadButtonState();
}

class _PadButtonState extends State<_PadButton> {
  bool _down = false;

  void _set(bool v) {
    if (mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final accent = _down ? GameColors.pacman : GameColors.wallLine;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        _set(true);
        widget.onPressed();
      },
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: _down
                ? [Colors.yellow.shade600, Colors.orange.shade700]
                : [const Color(0xFF2A3A9C), const Color(0xFF0C1448)],
          ),
          border: Border.all(color: accent, width: 2),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: _down ? 0.6 : 0.35),
              blurRadius: _down ? 20 : 12,
            ),
          ],
        ),
        child: Icon(
          widget.icon,
          size: widget.size * 0.62,
          color: _down ? Colors.black : Colors.white,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painters
// ─────────────────────────────────────────────────────────────────────────────

/// Static layer: neon maze outline + ghost-house door. Only repaints when the
/// map or tile size changes.
class _WallPainter extends CustomPainter {
  final List<List<int>> map;
  final double tileSize;

  _WallPainter({required this.map, required this.tileSize});

  @override
  void paint(Canvas canvas, Size size) {
    final rowsN = map.length;
    final colsN = map[0].length;
    bool isWall(int r, int c) =>
        r >= 0 && r < rowsN && c >= 0 && c < colsN && map[r][c] == Tile.wall;

    final fill = Paint()..color = GameColors.wallFill;
    final edges = Path();
    final inset = tileSize * 0.12;

    for (int r = 0; r < rowsN; r++) {
      for (int c = 0; c < colsN; c++) {
        final cell = map[r][c];
        final left = c * tileSize;
        final top = r * tileSize;
        final right = left + tileSize;
        final bottom = top + tileSize;

        if (cell == Tile.door) {
          final doorPaint = Paint()
            ..color = GameColors.door
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(2, tileSize * 0.14)
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(
            Offset(left, top + tileSize / 2),
            Offset(right, top + tileSize / 2),
            doorPaint,
          );
          continue;
        }
        if (cell != Tile.wall) continue;

        canvas.drawRect(
          Rect.fromLTRB(left - 0.5, top - 0.5, right + 0.5, bottom + 0.5),
          fill,
        );

        final up = !isWall(r - 1, c);
        final down = !isWall(r + 1, c);
        final lft = !isWall(r, c - 1);
        final rgt = !isWall(r, c + 1);

        if (up) {
          edges
            ..moveTo(left + (lft ? inset : 0), top + inset)
            ..lineTo(right - (rgt ? inset : 0), top + inset);
        }
        if (down) {
          edges
            ..moveTo(left + (lft ? inset : 0), bottom - inset)
            ..lineTo(right - (rgt ? inset : 0), bottom - inset);
        }
        if (lft) {
          edges
            ..moveTo(left + inset, top + (up ? inset : 0))
            ..lineTo(left + inset, bottom - (down ? inset : 0));
        }
        if (rgt) {
          edges
            ..moveTo(right - inset, top + (up ? inset : 0))
            ..lineTo(right - inset, bottom - (down ? inset : 0));
        }
      }
    }

    // Soft glow underneath, crisp line on top.
    canvas.drawPath(
      edges,
      Paint()
        ..color = GameColors.wallGlow.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(3, tileSize * 0.22)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, tileSize * 0.16),
    );
    canvas.drawPath(
      edges,
      Paint()
        ..color = GameColors.wallLine
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.5, tileSize * 0.09)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _WallPainter old) =>
      old.map != map || old.tileSize != tileSize;
}

/// Dynamic layer: pellets, Pac-Man and ghosts.
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

  /// Interpolated tile position (in tile units). Skips the lerp on tunnel wraps.
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

    // ── Pellets ──
    for (int r = 0; r < map.length; r++) {
      for (int c = 0; c < map[r].length; c++) {
        final cell = map[r][c];
        if (cell != Tile.pellet && cell != Tile.power) continue;
        final center = Offset((c + 0.5) * tileSize, (r + 0.5) * tileSize);
        if (cell == Tile.pellet) {
          paint.color = GameColors.pellet;
          canvas.drawCircle(center, tileSize * 0.1, paint);
        } else {
          final pulse = 0.24 + 0.06 * mouthAnimation.value;
          paint.color = GameColors.pellet.withValues(alpha: 0.25);
          canvas.drawCircle(center, tileSize * (pulse + 0.14), paint);
          paint.color = GameColors.pellet;
          canvas.drawCircle(center, tileSize * pulse, paint);
        }
      }
    }

    // ── Pac-Man ──
    final pacTile = _lerp(prevPac, pac);
    final pacRect = _spriteRect(pacTile).deflate(tileSize * 0.08);
    paint.color = GameColors.pacman.withValues(alpha: 0.22);
    canvas.drawCircle(pacRect.center, tileSize * 0.75, paint);
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
      final body =
          frightened ? (flash ? Colors.white : GameColors.frightened) : g.color;
      paint.color = body.withValues(alpha: 0.2);
      canvas.drawCircle(gr.center, tileSize * 0.7, paint);
      paint.color = body;
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
