import 'dart:async';
import 'dart:io';
import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../store/app_state.dart';
import '../theme/theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  StreamSubscription<String>? _notifSub;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _notifSub = s.notifications.listen((msg) {
      if (msg == 'open_notification_settings' && mounted) {
        _showOpenSettingsDialog();
      }
    });
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    super.dispose();
  }

  void _showOpenSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Notifications blocked'),
        content: const Text(
          'You previously denied notification permissions. '
          'Please enable them in your device settings to receive push notifications.',
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
              Navigator.pop(ctx);
              AppSettings.openAppSettings(type: AppSettingsType.notification);
            },
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
  }

  void _editName(BuildContext context, AppState s) {
    final ctrl = TextEditingController(text: s.displayName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Edit display name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 20,
          style: const TextStyle(fontSize: 18),
          decoration: const InputDecoration(
            hintText: 'Your name',
            hintStyle: TextStyle(color: AppColors.dim),
            counterStyle: TextStyle(color: AppColors.dim),
          ),
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
              s.setDisplayName(ctrl.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _changePhoto(BuildContext context, AppState s) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 256, maxHeight: 256);
    if (picked == null) return;

    // Copy to app directory so it persists
    final dir = await getApplicationDocumentsDirectory();
    final saved = await File(picked.path).copy('${dir.path}/profile_photo.jpg');
    await s.setCustomPhoto(saved.path);
  }

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

  Future<void> _handleLogin(BuildContext context) async {
    final s = context.read<AppState>();
    final result = await s.signInWithGoogle();
    if (!context.mounted) return;

    if (result == 'conflict') {
      final choice = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text('Portfolio conflict'),
          content: const Text(
            'You have a portfolio saved in the cloud AND on this device. '
            'Which one do you want to keep? The other will be overwritten.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cloud'),
              child: const Text('Keep cloud'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
              onPressed: () => Navigator.pop(ctx, 'local'),
              child: const Text('Keep local'),
            ),
          ],
        ),
      );
      if (choice != null) {
        await s.resolveConflict(keepCloud: choice == 'cloud');
      }
    } else if (result.startsWith('error:')) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Login failed: ${result.substring(6)}')),
        );
      }
    }
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
          // --- Google account ---
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: s.isLoggedIn
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => _changePhoto(context, s),
                            child: Stack(
                              children: [
                                CircleAvatar(
                                  backgroundImage: s.photoUrl != null
                                      ? (s.photoUrl!.startsWith('/')
                                          ? FileImage(File(s.photoUrl!)) as ImageProvider
                                          : NetworkImage(s.photoUrl!))
                                      : null,
                                  radius: 24,
                                  backgroundColor: AppColors.cardAlt,
                                  child: s.photoUrl == null
                                      ? const Icon(Icons.person, color: AppColors.dim)
                                      : null,
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      color: AppColors.accent,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.edit, size: 12, color: AppColors.bg),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                GestureDetector(
                                  onTap: () => _editName(context, s),
                                  child: Row(
                                    children: [
                                      Text(s.displayName,
                                          style: const TextStyle(
                                              fontSize: 16, fontWeight: FontWeight.w700)),
                                      const SizedBox(width: 6),
                                      const Icon(Icons.edit, size: 14, color: AppColors.dim),
                                    ],
                                  ),
                                ),
                                Text(s.firebaseUser?.email ?? '',
                                    style: const TextStyle(
                                        color: AppColors.dim, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.border),
                          ),
                          onPressed: () => s.signOut(),
                          child: const Text('Sign out',
                              style: TextStyle(color: AppColors.dim)),
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Sign in',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      const Text(
                        'Sign in with Google to sync your portfolio, play with friends, and get push notifications.',
                        style: TextStyle(color: AppColors.dim, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.login),
                          label: const Text('Sign in with Google',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: AppColors.bg,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () => _handleLogin(context),
                        ),
                      ),
                    ],
                  ),
          ),

          // --- Push notifications (only when logged in) ---
          if (s.isLoggedIn) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Push notifications',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        Text('Game progress, order fills, price alerts',
                            style: TextStyle(color: AppColors.dim, fontSize: 12)),
                      ],
                    ),
                  ),
                  Switch(
                    value: s.pushEnabled,
                    activeColor: AppColors.accent,
                    onChanged: (v) => s.togglePush(v),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // --- Account info ---
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
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
