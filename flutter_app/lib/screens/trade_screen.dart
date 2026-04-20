import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../api/coingecko.dart';
import '../models/models.dart';
import '../store/app_state.dart';
import '../theme/theme.dart';

class TradeScreen extends StatefulWidget {
  final String coinId;
  final String symbol;
  final String name;
  const TradeScreen({super.key, required this.coinId, required this.symbol, required this.name});

  @override
  State<TradeScreen> createState() => _TradeScreenState();
}

class _TradeScreenState extends State<TradeScreen> {
  Side _side = Side.buy;
  final _ctrl = TextEditingController();

  // chart state
  static const _ranges = <({String label, Object days})>[
    (label: '1D',  days: '1d'),
    (label: '7D',  days: '7d'),
    (label: '30D', days: '30d'),
    (label: '90D', days: '90d'),
    (label: '1Y',  days: '1y'),
    (label: 'MAX', days: 'max'),
  ];
  int _rangeIdx = 1;
  List<(DateTime, double)> _history = [];
  bool _chartLoading = false;
  String? _chartErr;

  @override
  void initState() {
    super.initState();
    _loadChart();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadChart() async {
    setState(() { _chartLoading = true; _chartErr = null; });
    try {
      final h = await fetchHistory(widget.coinId, _ranges[_rangeIdx].days);
      if (!mounted) return;
      setState(() => _history = h);
    } catch (e) {
      if (!mounted) return;
      setState(() => _chartErr = e.toString());
    } finally {
      if (mounted) setState(() => _chartLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final price = s.priceOf(widget.coinId);
    final a = s.account!;
    final owned = s.availableToSell(widget.coinId); // excludes pending sells
    final availCash = s.availableCash();             // excludes pending buys

    final usd = NumberFormat.currency(locale: 'en_US', symbol: '\$');
    final priceFmt = NumberFormat.currency(
        locale: 'en_US', symbol: '\$', decimalDigits: price > 10 ? 2 : 6);

    final inputUsd = double.tryParse(_ctrl.text) ?? 0;
    final coinAmount = (price > 0) ? inputUsd / price : 0;

    final basis = _side == Side.buy ? availCash : owned * price;
    final pcts = _side == Side.buy
        ? const [0.1, 0.25, 0.5, 1.0]
        : const [0.25, 0.5, 0.75, 1.0];

    return Scaffold(
      appBar: AppBar(title: Text(widget.symbol)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(widget.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('${widget.symbol} · ${priceFmt.format(price)}',
                style: const TextStyle(color: AppColors.dim)),
            const SizedBox(height: 14),
            _chartCard(),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  _sideBtn(Side.buy,  'BUY',  AppColors.green),
                  _sideBtn(Side.sell, 'SELL', AppColors.red),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _kvRow('Cash', usd.format(availCash)),
            _kvRow('Holding', '${owned.toStringAsFixed(6)} ${widget.symbol}'),
            if (s.pendingSellAmount(widget.coinId) > 0 ||
                s.pendingBuyCost() > 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('Some funds are reserved by pending orders.',
                    style: TextStyle(color: AppColors.dim, fontSize: 12)),
              ),
            const SizedBox(height: 16),
            const Text('Amount (USD)', style: TextStyle(color: AppColors.dim)),
            const SizedBox(height: 6),
            TextField(
              controller: _ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(
                hintText: '0.00',
                hintStyle: TextStyle(color: AppColors.dim),
                filled: true,
                fillColor: AppColors.card,
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.accent)),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final p in pcts)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: AppColors.cardAlt,
                          side: BorderSide.none,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () {
                          setState(() {
                            _ctrl.text = (basis * p).toStringAsFixed(2);
                          });
                        },
                        child: Text('${(p * 100).round()}%',
                            style: const TextStyle(
                                color: AppColors.text, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('≈ ${coinAmount.toStringAsFixed(6)} ${widget.symbol}',
                style: const TextStyle(color: AppColors.dim)),
            Text('Fee (${(kFeeRate * 100).toStringAsFixed(1)}%): ${usd.format(inputUsd * kFeeRate)}',
                style: const TextStyle(color: AppColors.dim, fontSize: 12)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _side == Side.buy ? AppColors.green : AppColors.red,
                  foregroundColor: AppColors.bg,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () => _submit(context, price, owned),
                child: Text('${_side == Side.buy ? 'Buy' : 'Sell'} ${widget.symbol}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Orders take a random 1–5s to fill, just like a real exchange.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.dim, fontSize: 12),
            ),
            const SizedBox(height: 24),
            _limitsSection(context, s, price, owned, availCash),
          ],
        ),
      ),
    );
  }

  Widget _limitsSection(BuildContext context, AppState s, double price, double owned, double cash) {
    final limits = s.limitsFor(widget.coinId);
    final priceFmt = NumberFormat.currency(
        locale: 'en_US', symbol: '\$', decimalDigits: price > 10 ? 2 : 6);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Reservations & triggers',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'Auto buy/sell when the price hits your target.',
            style: TextStyle(color: AppColors.dim, fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (limits.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('No triggers set.',
                  style: TextStyle(color: AppColors.dim, fontSize: 13)),
            )
          else
            ...limits.map((l) {
              final isBuy = l.side == Side.buy;
              final label = isBuy
                  ? 'BUY'
                  : l.kind == LimitKind.stop
                      ? 'STOP'
                      : 'TAKE';
              final color = isBuy ? AppColors.accent : (l.kind == LimitKind.stop ? AppColors.red : AppColors.green);
              return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(label,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '@ ${priceFmt.format(l.triggerPrice)} · ${l.amount.toStringAsFixed(6)} ${widget.symbol}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18, color: AppColors.dim),
                        onPressed: () => s.removeLimit(l.id),
                      ),
                    ],
                  ),
              );
            }),
          const SizedBox(height: 8),
          Row(
            children: [
              if (owned > 0) ...[
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: AppColors.cardAlt,
                      side: BorderSide.none,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _openLimitDialog(LimitKind.stop, price, owned),
                    child: const Text('Stop-loss',
                        style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w600, fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: AppColors.cardAlt,
                      side: BorderSide.none,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _openLimitDialog(LimitKind.take, price, owned),
                    child: const Text('Take-profit',
                        style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w600, fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: AppColors.cardAlt,
                    side: BorderSide.none,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => _openBuyReservationDialog(price, cash),
                  child: const Text('Buy at price',
                      style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600, fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openLimitDialog(LimitKind kind, double price, double owned) async {
    final defaultPrice = kind == LimitKind.stop ? price * 0.9 : price * 1.1;
    final priceCtrl = TextEditingController(
        text: defaultPrice.toStringAsFixed(defaultPrice > 10 ? 2 : 6));
    final amtCtrl = TextEditingController(text: owned.toStringAsFixed(6));
    final s = context.read<AppState>();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: Text(
            kind == LimitKind.stop ? 'Set stop-loss' : 'Set take-profit',
            style: const TextStyle(color: AppColors.text),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                kind == LimitKind.stop
                    ? 'Auto-sell if ${widget.symbol} drops to this price.'
                    : 'Auto-sell if ${widget.symbol} rises to this price.',
                style: const TextStyle(color: AppColors.dim, fontSize: 12),
              ),
              const SizedBox(height: 12),
              const Text('Trigger price (USD)',
                  style: TextStyle(color: AppColors.dim, fontSize: 12)),
              TextField(
                controller: priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppColors.text),
              ),
              const SizedBox(height: 12),
              Text('Amount (${widget.symbol}) — max ${owned.toStringAsFixed(6)}',
                  style: const TextStyle(color: AppColors.dim, fontSize: 12)),
              TextField(
                controller: amtCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppColors.text),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppColors.dim)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor:
                    kind == LimitKind.stop ? AppColors.red : AppColors.green,
                foregroundColor: AppColors.bg,
              ),
              onPressed: () {
                final tp = double.tryParse(priceCtrl.text) ?? 0;
                var amt = double.tryParse(amtCtrl.text) ?? 0;
                if (tp <= 0) { _snack('Invalid price'); return; }
                if (amt <= 0) { _snack('Invalid amount'); return; }
                if (amt > owned && amt < owned * 1.001) amt = owned;
                if (amt > owned) { _snack('Amount exceeds holding'); return; }
                if (kind == LimitKind.stop && tp >= price) {
                  _snack('Stop-loss must be below current price'); return;
                }
                if (kind == LimitKind.take && tp <= price) {
                  _snack('Take-profit must be above current price'); return;
                }
                s.addLimit(
                  coinId: widget.coinId,
                  symbol: widget.symbol,
                  kind: kind,
                  triggerPrice: tp,
                  amount: amt,
                );
                Navigator.pop(ctx);
              },
              child: const Text('Set'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openBuyReservationDialog(double price, double cash) async {
    final priceCtrl = TextEditingController(
        text: (price * 0.9).toStringAsFixed(price > 10 ? 2 : 6));
    final amtCtrl = TextEditingController(text: '0');
    String dir = 'below'; // 'below' = buy when dips, 'above' = buy on breakout
    final s = context.read<AppState>();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDlgState) {
          return AlertDialog(
            backgroundColor: AppColors.card,
            title: const Text('Buy at price',
                style: TextStyle(color: AppColors.text)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Auto-buy when price hits target.',
                    style: TextStyle(color: AppColors.dim, fontSize: 12)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setDlgState(() => dir = 'below'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: dir == 'below' ? AppColors.accent : AppColors.cardAlt,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Text('Buy on dip',
                              style: TextStyle(
                                color: dir == 'below' ? AppColors.bg : AppColors.text,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              )),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () => setDlgState(() => dir = 'above'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: dir == 'above' ? AppColors.accent : AppColors.cardAlt,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Text('Buy on breakout',
                              style: TextStyle(
                                color: dir == 'above' ? AppColors.bg : AppColors.text,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              )),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Target price (USD)',
                    style: TextStyle(color: AppColors.dim, fontSize: 12)),
                TextField(
                  controller: priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: AppColors.text),
                ),
                const SizedBox(height: 12),
                Text('Amount (${widget.symbol}) to buy',
                    style: const TextStyle(color: AppColors.dim, fontSize: 12)),
                TextField(
                  controller: amtCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: AppColors.text),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: AppColors.dim)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.bg,
                ),
                onPressed: () {
                  final tp = double.tryParse(priceCtrl.text) ?? 0;
                  final amt = double.tryParse(amtCtrl.text) ?? 0;
                  if (tp <= 0) { _snack('Invalid price'); return; }
                  if (amt <= 0) { _snack('Invalid amount'); return; }
                  final cost = amt * tp;
                  if (cost > cash * 1.01) { _snack('Not enough cash'); return; }
                  s.addLimit(
                    coinId: widget.coinId,
                    symbol: widget.symbol,
                    kind: dir == 'below' ? LimitKind.stop : LimitKind.take,
                    triggerPrice: tp,
                    amount: amt,
                    side: Side.buy,
                    direction: dir == 'below' ? ReservationDir.below : ReservationDir.above,
                  );
                  Navigator.pop(ctx);
                },
                child: const Text('Set'),
              ),
            ],
          );
        });
      },
    );
  }

  Widget _chartCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 190,
            child: _buildChart(),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (int i = 0; i < _ranges.length; i++)
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    backgroundColor: _rangeIdx == i ? AppColors.cardAlt : null,
                  ),
                  onPressed: () {
                    setState(() => _rangeIdx = i);
                    _loadChart();
                  },
                  child: Text(
                    _ranges[i].label,
                    style: TextStyle(
                      color: _rangeIdx == i ? AppColors.accent : AppColors.dim,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    if (_chartLoading && _history.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_chartErr != null && _history.isEmpty) {
      return Center(
        child: Text(_chartErr!, style: const TextStyle(color: AppColors.red, fontSize: 12)),
      );
    }
    if (_history.isEmpty) {
      return const Center(
        child: Text('No data', style: TextStyle(color: AppColors.dim)),
      );
    }
    final spots = <FlSpot>[
      for (int i = 0; i < _history.length; i++)
        FlSpot(i.toDouble(), _history[i].$2),
    ];
    final first = _history.first.$2;
    final last = _history.last.$2;
    final up = last >= first;
    final color = up ? AppColors.green : AppColors.red;
    double minY = _history.first.$2;
    double maxY = minY;
    for (final h in _history) {
      if (h.$2 < minY) minY = h.$2;
      if (h.$2 > maxY) maxY = h.$2;
    }
    final pad = (maxY - minY) * 0.08;
    if (pad == 0) {
      minY = minY * 0.99;
      maxY = maxY * 1.01;
    } else {
      minY -= pad;
      maxY += pad;
    }

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.cardAlt,
            getTooltipItems: (touched) => touched.map((t) {
              final ts = _history[t.x.toInt()].$1;
              final p = _history[t.x.toInt()].$2;
              final d = DateFormat.MMMd().add_Hm().format(ts);
              final pf = NumberFormat.currency(
                  locale: 'en_US',
                  symbol: '\$',
                  decimalDigits: p > 10 ? 2 : 6).format(p);
              return LineTooltipItem(
                '$pf\n$d',
                const TextStyle(color: AppColors.text, fontSize: 11),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: color,
            barWidth: 1.8,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: color.withOpacity(0.12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sideBtn(Side s, String label, Color col) {
    final active = _side == s;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _side = s),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: active ? col : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  color: active ? AppColors.bg : AppColors.text,
                  fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Widget _kvRow(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(color: AppColors.dim)),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );

  void _submit(BuildContext context, double price, double owned) {
    var u = double.tryParse(_ctrl.text) ?? 0;
    if (u <= 0) { _snack('Enter an amount'); return; }
    if (price <= 0) { _snack('No live price yet — try again in a moment'); return; }

    final s = context.read<AppState>();
    final cash = s.availableCash();

    double coinAmt;
    if (_side == Side.buy) {
      // Budget includes the fee — clip the order so it always fits.
      if (u > cash * 1.01) { _snack('Not enough cash'); return; }
      if (u > cash) u = cash;
      // Reserve room for the fee so the fill won't be capped or fail.
      final spendable = u / (1 + kFeeRate);
      coinAmt = spendable / price;
    } else {
      coinAmt = u / price;
      // If 100% button rounded up by a cent, sell the exact holding instead.
      if (coinAmt > owned && coinAmt < owned * 1.001) coinAmt = owned;
      if (coinAmt > owned) { _snack('Not enough ${widget.symbol}'); return; }
    }

    s.placeOrder(
      coinId: widget.coinId,
      symbol: widget.symbol,
      side: _side,
      amount: coinAmt,
      pricePerUnitUsd: price,
    );
    _ctrl.clear();
    Navigator.of(context).pop();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
