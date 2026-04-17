import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../store/app_state.dart';
import '../theme/theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmReset(BuildContext context, ClassTier t) async {
    final s = context.read<AppState>();
    final a = s.account!;
    if (a.lockedInGame) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You're in a game. Can't reset until it ends.")),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Reset account?'),
        content: Text(
            'Your holdings and cash will be wiped and you\'ll restart at '
            '\$${NumberFormat.decimalPattern().format(kStartingBalance[t])}. '
            'Reset history is preserved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok == true) s.resetAccount(t);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final a = s.account;
    if (a == null) return const SizedBox.shrink();
    final usd = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w700))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Account',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('Created: ${DateFormat.yMMMd().format(a.createdAt)}',
                    style: const TextStyle(color: AppColors.dim)),
                Text('Class: ${kClassLabels[a.tier]}',
                    style: const TextStyle(color: AppColors.dim)),
                Text('Status: ${a.lockedInGame ? 'Locked (in game)' : 'Free to reset'}',
                    style: const TextStyle(color: AppColors.dim)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Reset & change class',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...ClassTier.values.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => _confirmReset(context, t),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(kClassLabels[t]!,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(usd.format(kStartingBalance[t]),
                            style: const TextStyle(color: AppColors.dim)),
                      ],
                    ),
                  ),
                ),
              )),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Multiplayer lock (preview)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text(
                  'When a game with friends is active, reset is disabled so nobody can cheat.',
                  style: TextStyle(color: AppColors.dim),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: a.lockedInGame ? AppColors.red : AppColors.accent,
                      foregroundColor: AppColors.bg,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => s.setLockedInGame(!a.lockedInGame),
                    child: Text(a.lockedInGame ? 'End game (unlock)' : 'Start a game (lock)',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
