import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const emotions = ['শান্ত', 'আত্মবিশ্বাসী', 'ভয়', 'লোভ', 'রাগ', 'অধৈর্য', 'FOMO'];
const monthNames = [
  'জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন',
  'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর'
];
const green = Color(0xFF22C55E);
const red = Color(0xFFEF4444);

String two(int n) => n.toString().padLeft(2, '0');
String fmt(DateTime d) => '${d.day}/${d.month}/${d.year} ${two(d.hour)}:${two(d.minute)}';
String dayKey(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
void snack(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

class Trade {
  String id;
  int time;
  String pair;
  String side;
  double pnl;
  String emotion;
  String note;
  bool followed;
  Trade({
    required this.id,
    required this.time,
    required this.pair,
    required this.side,
    required this.pnl,
    required this.emotion,
    required this.note,
    required this.followed,
  });
  Map<String, dynamic> toJson() => {
        'id': id,
        'time': time,
        'pair': pair,
        'side': side,
        'pnl': pnl,
        'emotion': emotion,
        'note': note,
        'followed': followed,
      };
  factory Trade.fromJson(Map<String, dynamic> j) => Trade(
        id: j['id'] as String,
        time: (j['time'] as num).toInt(),
        pair: j['pair'] as String,
        side: j['side'] as String,
        pnl: (j['pnl'] as num).toDouble(),
        emotion: j['emotion'] as String,
        note: j['note'] as String,
        followed: j['followed'] as bool,
      );
}

class Review {
  int time;
  String text;
  Review(this.time, this.text);
  Map<String, dynamic> toJson() => {'time': time, 'text': text};
  factory Review.fromJson(Map<String, dynamic> j) =>
      Review((j['time'] as num).toInt(), j['text'] as String);
}

class AppState extends ChangeNotifier {
  List<Trade> trades = [];
  List<Review> reviews = [];
  List<String> rules = [
    'স্টপ লস সেট করেছি',
    'রিস্ক ২% এর বেশি না',
    'সেটআপ আমার প্ল্যান অনুযায়ী',
    'মন শান্ত আছে',
  ];
  int maxTrades = 3;
  double maxLoss = 100;
  int lockMinutes = 30;
  int lockUntil = 0;
  bool dark = true;
  bool approved = false;
  SharedPreferences? prefs;

  bool get isLocked => DateTime.now().millisecondsSinceEpoch < lockUntil;

  Future<void> load() async {
    prefs = await SharedPreferences.getInstance();
    final s = prefs!.getString('data');
    if (s != null) {
      try {
        importJson(s);
      } catch (_) {}
    }
    notifyListeners();
  }

  Map<String, dynamic> toJson() => {
        'trades': trades.map((t) => t.toJson()).toList(),
        'reviews': reviews.map((r) => r.toJson()).toList(),
        'rules': rules,
        'maxTrades': maxTrades,
        'maxLoss': maxLoss,
        'lockMinutes': lockMinutes,
        'lockUntil': lockUntil,
        'dark': dark,
      };

  void importJson(String s) {
    final j = jsonDecode(s) as Map<String, dynamic>;
    trades = ((j['trades'] as List?) ?? [])
        .map((e) => Trade.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    reviews = ((j['reviews'] as List?) ?? [])
        .map((e) => Review.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    rules = List<String>.from((j['rules'] as List?) ?? rules);
    maxTrades = (j['maxTrades'] as num?)?.toInt() ?? 3;
    maxLoss = (j['maxLoss'] as num?)?.toDouble() ?? 100;
    lockMinutes = (j['lockMinutes'] as num?)?.toInt() ?? 30;
    lockUntil = (j['lockUntil'] as num?)?.toInt() ?? 0;
    dark = (j['dark'] as bool?) ?? true;
  }

  Future<void> _save() async {
    await prefs?.setString('data', jsonEncode(toJson()));
  }

  void change(VoidCallback f) {
    f();
    _save();
    notifyListeners();
  }

  List<Trade> tradesOn(DateTime d) => trades
      .where((t) => dayKey(DateTime.fromMillisecondsSinceEpoch(t.time)) == dayKey(d))
      .toList();

  double pnlOn(DateTime d) => tradesOn(d).fold<double>(0, (a, t) => a + t.pnl);

  int scoreOn(DateTime d) {
    final ts = tradesOn(d);
    if (ts.isEmpty) return 0;
    final f = ts.where((t) => t.followed).length;
    double s = f / ts.length * 100;
    if (ts.length > maxTrades) s -= 20 * (ts.length - maxTrades);
    if (pnlOn(d) < -maxLoss) s -= 20;
    return s.clamp(0, 100).round();
  }

  int streak() {
    int n = 0;
    final now = DateTime.now();
    for (int i = 0; i < 365; i++) {
      final day = DateTime(now.year, now.month, now.day - i);
      if (tradesOn(day).isEmpty) continue;
      if (scoreOn(day) >= 80) {
        n++;
      } else {
        break;
      }
    }
    return n;
  }

  int overallScore() {
    final days = <String, DateTime>{};
    for (final t in trades) {
      final d = DateTime.fromMillisecondsSinceEpoch(t.time);
      days[dayKey(d)] = DateTime(d.year, d.month, d.day);
    }
    if (days.isEmpty) return 0;
    final scores = days.values.map((d) => scoreOn(d)).toList();
    return (scores.reduce((a, b) => a + b) / scores.length).round();
  }

  void addTrade(Trade t) {
    change(() {
      trades.add(t);
      trades.sort((a, b) => b.time.compareTo(a.time));
      approved = false;
      if (trades.length >= 2 && trades[0].pnl < 0 && trades[1].pnl < 0) {
        lockUntil = DateTime.now().millisecondsSinceEpoch + lockMinutes * 60000;
      }
    });
  }
}

final app = AppState();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  app.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (c, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Trade Discipline',
        themeMode: app.dark ? ThemeMode.dark : ThemeMode.light,
        theme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: Colors.teal,
            brightness: Brightness.light),
        darkTheme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: Colors.teal,
            brightness: Brightness.dark),
        home: const Shell(),
      ),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int i = 0;
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (c, _) => Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: i,
            children: [
              HomePage(),
              JournalPage(),
              StatsPage(),
              CalcPage(),
              MorePage(),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: i,
          onDestinationSelected: (v) => setState(() => i = v),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), label: 'হোম'),
            NavigationDestination(icon: Icon(Icons.menu_book_outlined), label: 'জার্নাল'),
            NavigationDestination(icon: Icon(Icons.bar_chart), label: 'স্ট্যাটস'),
            NavigationDestination(icon: Icon(Icons.calculate_outlined), label: 'ক্যালকু'),
            NavigationDestination(icon: Icon(Icons.more_horiz), label: 'আরও'),
          ],
        ),
      ),
    );
  }
}

Widget statCard(BuildContext c, String title, String value, {Color? color}) {
  return Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontSize: 12, color: Theme.of(c).hintColor)),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    ),
  );
}

Widget banner(String text, Color color) {
  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withAlpha(50),
      border: Border.all(color: color),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
  );
}

// ---------------- হোম ----------------
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomeState();
}

class _HomeState extends State<HomePage> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && app.lockUntil != 0) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todays = app.tradesOn(now);
    final pnl = app.pnlOn(now);
    final locked = app.isLocked;
    final limitHit = todays.length >= app.maxTrades || pnl <= -app.maxLoss;
    final remain = Duration(
        milliseconds: math.max(0, app.lockUntil - now.millisecondsSinceEpoch));
    final mmss =
        '${two(remain.inMinutes)}:${two(remain.inSeconds % 60)}';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('আজকের ডিসিপ্লিন', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        if (locked) banner('লক চালু! শান্ত হও। বাকি $mmss', red),
        if (!locked && limitHit) banner('আজকের লিমিট শেষ। আজ আর ট্রেড নয়।', Colors.orange),
        Row(children: [
          statCard(context, 'আজকের ট্রেড', '${todays.length}/${app.maxTrades}'),
          statCard(context, 'আজকের P&L', pnl.toStringAsFixed(2),
              color: pnl >= 0 ? green : red),
        ]),
        Row(children: [
          statCard(context, 'ডিসিপ্লিন স্কোর',
              todays.isEmpty ? '--' : '${app.scoreOn(now)}'),
          statCard(context, 'স্ট্রিক', '${app.streak()} দিন'),
        ]),
        if (pnl < 0) ...[
          const SizedBox(height: 4),
          Text('লস লিমিট: ${pnl.abs().toStringAsFixed(0)} / ${app.maxLoss.toStringAsFixed(0)}'),
          const SizedBox(height: 6),
          LinearProgressIndicator(
              value: (-pnl / app.maxLoss).clamp(0.0, 1.0).toDouble(), color: red),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: (locked || limitHit) ? null : () => showChecklist(context),
          icon: Icon(app.approved ? Icons.check_circle : Icons.checklist),
          label: Text(app.approved ? 'চেকলিস্ট পাস ✓' : 'ট্রেডের আগে চেকলিস্ট'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => showTradeForm(context),
          icon: const Icon(Icons.edit_note),
          label: const Text('ট্রেড লগ করো'),
        ),
      ],
    );
  }
}

void showChecklist(BuildContext context) {
  if (app.rules.isEmpty) {
    snack(context, 'আগে "আরও" ট্যাবে নিয়ম যোগ করো');
    return;
  }
  final checked = List<bool>.filled(app.rules.length, false);
  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final all = checked.every((e) => e);
      return AlertDialog(
        title: const Text('ট্রেডের আগে চেকলিস্ট'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < app.rules.length; i++)
                CheckboxListTile(
                  value: checked[i],
                  onChanged: (v) => setS(() => checked[i] = v ?? false),
                  title: Text(app.rules[i]),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('বাতিল')),
          FilledButton(
            onPressed: all
                ? () {
                    app.change(() => app.approved = true);
                    Navigator.pop(ctx);
                  }
                : null,
            child: const Text('ট্রেড নিন'),
          ),
        ],
      );
    }),
  );
}

void showTradeForm(BuildContext context) {
  final pair = TextEditingController(text: 'XAUUSD');
  final pnl = TextEditingController();
  final note = TextEditingController();
  String side = 'Buy';
  String emotion = 'শান্ত';
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ট্রেড লগ', style: Theme.of(ctx).textTheme.titleLarge),
              if (!app.approved)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'চেকলিস্ট ছাড়া নিয়েছ, তাই এটা "নিয়ম ভাঙা" ধরা হবে।',
                    style: TextStyle(color: Colors.orange),
                  ),
                ),
              TextField(
                controller: pair,
                decoration: const InputDecoration(labelText: 'পেয়ার (যেমন XAUUSD)'),
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'Buy', label: Text('Buy')),
                  ButtonSegment(value: 'Sell', label: Text('Sell')),
                ],
                selected: {side},
                onSelectionChanged: (s) => setS(() => side = s.first),
              ),
              TextField(
                controller: pnl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(
                    labelText: 'লাভ/লস (লস হলে - দিয়ে, যেমন -25)'),
              ),
              const SizedBox(height: 10),
              const Text('ট্রেডের সময় মন কেমন ছিল?'),
              Wrap(
                spacing: 8,
                children: [
                  for (final e in emotions)
                    ChoiceChip(
                      label: Text(e),
                      selected: emotion == e,
                      onSelected: (_) => setS(() => emotion = e),
                    ),
                ],
              ),
              TextField(
                controller: note,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'নোট'),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    final v = double.tryParse(pnl.text.trim());
                    if (v == null) {
                      snack(ctx, 'লাভ/লস সংখ্যায় লেখো');
                      return;
                    }
                    app.addTrade(Trade(
                      id: DateTime.now().microsecondsSinceEpoch.toString(),
                      time: DateTime.now().millisecondsSinceEpoch,
                      pair: pair.text.trim().isEmpty ? 'XAUUSD' : pair.text.trim(),
                      side: side,
                      pnl: v,
                      emotion: emotion,
                      note: note.text.trim(),
                      followed: app.approved,
                    ));
                    Navigator.pop(ctx);
                  },
                  child: const Text('সেভ'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ---------------- জার্নাল ----------------
class JournalPage extends StatelessWidget {
  const JournalPage({super.key});
  @override
  Widget build(BuildContext context) {
    final ts = app.trades;
    if (ts.isEmpty) return const Center(child: Text('এখনও কোনো ট্রেড লগ নেই'));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: ts.length,
      itemBuilder: (c, i) {
        final t = ts[i];
        final d = DateTime.fromMillisecondsSinceEpoch(t.time);
        final rule = t.followed ? 'নিয়ম মেনেছি ✓' : 'চেকলিস্ট ছাড়া ✗';
        return Card(
          child: ListTile(
            leading: Icon(
              t.side == 'Buy' ? Icons.trending_up : Icons.trending_down,
              color: t.pnl >= 0 ? green : red,
            ),
            title: Text('${t.pair}   ${t.pnl >= 0 ? '+' : ''}${t.pnl.toStringAsFixed(2)}'),
            subtitle: Text(
                '${fmt(d)} • ${t.emotion} • $rule${t.note.isEmpty ? '' : '\n${t.note}'}'),
            isThreeLine: t.note.isNotEmpty,
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => confirmDelete(c, t.id),
            ),
          ),
        );
      },
    );
  }
}

void confirmDelete(BuildContext context, String id) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('মুছে ফেলবে?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('না')),
        FilledButton(
          onPressed: () {
            app.change(() => app.trades.removeWhere((t) => t.id == id));
            Navigator.pop(ctx);
          },
          child: const Text('হ্যাঁ'),
        ),
      ],
    ),
  );
}

// ---------------- স্ট্যাটস ----------------
class EquityPainter extends CustomPainter {
  final List<double> pts;
  final Color color;
  final Color zero;
  EquityPainter(this.pts, this.color, this.zero);
  @override
  void paint(Canvas canvas, Size size) {
    if (pts.length < 2) return;
    double mn = 0, mx = 0;
    for (final v in pts) {
      mn = math.min(mn, v);
      mx = math.max(mx, v);
    }
    if (mx == mn) mx = mn + 1;
    double y(double v) => size.height - (v - mn) / (mx - mn) * size.height;
    canvas.drawLine(Offset(0, y(0)), Offset(size.width, y(0)),
        Paint()..color = zero..strokeWidth = 1);
    final path = Path();
    for (int i = 0; i < pts.length; i++) {
      final x = i / (pts.length - 1) * size.width;
      if (i == 0) {
        path.moveTo(x, y(pts[i]));
      } else {
        path.lineTo(x, y(pts[i]));
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(covariant EquityPainter old) => true;
}

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final ts = app.trades;
    final wins = ts.where((t) => t.pnl > 0).toList();
    final losses = ts.where((t) => t.pnl < 0).toList();
    final total = ts.fold<double>(0, (a, t) => a + t.pnl);
    final grossW = wins.fold<double>(0, (a, t) => a + t.pnl);
    final grossL = -losses.fold<double>(0, (a, t) => a + t.pnl);
    final winRate = ts.isEmpty ? 0.0 : wins.length / ts.length * 100;
    final avgW = wins.isEmpty ? 0.0 : grossW / wins.length;
    final avgL = losses.isEmpty ? 0.0 : grossL / losses.length;
    final rr = avgL == 0 ? 0.0 : avgW / avgL;
    final pf = grossL == 0 ? (grossW > 0 ? double.infinity : 0.0) : grossW / grossL;

    final eq = <double>[0];
    double run = 0;
    for (final t in ts.reversed) {
      run += t.pnl;
      eq.add(run);
    }

    final em = <String, List<double>>{};
    for (final t in ts) {
      final l = em.putIfAbsent(t.emotion, () => [0.0, 0.0]);
      l[0] += 1;
      l[1] += t.pnl;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('অ্যানালিটিক্স', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Row(children: [
          statCard(context, 'মোট P&L', total.toStringAsFixed(2),
              color: total >= 0 ? green : red),
          statCard(context, 'উইন রেট', '${winRate.toStringAsFixed(0)}%'),
        ]),
        Row(children: [
          statCard(context, 'প্রফিট ফ্যাক্টর', pf.isInfinite ? '∞' : pf.toStringAsFixed(2)),
          statCard(context, 'গড় রিস্ক:রিওয়ার্ড', '1:${rr.toStringAsFixed(2)}'),
        ]),
        Row(children: [
          statCard(context, 'গড় লাভ', avgW.toStringAsFixed(2), color: green),
          statCard(context, 'গড় লস', avgL.toStringAsFixed(2), color: red),
        ]),
        Row(children: [
          statCard(context, 'ডিসিপ্লিন স্কোর', '${app.overallScore()}'),
          statCard(context, 'মোট ট্রেড', '${ts.length}'),
        ]),
        const SizedBox(height: 8),
        Text('ইকুইটি কার্ভ', style: Theme.of(context).textTheme.titleMedium),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ts.isEmpty
                ? const Text('ট্রেড লগ করলে কার্ভ আসবে')
                : SizedBox(
                    height: 160,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: EquityPainter(eq, Colors.teal, Theme.of(context).hintColor),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text('ক্যালেন্ডার', style: Theme.of(context).textTheme.titleMedium),
        const CalendarCard(),
        const SizedBox(height: 8),
        Text('ইমোশন অনুযায়ী ফলাফল', style: Theme.of(context).textTheme.titleMedium),
        Card(
          child: Column(
            children: [
              if (em.isEmpty)
                const Padding(padding: EdgeInsets.all(14), child: Text('এখনও ডেটা নেই')),
              for (final e in em.entries)
                ListTile(
                  dense: true,
                  title: Text(e.key),
                  subtitle: Text('${e.value[0].toInt()} টা ট্রেড'),
                  trailing: Text(
                    e.value[1].toStringAsFixed(2),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: e.value[1] >= 0 ? green : red),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class CalendarCard extends StatefulWidget {
  const CalendarCard({super.key});
  @override
  State<CalendarCard> createState() => _CalState();
}

class _CalState extends State<CalendarCard> {
  DateTime m = DateTime(DateTime.now().year, DateTime.now().month);
  @override
  Widget build(BuildContext context) {
    final first = DateTime(m.year, m.month, 1);
    final offset = first.weekday % 7;
    final days = DateTime(m.year, m.month + 1, 0).day;
    final cells = <Widget>[];
    for (int i = 0; i < offset; i++) {
      cells.add(const SizedBox());
    }
    for (int d = 1; d <= days; d++) {
      final day = DateTime(m.year, m.month, d);
      final has = app.tradesOn(day).isNotEmpty;
      final p = app.pnlOn(day);
      cells.add(Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: !has
              ? null
              : (p >= 0 ? const Color(0x5522C55E) : const Color(0x55EF4444)),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$d', style: const TextStyle(fontSize: 12)),
            if (has) Text(p.toStringAsFixed(0), style: const TextStyle(fontSize: 9)),
          ],
        ),
      ));
    }
    const heads = ['র', 'সো', 'ম', 'বু', 'বৃ', 'শু', 'শ'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => setState(() => m = DateTime(m.year, m.month - 1)),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('${monthNames[m.month - 1]} ${m.year}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  onPressed: () => setState(() => m = DateTime(m.year, m.month + 1)),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Row(
              children: [
                for (final h in heads)
                  Expanded(
                    child: Center(child: Text(h, style: const TextStyle(fontSize: 12))),
                  ),
              ],
            ),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: cells,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- ক্যালকুলেটর ----------------
class CalcPage extends StatefulWidget {
  const CalcPage({super.key});
  @override
  State<CalcPage> createState() => _CalcState();
}

class _CalcState extends State<CalcPage> {
  final bal = TextEditingController(text: '1000');
  final risk = TextEditingController(text: '1');
  final sl = TextEditingController(text: '20');
  final tp = TextEditingController(text: '40');
  final pv = TextEditingController(text: '10');
  final pips = TextEditingController(text: '30');
  final lots = TextEditingController(text: '0.10');

  double n(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  Widget f(String label, TextEditingController c) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      );

  Widget r(String label, String value, {Color? color}) => ListTile(
        dense: true,
        title: Text(label),
        trailing: Text(value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
      );

  @override
  Widget build(BuildContext context) {
    final riskAmt = n(bal) * n(risk) / 100;
    final lot = (n(sl) > 0 && n(pv) > 0) ? riskAmt / (n(sl) * n(pv)) : 0.0;
    final profit = n(tp) * n(pv) * lot;
    final rr = n(sl) > 0 ? n(tp) / n(sl) : 0.0;
    final pl = n(pips) * n(pv) * n(lots);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('লট সাইজ ক্যালকুলেটর', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        f('ব্যালেন্স', bal),
        f('রিস্ক %', risk),
        f('স্টপ লস (পিপস)', sl),
        f('টেক প্রফিট (পিপস)', tp),
        f('১ লটে প্রতি পিপের মান (ফরেক্সে সাধারণত ১০)', pv),
        Card(
          child: Column(
            children: [
              r('রিস্ক অ্যামাউন্ট', riskAmt.toStringAsFixed(2)),
              r('লট সাইজ', lot.toStringAsFixed(2)),
              r('সম্ভাব্য প্রফিট', profit.toStringAsFixed(2), color: green),
              r('রিস্ক:রিওয়ার্ড', '1:${rr.toStringAsFixed(2)}'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('প্রফিট/লস হিসাব', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        f('পিপস (লস হলে -)', pips),
        f('লট', lots),
        Card(
          child: r('ফলাফল', pl.toStringAsFixed(2), color: pl >= 0 ? green : red),
        ),
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'পিপের মান ব্রোকার ও পেয়ার ভেদে আলাদা। নিশ্চিত হতে ব্রোকারের কন্ট্রাক্ট স্পেক দেখো।',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

// ---------------- আরও ----------------
void push(BuildContext c, Widget w) =>
    Navigator.push(c, MaterialPageRoute(builder: (_) => w));

class MorePage extends StatelessWidget {
  const MorePage({super.key});
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.dark_mode_outlined),
          title: const Text('ডার্ক মোড'),
          value: app.dark,
          onChanged: (v) => app.change(() => app.dark = v),
        ),
        ListTile(
          leading: const Icon(Icons.rule),
          title: const Text('আমার নিয়ম (চেকলিস্ট)'),
          onTap: () => push(context, const RulesPage()),
        ),
        ListTile(
          leading: const Icon(Icons.speed),
          title: const Text('লিমিট ও লক সেটিং'),
          onTap: () => push(context, const SettingsPage()),
        ),
        ListTile(
          leading: const Icon(Icons.rate_review_outlined),
          title: const Text('সাপ্তাহিক রিভিউ'),
          onTap: () => push(context, const ReviewPage()),
        ),
        ListTile(
          leading: const Icon(Icons.backup_outlined),
          title: const Text('ব্যাকআপ ও রিস্টোর'),
          onTap: () => push(context, const BackupPage()),
        ),
      ],
    );
  }
}

class RulesPage extends StatelessWidget {
  const RulesPage({super.key});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (c, _) => Scaffold(
        appBar: AppBar(title: const Text('আমার নিয়ম')),
        floatingActionButton: FloatingActionButton(
          onPressed: () => addRule(c),
          child: const Icon(Icons.add),
        ),
        body: ListView(
          children: [
            for (int i = 0; i < app.rules.length; i++)
              ListTile(
                title: Text(app.rules[i]),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => app.change(() => app.rules.removeAt(i)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

void addRule(BuildContext context) {
  final c = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('নতুন নিয়ম'),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'যেমন: দিনে সর্বোচ্চ ৩টা ট্রেড'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('বাতিল')),
        FilledButton(
          onPressed: () {
            final s = c.text.trim();
            if (s.isNotEmpty) app.change(() => app.rules.add(s));
            Navigator.pop(ctx);
          },
          child: const Text('যোগ'),
        ),
      ],
    ),
  );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SetState();
}

class _SetState extends State<SettingsPage> {
  final a = TextEditingController(text: app.maxTrades.toString());
  final b = TextEditingController(text: app.maxLoss.toString());
  final c = TextEditingController(text: app.lockMinutes.toString());

  Widget field(String label, TextEditingController ctl) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: ctl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('লিমিট ও লক')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          field('দিনে সর্বোচ্চ ট্রেড', a),
          field('দিনে সর্বোচ্চ লস (সংখ্যায়)', b),
          field('পরপর ২ লসের পর লক (মিনিট)', c),
          FilledButton(
            onPressed: () {
              app.change(() {
                app.maxTrades = int.tryParse(a.text.trim()) ?? app.maxTrades;
                app.maxLoss = double.tryParse(b.text.trim()) ?? app.maxLoss;
                app.lockMinutes = int.tryParse(c.text.trim()) ?? app.lockMinutes;
              });
              Navigator.pop(context);
            },
            child: const Text('সেভ'),
          ),
        ],
      ),
    );
  }
}

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});
  @override
  State<ReviewPage> createState() => _RevState();
}

class _RevState extends State<ReviewPage> {
  final ctl = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (c, _) => Scaffold(
        appBar: AppBar(title: const Text('সাপ্তাহিক রিভিউ')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: ctl,
              maxLines: 6,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'এই সপ্তাহে কোন নিয়ম ভেঙেছি? কেন? পরের সপ্তাহে কী বদলাব?',
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () {
                final s = ctl.text.trim();
                if (s.isEmpty) return;
                app.change(() => app.reviews
                    .insert(0, Review(DateTime.now().millisecondsSinceEpoch, s)));
                ctl.clear();
              },
              child: const Text('রিভিউ সেভ'),
            ),
            const Divider(height: 30),
            for (final r in app.reviews)
              Card(
                child: ListTile(
                  title: Text(fmt(DateTime.fromMillisecondsSinceEpoch(r.time))),
                  subtitle: Text(r.text),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});
  @override
  State<BackupPage> createState() => _BackupState();
}

class _BackupState extends State<BackupPage> {
  final ctl = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ব্যাকআপ ও রিস্টোর')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('ব্যাকআপ: নিচের বাটনে চাপলে সব ডেটা কপি হবে। সেটা কোথাও (নোট বা মেসেজে) সেভ করে রাখো।'),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: jsonEncode(app.toJson())));
              if (context.mounted) snack(context, 'কপি হয়েছে');
            },
            icon: const Icon(Icons.copy),
            label: const Text('ডেটা কপি করো'),
          ),
          const Divider(height: 36),
          const Text('রিস্টোর: সেভ করা লেখাটা এখানে পেস্ট করো।'),
          const SizedBox(height: 10),
          TextField(
            controller: ctl,
            maxLines: 5,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () {
              try {
                app.change(() => app.importJson(ctl.text.trim()));
                snack(context, 'রিস্টোর হয়েছে');
              } catch (e) {
                snack(context, 'লেখাটা ঠিক নেই');
              }
            },
            child: const Text('রিস্টোর করো'),
          ),
        ],
      ),
    );
  }
}
