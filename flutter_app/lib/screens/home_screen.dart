import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../store/app_state.dart';
import '../theme/theme.dart';
import 'trade_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    // Use activeAccount so the portfolio shows game wallet during a game.
    final a = s.activeAccount ?? s.account;
    if (a == null) return const SizedBox.shrink();

    final usd = NumberFormat.currency(locale: 'en_US', symbol: '\$');
    final portfolio = s.portfolioValue();
    final start = kStartingBalance[a.tier]!;
    final pnl = portfolio - start;
    final pnlPct = start == 0 ? 0 : (pnl / start) * 100;
    final up = pnl >= 0;
    final isGameMode = s.inGame && s.gameStatus == 'active';

    final holdings = a.holdings.values.where((h) {
      final available = s.availableToSell(h.coinId);
      final price = s.priceOf(h.coinId);
      // Hide fully-reserved rows (all units queued in pending sells) and dust.
      return available > 1e-8 && available * price >= 0.01;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Portfolio', style: TextStyle(fontWeight: FontWeight.w700))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Game mode banner
          if (isGameMode)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.accent.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sports_esports, color: AppColors.accent, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Game mode active — showing your game wallet',
                      style: TextStyle(color: AppColors.accent, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isGameMode ? AppColors.accent.withOpacity(0.4) : AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isGameMode ? 'Game portfolio' : 'Portfolio value',
                    style: const TextStyle(color: AppColors.dim)),
                const SizedBox(height: 4),
                Text(usd.format(portfolio),
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  '${up ? '+' : ''}${usd.format(pnl)} (${up ? '+' : ''}${pnlPct.toStringAsFixed(2)}%)',
                  style: TextStyle(color: up ? AppColors.green : AppColors.red),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: _kv('Cash', usd.format(a.cashUsd))),
                    Expanded(child: _kv('Class', kClassLabels[a.tier]!)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(isGameMode ? 'Game holdings' : 'Holdings',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (holdings.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                isGameMode
                    ? "No holdings in your game wallet yet. Go trade!"
                    : "You don't own any coins yet. Open the Market tab to buy some.",
                style: const TextStyle(color: AppColors.dim),
              ),
            ),
          ...holdings.map((h) {
            final meta = s.metaOf(h.coinId);
            final p = s.priceOf(h.coinId);
            final value = h.amount * p;
            final avg = h.amount > 0 ? h.costBasisUsd / h.amount : 0;
            final plPct = avg > 0 ? (p - avg) / avg * 100 : 0;
            final rowUp = plPct >= 0;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TradeScreen(
                      coinId: meta.id,
                      symbol: meta.symbol,
                      name: meta.name,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(meta.symbol,
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(
                              '${h.amount.toStringAsFixed(6)} @ avg \$${avg.toStringAsFixed(avg > 10 ? 2 : 4)}',
                              style: const TextStyle(color: AppColors.dim, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(usd.format(value),
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('${rowUp ? '+' : ''}${plPct.toStringAsFixed(2)}%',
                              style: TextStyle(
                                  color: rowUp ? AppColors.green : AppColors.red)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: const TextStyle(color: AppColors.dim, fontSize: 12)),
          const SizedBox(height: 2),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        ],
      );
}
