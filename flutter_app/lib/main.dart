import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'screens/game_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/market_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_screen.dart';
import 'store/app_state.dart';
import 'theme/theme.dart';

final GlobalKey<ScaffoldMessengerState> kMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void showAppSnack(String msg, {Color? color}) {
  kMessengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(seconds: 3),
      backgroundColor: color,
    ));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const FakeCryptoApp());
}

class FakeCryptoApp extends StatelessWidget {
  const FakeCryptoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>(
      create: (_) => AppState()..load(),
      child: MaterialApp(
        title: 'FakeCrypto',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        scaffoldMessengerKey: kMessengerKey,
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root();
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  StreamSubscription<String>? _notif;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _notif ??= context.read<AppState>().notifications.listen(showAppSnack);
  }

  @override
  void dispose() {
    _notif?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (!s.ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (s.account == null) return const OnboardingScreen();
    return const _Shell();
  }
}

class _Shell extends StatefulWidget {
  const _Shell();
  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _tab = 0;

  static const _pages = <Widget>[
    HomeScreen(),
    MarketScreen(),
    GameScreen(),
    HistoryScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: _pages),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppColors.card,
        indicatorColor: AppColors.cardAlt,
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.pie_chart_outline),
              selectedIcon: Icon(Icons.pie_chart, color: AppColors.accent),
              label: 'Portfolio'),
          NavigationDestination(
              icon: Icon(Icons.trending_up_outlined),
              selectedIcon: Icon(Icons.trending_up, color: AppColors.accent),
              label: 'Market'),
          NavigationDestination(
              icon: Icon(Icons.sports_esports_outlined),
              selectedIcon: Icon(Icons.sports_esports, color: AppColors.accent),
              label: 'Play'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long, color: AppColors.accent),
              label: 'History'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings, color: AppColors.accent),
              label: 'Settings'),
        ],
      ),
    );
  }
}
