import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

const Color kRed = Color(0xFFE53935);
const Color kGreen = Color(0xFF2E7D32);
const Color kBg = Color(0xFFF5F7FA);
const Color kInk = Color(0xFF111111);
const Color kGrey = Color(0xFF8A94A3);
const Color kLine = Color(0xFFE3E8EF);

const double kRate = 0.15;
const double kWaitSeconds = 5.0;
const double kCrashShowSeconds = 3.0;
const double kStartBalance = 20.0;
const int kMinBet = 10;
const int kMaxBet = 100000;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const AvitoApp());
}

class AvitoApp extends StatelessWidget {
  const AvitoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Avito',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kRed,
          brightness: Brightness.light,
        ).copyWith(surface: Colors.white, surfaceTint: Colors.transparent),
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: kInk,
          selectionHandleColor: kInk,
          selectionColor: kInk.withAlpha(40),
        ),
      ),
      home: const GamePage(),
    );
  }
}

enum Phase { waiting, flying, crashed }

String fmt(double v) {
  final parts = v.toStringAsFixed(2).split('.');
  final ip = parts[0];
  final buf = StringBuffer();
  for (int i = 0; i < ip.length; i++) {
    final fromEnd = ip.length - i;
    buf.write(ip[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(',');
  }
  return '${buf.toString()}.${parts[1]}';
}

class Tap extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;

  const Tap({super.key, required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: child,
    );
  }
}

class BetDialog extends StatefulWidget {
  final int initial;

  const BetDialog({super.key, required this.initial});

  @override
  State<BetDialog> createState() => _BetDialogState();
}

class _BetDialogState extends State<BetDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: '${widget.initial}');
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = int.tryParse(_controller.text.trim());
    if (v == null || v < kMinBet) {
      setState(() => _error = 'Minimum ₹$kMinBet');
      return;
    }
    if (v > kMaxBet) {
      setState(() => _error = 'Maximum ₹$kMaxBet');
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Bet Amount',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: kInk,
        ),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: kInk,
        ),
        decoration: InputDecoration(
          prefixText: '₹ ',
          errorText: _error,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kLine),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kInk, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kRed),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kRed, width: 1.5),
          ),
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        Tap(
          onTap: () => Navigator.of(context).pop(),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: kGrey,
              ),
            ),
          ),
        ),
        Tap(
          onTap: _submit,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            decoration: BoxDecoration(
              color: kGreen,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'OK',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage>
    with SingleTickerProviderStateMixin {
  final math.Random _rng = math.Random();
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  final ValueNotifier<double> _countdown = ValueNotifier<double>(kWaitSeconds);
  final List<double> _history = [];
  late final Ticker _ticker;

  int _tab = 0;
  Phase _phase = Phase.waiting;
  double _phaseStart = -1;
  double _lastNow = 0;
  double _crashPoint = 1.5;
  double _balance = kStartBalance;
  double _betAmount = kMinBet.toDouble();
  double _pendingBet = 0;
  double _activeBet = 0;

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 14; i++) {
      _history.add(_genCrash());
    }
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    _countdown.dispose();
    super.dispose();
  }

  double _genCrash() {
    final r = _rng.nextDouble();
    double c = 0.96 / (1 - r);
    if (c < 1.01) c = 1.01;
    if (c > 100) c = 100;
    return (c * 100).floorToDouble() / 100;
  }

  void _setPhase(Phase p, double now) {
    _phaseStart = now;
    if (!mounted) return;
    setState(() {
      _phase = p;
    });
  }

  void _onTick(Duration d) {
    if (!mounted) return;
    final now = d.inMicroseconds / 1000000.0;
    if (_phaseStart < 0) {
      _phaseStart = now;
      _lastNow = now;
    }
    final dt = now - _lastNow;
    _lastNow = now;
    if (dt > 0.5) {
      _phaseStart += dt;
    }

    switch (_phase) {
      case Phase.waiting:
        final remaining = kWaitSeconds - (now - _phaseStart);
        if (remaining <= 0) {
          _crashPoint = _genCrash();
          _activeBet = _pendingBet;
          _pendingBet = 0;
          _time.value = 0;
          _setPhase(Phase.flying, now);
        } else {
          _countdown.value = remaining;
        }
        break;
      case Phase.flying:
        final t = now - _phaseStart;
        if (math.exp(kRate * t) >= _crashPoint) {
          _time.value = math.log(_crashPoint) / kRate;
          _history.insert(0, _crashPoint);
          if (_history.length > 20) _history.removeLast();
          _activeBet = 0;
          _setPhase(Phase.crashed, now);
        } else {
          _time.value = t;
        }
        break;
      case Phase.crashed:
        if (now - _phaseStart >= kCrashShowSeconds) {
          _time.value = 0;
          _countdown.value = kWaitSeconds;
          _setPhase(Phase.waiting, now);
        }
        break;
    }
  }

  void _snack(String msg, {Color color = kInk}) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(
        msg,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(milliseconds: 1600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _placeBet() {
    if (_betAmount > _balance) {
      _snack('Insufficient balance', color: kRed);
      return;
    }
    setState(() {
      _balance -= _betAmount;
      _pendingBet = _betAmount;
    });
  }

  void _cancelBet() {
    if (_pendingBet <= 0) return;
    setState(() {
      _balance += _pendingBet;
      _pendingBet = 0;
    });
  }

  void _cashOut() {
    if (_phase != Phase.flying || _activeBet <= 0) return;
    double m = math.exp(kRate * _time.value);
    m = (m * 100).floorToDouble() / 100;
    final win = _activeBet * m;
    setState(() {
      _balance += win;
      _activeBet = 0;
    });
    _snack(
      'Cashed out at ${m.toStringAsFixed(2)}x  •  Won ₹${fmt(win)}',
      color: kGreen,
    );
  }

  void _changeBet(int dir) {
    final next = _betAmount + dir * 10;
    setState(() {
      _betAmount =
          next.clamp(kMinBet.toDouble(), kMaxBet.toDouble()).toDouble();
    });
  }

  Future<void> _editBet() async {
    final value = await showDialog<int>(
      context: context,
      builder: (_) => BetDialog(initial: _betAmount.toInt()),
    );
    if (value != null && mounted) {
      setState(() {
        _betAmount = value.toDouble();
      });
    }
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: kRed,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.flight, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          const Text(
            'Avito',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: kRed,
              letterSpacing: 0.3,
            ),
          ),
          const Spacer(),
          Tap(
            onTap: () => setState(() => _tab = 1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: kBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: kLine),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.account_balance_wallet_outlined,
                    color: kInk,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '₹ ${fmt(_balance)}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: kInk,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyStrip() {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: _history.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final v = _history[i];
          final c = v >= 2.0 ? kGreen : kRed;
          return Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: c.withAlpha(24),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: c.withAlpha(70)),
            ),
            child: Text(
              '${v.toStringAsFixed(2)}x',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: c,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _graph() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kLine),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: GraphPainter(time: _time, phase: _phase),
              ),
            ),
            Positioned.fill(
              child: Center(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_time, _countdown]),
                  builder: (context, _) {
                    if (_phase == Phase.waiting) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'NEXT ROUND IN',
                            style: TextStyle(
                              fontSize: 13,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w700,
                              color: kGrey,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${_countdown.value.ceil()}s',
                            style: const TextStyle(
                              fontSize: 56,
                              fontWeight: FontWeight.w900,
                              color: kInk,
                            ),
                          ),
                        ],
                      );
                    }
                    if (_phase == Phase.crashed) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'FLEW AWAY!',
                            style: TextStyle(
                              fontSize: 16,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w800,
                              color: kRed,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_crashPoint.toStringAsFixed(2)}x',
                            style: const TextStyle(
                              fontSize: 58,
                              fontWeight: FontWeight.w900,
                              color: kRed,
                            ),
                          ),
                        ],
                      );
                    }
                    final m = math.exp(kRate * _time.value);
                    return Text(
                      '${m.toStringAsFixed(2)}x',
                      style: const TextStyle(
                        fontSize: 58,
                        fontWeight: FontWeight.w900,
                        color: kInk,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap) {
    return Tap(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: kLine),
        ),
        child: Icon(icon, color: kInk, size: 22),
      ),
    );
  }

  Widget _actionButton() {
    return AnimatedBuilder(
      animation: _time,
      builder: (context, _) {
        String label;
        Color color;
        VoidCallback onTap;
        if (_phase == Phase.flying && _activeBet > 0) {
          final m = math.exp(kRate * _time.value);
          label = 'CASH OUT  ₹${fmt(_activeBet * m)}';
          color = kRed;
          onTap = _cashOut;
        } else if (_pendingBet > 0) {
          label = 'CANCEL BET  ₹${fmt(_pendingBet)}';
          color = kGrey;
          onTap = _cancelBet;
        } else {
          label = _phase == Phase.waiting
              ? 'PLACE BET  ₹${_betAmount.toInt()}'
              : 'BET NEXT ROUND  ₹${_betAmount.toInt()}';
          color = kGreen;
          onTap = _placeBet;
        }
        return Tap(
          onTap: onTap,
          child: Container(
            height: 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _betPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: kLine)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _roundBtn(Icons.remove, () => _changeBet(-1)),
              const SizedBox(width: 10),
              Expanded(
                child: Tap(
                  onTap: _editBet,
                  child: Container(
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: kBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: kLine),
                    ),
                    child: Text(
                      '₹ ${_betAmount.toInt()}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: kInk,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _roundBtn(Icons.add, () => _changeBet(1)),
            ],
          ),
          const SizedBox(height: 12),
          _actionButton(),
        ],
      ),
    );
  }

  Widget _homeView() {
    return Column(
      children: [
        _topBar(),
        _historyStrip(),
        Expanded(child: _graph()),
        _betPanel(),
      ],
    );
  }

  Widget _walletView() {
    return Center(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.symmetric(vertical: 56),
        decoration: BoxDecoration(
          color: kBg,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: kLine),
        ),
        alignment: Alignment.center,
        child: Text(
          '₹ ${fmt(_balance)}',
          style: const TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.w900,
            color: kInk,
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData filled, IconData outlined) {
    final selected = _tab == index;
    return Tap(
      onTap: () => setState(() => _tab = index),
      child: SizedBox(
        width: 72,
        height: 60,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? filled : outlined, color: kInk, size: 28),
            const SizedBox(height: 4),
            Container(
              width: 18,
              height: 3,
              decoration: BoxDecoration(
                color: selected ? kInk : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: kLine)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _navItem(0, Icons.home_rounded, Icons.home_outlined),
          _navItem(
            1,
            Icons.account_balance_wallet_rounded,
            Icons.account_balance_wallet_outlined,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [_homeView(), _walletView()],
              ),
            ),
            _bottomBar(),
          ],
        ),
      ),
    );
  }
}

class GraphPainter extends CustomPainter {
  final ValueNotifier<double> time;
  final Phase phase;

  GraphPainter({required this.time, required this.phase})
      : super(repaint: time);

  static double _mult(double t) => math.exp(kRate * t);

  @override
  void paint(Canvas canvas, Size size) {
    const double padL = 18, padR = 24, padT = 24, padB = 22;
    final double w = size.width - padL - padR;
    final double h = size.height - padT - padB;
    if (w <= 0 || h <= 0) return;

    final gridPaint = Paint()
      ..color = kLine
      ..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final y = padT + h * i / 4;
      canvas.drawLine(Offset(padL, y), Offset(padL + w, y), gridPaint);
      final x = padL + w * i / 4;
      canvas.drawLine(Offset(x, padT), Offset(x, padT + h), gridPaint);
    }

    if (phase == Phase.waiting) return;

    final t = time.value;
    final m = _mult(t);
    final xMax = math.max(6.0, t * 1.2);
    final yMax = math.max(2.0, m * 1.25);

    Offset pt(double tt) {
      final x = padL + tt / xMax * w;
      final y = padT + h - (_mult(tt) - 1) / (yMax - 1) * h;
      return Offset(x, y);
    }

    const int n = 80;
    final start = pt(0);
    final path = Path()..moveTo(start.dx, start.dy);
    Offset last = start;
    Offset prev = start;
    for (int i = 1; i <= n; i++) {
      final p = pt(t * i / n);
      path.lineTo(p.dx, p.dy);
      prev = last;
      last = p;
    }

    final fill = Path.from(path)
      ..lineTo(last.dx, padT + h)
      ..lineTo(start.dx, padT + h)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [kRed.withAlpha(60), kRed.withAlpha(0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fill, fillPaint);

    final linePaint = Paint()
      ..color = kRed
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    if (phase == Phase.flying) {
      final angle = math.atan2(last.dy - prev.dy, last.dx - prev.dx);
      canvas.save();
      canvas.translate(last.dx, last.dy);
      canvas.rotate(angle);
      final plane = Path()
        ..moveTo(22, 0)
        ..lineTo(8, -4)
        ..lineTo(-2, -16)
        ..lineTo(-8, -16)
        ..lineTo(-4, -4)
        ..lineTo(-16, -3)
        ..lineTo(-20, -9)
        ..lineTo(-24, -9)
        ..lineTo(-22, 0)
        ..lineTo(-24, 9)
        ..lineTo(-20, 9)
        ..lineTo(-16, 3)
        ..lineTo(-4, 4)
        ..lineTo(-8, 16)
        ..lineTo(-2, 16)
        ..lineTo(8, 4)
        ..close();
      canvas.drawShadow(plane, Colors.black, 3, false);
      canvas.drawPath(plane, Paint()..color = kRed);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant GraphPainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.time != time;
  }
}
