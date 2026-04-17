import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../store/app_state.dart';
import '../theme/theme.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AppState>().account;
    if (a == null) return const SizedBox.shrink();

    final usd = NumberFormat.currency(locale: 'en_US', symbol: '\$');
    final date = DateFormat.yMMMd().add_jm();

    return Scaffold(
      appBar: AppBar(title: const Text('History', style: TextStyle(fontWeight: FontWeight.w700))),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          if (a.resetHistory.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Previous lives',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: a.resetHistory.map((r) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${date.format(r.resetAt)} · ${kClassLabels[r.tier]}',
                            style: const TextStyle(color: AppColors.dim, fontSize: 13)),
                        Text(usd.format(r.endingPortfolioUsd),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: 14),
          const Text('Transactions',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (a.transactions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text('No trades yet.', style: TextStyle(color: AppColors.dim)),
              ),
            ),
          ...a.transactions.map((t) {
            final isBuy = t.side == Side.buy;
            final statusColor = t.status == TxStatus.filled
                ? AppColors.green
                : t.status == TxStatus.failed
                    ? AppColors.red
                    : AppColors.yellow;
            final priceFmt = NumberFormat.currency(
                locale: 'en_US',
                symbol: '\$',
                decimalDigits: t.pricePerUnitUsd > 10 ? 2 : 4);
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: isBuy ? 'BUY ' : 'SELL ',
                              style: TextStyle(
                                  color: isBuy ? AppColors.green : AppColors.red,
                                  fontWeight: FontWeight.w700),
                            ),
                            TextSpan(
                              text: t.symbol,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${t.amount.toStringAsFixed(6)} @ ${priceFmt.format(t.pricePerUnitUsd)}',
                          style: const TextStyle(color: AppColors.dim, fontSize: 12),
                        ),
                        Text(date.format(t.placedAt),
                            style: const TextStyle(color: AppColors.dim, fontSize: 12)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(usd.format(t.totalUsd),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(t.status.name, style: TextStyle(color: statusColor, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
