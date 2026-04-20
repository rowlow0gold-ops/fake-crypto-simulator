import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../api/coingecko.dart';
import '../store/app_state.dart';
import '../theme/theme.dart';
import 'trade_screen.dart';

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});
  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

enum _SortKey { volume, change, volatility, price, symbol }
enum _Filter { all, favorites, gainers, losers, holdings }

class _MarketScreenState extends State<MarketScreen> {
  bool _loading = false;
  String? _err;
  String _query = '';
  final _searchCtrl = TextEditingController();

  _SortKey _sort = _SortKey.volume;
  bool _sortDesc = true;
  _Filter _filter = _Filter.all;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _snapshot();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  Widget _filterChip(String label, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.accent : AppColors.card,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? AppColors.bg : AppColors.text,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _sortChip(String label, _SortKey key) {
    final active = _sort == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          setState(() {
            if (_sort == key) {
              _sortDesc = !_sortDesc;
            } else {
              _sort = key;
              _sortDesc = true;
            }
          });
          _scrollToTop();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? AppColors.cardAlt : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: active ? AppColors.accent : AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: active ? AppColors.accent : AppColors.dim,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              if (active) ...[
                const SizedBox(width: 4),
                Icon(
                  _sortDesc ? Icons.arrow_downward : Icons.arrow_upward,
                  size: 12,
                  color: AppColors.accent,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _snapshot() async {
    setState(() { _loading = true; _err = null; });
    try {
      final m = await fetchMarkets();
      if (!mounted) return;
      context.read<AppState>().setMarkets(m);
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();

    final holdingIds = s.account?.holdings.keys.toSet() ?? const <String>{};

    // Build a snapshot of rows from AppState (updated in real-time by the stream).
    final rows = s.metas.values.map((m) {
      return (
        id: m.id,
        symbol: m.symbol,
        name: m.name,
        price: s.prices[m.id] ?? 0.0,
        change: s.changeOf(m.id),
        vol: s.volumes[m.id] ?? 0.0,
      );
    }).where((r) => r.price > 0).toList();

    int cmp(num a, num b) => _sortDesc ? b.compareTo(a) : a.compareTo(b);
    rows.sort((a, b) {
      switch (_sort) {
        case _SortKey.volume:     return cmp(a.vol, b.vol);
        case _SortKey.change:     return cmp(a.change, b.change);
        case _SortKey.volatility: return cmp(a.change.abs(), b.change.abs());
        case _SortKey.price:      return cmp(a.price, b.price);
        case _SortKey.symbol:
          return _sortDesc
              ? b.symbol.compareTo(a.symbol)
              : a.symbol.compareTo(b.symbol);
      }
    });

    Iterable<dynamic> byFilter = rows;
    switch (_filter) {
      case _Filter.all: break;
      case _Filter.favorites: byFilter = rows.where((r) => s.isFavorite(r.id)); break;
      case _Filter.gainers:  byFilter = rows.where((r) => r.change > 0); break;
      case _Filter.losers:   byFilter = rows.where((r) => r.change < 0); break;
      case _Filter.holdings: byFilter = rows.where((r) => holdingIds.contains(r.id)); break;
    }

    final q = _query.toLowerCase();
    final filtered = (q.isEmpty
        ? byFilter
        : byFilter.where((r) =>
            r.symbol.toLowerCase().contains(q) ||
            r.name.toLowerCase().contains(q) ||
            r.id.toLowerCase().contains(q))).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Market', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            const Padding(
              padding: EdgeInsets.all(16),
              child: _LivePulse(),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: InputDecoration(
                hintText: 'Search by symbol or name',
                hintStyle: const TextStyle(color: AppColors.dim),
                prefixIcon: const Icon(Icons.search, color: AppColors.dim),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, color: AppColors.dim),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
                filled: true,
                fillColor: AppColors.card,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _filterChip('All', _filter == _Filter.all,
                    () { setState(() => _filter = _Filter.all); _scrollToTop(); }),
                _filterChip('Favorites', _filter == _Filter.favorites,
                    () { setState(() => _filter = _Filter.favorites); _scrollToTop(); }),
                _filterChip('Gainers', _filter == _Filter.gainers,
                    () { setState(() => _filter = _Filter.gainers); _scrollToTop(); }),
                _filterChip('Losers', _filter == _Filter.losers,
                    () { setState(() => _filter = _Filter.losers); _scrollToTop(); }),
                _filterChip('Holdings', _filter == _Filter.holdings,
                    () { setState(() => _filter = _Filter.holdings); _scrollToTop(); }),
              ],
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: [
                _sortChip('Volume',     _SortKey.volume),
                _sortChip('24h %',      _SortKey.change),
                _sortChip('Volatility', _SortKey.volatility),
                _sortChip('Price',      _SortKey.price),
                _sortChip('Name',       _SortKey.symbol),
              ],
            ),
          ),
          if (_err != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_err!, style: const TextStyle(color: AppColors.red)),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _snapshot,
              child: filtered.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Text(
                          _loading ? 'Loading market…' : 'No coins match.',
                          style: const TextStyle(color: AppColors.dim),
                        ),
                      ),
                    ])
                  : ListView.builder(
                      controller: _scrollCtrl,
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final r = filtered[i];
                        final up = r.change >= 0;
                        final isFav = s.isFavorite(r.id);
                        final priceFmt = NumberFormat.currency(
                            locale: 'en_US',
                            symbol: '\$',
                            decimalDigits: r.price > 10 ? 2 : 6);
                        final volFmt = NumberFormat.compactCurrency(
                            locale: 'en_US', symbol: '\$');
                        return InkWell(
                          onTap: () => Navigator.push(
                            ctx,
                            MaterialPageRoute(
                              builder: (_) => TradeScreen(
                                coinId: r.id,
                                symbol: r.symbol,
                                name: r.name,
                              ),
                            ),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            decoration: const BoxDecoration(
                              border: Border(
                                  bottom: BorderSide(
                                      color: AppColors.border, width: 0.5)),
                            ),
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: () => s.toggleFavorite(r.id),
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Icon(
                                      isFav ? Icons.star : Icons.star_border,
                                      size: 18,
                                      color: isFav ? AppColors.accent : AppColors.dim,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 24,
                                  child: Text(
                                    '${i + 1}',
                                    style: const TextStyle(
                                        color: AppColors.dim, fontSize: 11),
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(r.symbol,
                                          style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 2),
                                      Text('${r.id}',
                                          style: const TextStyle(
                                              color: AppColors.dim,
                                              fontSize: 11)),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(priceFmt.format(r.price),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text(
                                        '${up ? '+' : ''}${r.change.toStringAsFixed(2)}%',
                                        style: TextStyle(
                                            color: up
                                                ? AppColors.green
                                                : AppColors.red,
                                            fontSize: 13)),
                                  ],
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 62,
                                  child: Text(volFmt.format(r.vol),
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                          color: AppColors.dim, fontSize: 11)),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LivePulse extends StatefulWidget {
  const _LivePulse();
  @override
  State<_LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<_LivePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: _c,
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.green,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 6),
        const Text('LIVE',
            style: TextStyle(
                color: AppColors.green,
                fontWeight: FontWeight.w700,
                fontSize: 11)),
      ],
    );
  }
}
