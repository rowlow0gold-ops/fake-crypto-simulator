import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/coingecko.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

const _kAccountKey = 'fake_crypto_account_v2';
const _kFavoritesKey = 'favorite_coins';
const _kDisplayNameKey = 'custom_display_name';

class AppState extends ChangeNotifier {
  Account? account;
  Map<String, double> prices = {};
  Map<String, double> changes24h = {};
  Map<String, double> volumes = {};
  Map<String, CoinMeta> metas = {};
  bool ready = false;

  // Favorites
  Set<String> favorites = {};

  // Auth state
  User? firebaseUser;
  bool get isLoggedIn => firebaseUser != null;
  String? get uid => firebaseUser?.uid;
  String? _customDisplayName;
  String? _customPhotoUrl;
  String get displayName => _customDisplayName ?? firebaseUser?.displayName ?? 'Player';
  String? get photoUrl => _customPhotoUrl ?? firebaseUser?.photoURL;
  bool pushEnabled = false;

  // Game room state
  String? activeRoomCode;
  Map<String, dynamic>? activeRoomData;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _roomSub;
  Account? _gameWallet; // separate wallet for in-game trades
  bool get inGame => activeRoomCode != null && activeRoomData != null;
  String? get gameStatus => activeRoomData?['status'] as String?;

  BinanceStream? _stream;
  Timer? _coalesce;
  Timer? _restPoll;
  Timer? _cloudSync;
  bool _dirty = false;
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);

  final StreamController<String> _notif = StreamController.broadcast();
  Stream<String> get notifications => _notif.stream;
  void _notify(String msg) => _notif.add(msg);

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kAccountKey);
    if (raw != null) {
      try {
        account = Account.fromJson(jsonDecode(raw));
      } catch (_) {
        account = null;
      }
    }

    // Restore favorites, custom display name, and photo.
    favorites = (sp.getStringList(_kFavoritesKey) ?? []).toSet();
    _customDisplayName = sp.getString(_kDisplayNameKey);
    _customPhotoUrl = sp.getString('custom_photo_url');

    // Restore Firebase auth state (persists across app restarts).
    firebaseUser = AuthService.currentUser;
    if (isLoggedIn) {
      pushEnabled = await FirestoreService.getPushEnabled(uid!);
      _startCloudSync();
      loadPriceAlerts();
      if (pushEnabled) initFcm(silent: true);
    }

    ready = true;
    notifyListeners();
    _startStream();
  }

  void _startStream() {
    _stream?.close();
    _stream = BinanceStream(
      onBatch: (batch) {
        for (final t in batch) {
          prices[t.id] = t.price;
          if (t.change24hPct != null) changes24h[t.id] = t.change24hPct!;
          volumes[t.id] = t.totalVolume;
        }
        _lastTick = DateTime.now();
        _dirty = true;
        _checkLimits(); // auto-trigger stop/take orders on every tick
        _checkPriceAlerts();
      },
    );
    _stream!.connect();

    // Flush dirty state to the UI at a steady 2 fps — every tab sees movement
    // even if it's not currently re-rendering the row that ticked.
    _coalesce?.cancel();
    _coalesce = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_dirty) {
        _dirty = false;
        notifyListeners();
      }
    });

    // Fallback: if the WebSocket goes silent for >15s, poll REST so the
    // portfolio and market still move.
    _restPoll?.cancel();
    _restPoll = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (DateTime.now().difference(_lastTick).inSeconds < 15) return;
      try {
        final m = await fetchMarkets(force: true);
        setMarkets(m);
        _lastTick = DateTime.now();
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _coalesce?.cancel();
    _restPoll?.cancel();
    _cloudSync?.cancel();
    _stream?.close();
    _roomSub?.cancel();
    _notif.close();
    super.dispose();
  }

  Future<void> _persist() async {
    final sp = await SharedPreferences.getInstance();
    if (account == null) {
      await sp.remove(_kAccountKey);
    } else {
      await sp.setString(_kAccountKey, jsonEncode(account!.toJson()));
    }
  }

  /// Sync portfolio to cloud periodically (every 30s if logged in).
  void _startCloudSync() {
    _cloudSync?.cancel();
    _cloudSync = Timer.periodic(const Duration(seconds: 30), (_) {
      _syncToCloud();
    });
  }

  Future<void> _syncToCloud() async {
    if (!isLoggedIn || account == null) return;
    try {
      await FirestoreService.saveProfile(
        uid: uid!,
        account: account!,
        displayName: displayName,
        email: firebaseUser?.email,
        photoUrl: photoUrl,
        pushEnabled: pushEnabled,
      );
    } catch (_) {}
  }

  // ---------- Auth ----------

  /// Sign in with Google. Returns 'ok', 'conflict', or 'error:...'
  Future<String> signInWithGoogle() async {
    try {
      final user = await AuthService.signInWithGoogle();
      if (user == null) return 'cancelled';
      firebaseUser = user;
      notifyListeners();

      // Check for cloud data conflict
      final hasCloud = await FirestoreService.hasCloudData(user.uid);
      if (hasCloud && account != null) {
        return 'conflict'; // caller shows resolution dialog
      }

      if (hasCloud && account == null) {
        // Restore from cloud
        final cloud = await FirestoreService.fetchCloudAccount(user.uid);
        if (cloud != null) {
          account = cloud;
          await _persist();
        }
      } else {
        // First login or no cloud data — push local to cloud
        await _syncToCloud();
      }

      pushEnabled = await FirestoreService.getPushEnabled(user.uid);
      _startCloudSync();
      await loadPriceAlerts();
      if (pushEnabled) initFcm(silent: true);
      notifyListeners();
      _notify('Signed in as ${user.displayName ?? user.email}');
      return 'ok';
    } catch (e) {
      return 'error:$e';
    }
  }

  /// Resolve conflict: keep cloud or local.
  Future<void> resolveConflict({required bool keepCloud}) async {
    if (!isLoggedIn) return;
    if (keepCloud) {
      final cloud = await FirestoreService.fetchCloudAccount(uid!);
      if (cloud != null) {
        account = cloud;
        await _persist();
      }
    } else {
      // Overwrite cloud with local
      await _syncToCloud();
    }
    pushEnabled = await FirestoreService.getPushEnabled(uid!);
    _startCloudSync();
    notifyListeners();
  }

  Future<void> signOut() async {
    _cloudSync?.cancel();
    await AuthService.signOut();
    firebaseUser = null;
    pushEnabled = false;
    notifyListeners();
    _notify('Signed out');
  }

  Future<void> togglePush(bool enabled) async {
    if (!isLoggedIn) return;
    if (enabled) {
      // Try requesting permission — initFcm will roll back if denied
      pushEnabled = true;
      notifyListeners();
      await initFcm();
      // If initFcm rolled it back, don't save true
      if (!pushEnabled) return;
      await FirestoreService.setPushEnabled(uid!, true);
    } else {
      pushEnabled = false;
      await FirestoreService.setPushEnabled(uid!, false);
      notifyListeners();
    }
  }

  // ---------- Game rooms ----------

  Future<String> createRoom({
    required String mode,
    required double specialsCash,
    required String classMode,
    required int timeLimitMinutes,
    required String visibility,
    required ClassTier creatorClass,
  }) async {
    if (!isLoggedIn) return '';
    final code = _generateRoomCode();
    await FirestoreService.createRoom(
      code: code,
      creatorUid: uid!,
      creatorName: displayName,
      creatorPhoto: photoUrl,
      mode: mode,
      specialsCash: specialsCash,
      classMode: classMode,
      timeLimitMinutes: timeLimitMinutes,
      visibility: visibility,
      creatorAccount: mode == 'original' ? account : null,
      creatorClass: creatorClass,
    );
    _joinRoomStream(code);
    _notify('Room $code created');
    return code;
  }

  String _generateRoomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(6, (_) => chars[_rand.nextInt(chars.length)]).join();
  }

  Future<bool> joinRoom(String code, {ClassTier tier = ClassTier.middle}) async {
    if (!isLoggedIn) return false;
    final data = await FirestoreService.joinRoom(
      code: code.toUpperCase(),
      uid: uid!,
      displayName: displayName,
      photoUrl: photoUrl,
      userAccount: account,
    );
    if (data == null) {
      _notify('Room not found or already ended');
      return false;
    }
    _joinRoomStream(code.toUpperCase());
    _notify('Joined room $code');
    return true;
  }

  void _joinRoomStream(String code) {
    _roomSub?.cancel();
    activeRoomCode = code;
    _roomSub = FirestoreService.roomStream(code).listen((snap) {
      if (!snap.exists) {
        // Room was deleted
        activeRoomCode = null;
        activeRoomData = null;
        _gameWallet = null;
        _roomSub?.cancel();
        _notify('Room was closed');
        notifyListeners();
        return;
      }
      activeRoomData = snap.data();

      // Extract our game wallet
      final members = activeRoomData?['members'] as Map<String, dynamic>?;
      if (members != null && members.containsKey(uid)) {
        final myData = members[uid] as Map<String, dynamic>;
        if (myData['gameWallet'] != null) {
          try {
            _gameWallet = Account.fromJson(Map<String, dynamic>.from(myData['gameWallet']));
          } catch (_) {}
        }
      }

      // Check if game ended by time
      final status = activeRoomData?['status'] as String?;
      final endsAt = activeRoomData?['endsAt'];
      if (status == 'active' && endsAt != null) {
        DateTime endTime;
        if (endsAt is Timestamp) {
          endTime = endsAt.toDate();
        } else {
          endTime = DateTime.now().add(const Duration(hours: 999));
        }
        if (DateTime.now().isAfter(endTime)) {
          FirestoreService.endGame(code);
        }
      }

      notifyListeners();
    });
    notifyListeners();
  }

  Future<void> leaveRoom() async {
    if (activeRoomCode == null || !isLoggedIn) return;
    await FirestoreService.leaveRoom(activeRoomCode!, uid!);
    _roomSub?.cancel();
    final code = activeRoomCode;
    activeRoomCode = null;
    activeRoomData = null;
    _gameWallet = null;
    notifyListeners();
    _notify('Left room $code');
  }

  /// Get sorted leaderboard from active room.
  List<Map<String, dynamic>> roomLeaderboard() {
    final members = activeRoomData?['members'] as Map<String, dynamic>?;
    if (members == null) return [];
    final list = members.entries.map((e) {
      final m = Map<String, dynamic>.from(e.value as Map);
      m['uid'] = e.key;
      return m;
    }).toList();
    list.sort((a, b) =>
        ((b['portfolioValue'] as num?) ?? 0).compareTo((a['portfolioValue'] as num?) ?? 0));
    return list;
  }

  /// Start game after lobby.
  Future<void> startGameFromLobby() async {
    if (activeRoomCode == null) return;
    final minutes = activeRoomData?['timeLimitMinutes'] as int? ?? 60;
    await FirestoreService.startGame(activeRoomCode!, minutes);
  }

  /// Sync game wallet to room after a trade.
  Future<void> syncGameWallet() async {
    if (activeRoomCode == null || !isLoggedIn || _gameWallet == null) return;
    final val = _gamePortfolioValue();
    await FirestoreService.updateMemberWallet(
      code: activeRoomCode!,
      uid: uid!,
      gameWallet: _gameWallet!,
      portfolioValue: val,
    );
  }

  double _gamePortfolioValue() {
    final w = _gameWallet;
    if (w == null) return 0;
    var v = w.cashUsd;
    for (final h in w.holdings.values) {
      v += h.amount * (prices[h.coinId] ?? 0);
    }
    return v;
  }

  void setPrices(Map<String, double> p) {
    prices = p;
    notifyListeners();
  }

  void setMarkets(List<MarketRow> rows) {
    for (final r in rows) {
      prices[r.id] = r.currentPrice;
      if (r.change24hPct != null) changes24h[r.id] = r.change24hPct!;
      volumes[r.id] = r.totalVolume;
      metas[r.id] = CoinMeta(id: r.id, symbol: r.symbol, name: r.name);
    }
    notifyListeners();
  }

  double changeOf(String coinId) => changes24h[coinId] ?? 0;

  /// Coin amount currently queued in pending SELL orders for [coinId].
  double pendingSellAmount(String coinId) {
    final a = activeAccount;
    if (a == null) return 0;
    var sum = 0.0;
    for (final t in a.transactions) {
      if (t.status == TxStatus.pending &&
          t.side == Side.sell &&
          t.coinId == coinId) {
        sum += t.amount;
      }
    }
    return sum;
  }

  /// Holding amount minus whatever is already queued to sell.
  double availableToSell(String coinId) {
    final h = activeAccount?.holdings[coinId];
    if (h == null) return 0;
    return (h.amount - pendingSellAmount(coinId)).clamp(0, double.infinity);
  }

  /// USD currently reserved by pending BUY orders.
  double pendingBuyCost() {
    final a = activeAccount;
    if (a == null) return 0;
    var sum = 0.0;
    for (final t in a.transactions) {
      if (t.status == TxStatus.pending && t.side == Side.buy) {
        sum += t.totalUsd;
      }
    }
    return sum;
  }

  double availableCash() {
    final a = activeAccount;
    if (a == null) return 0;
    return (a.cashUsd - pendingBuyCost()).clamp(0, double.infinity);
  }

  CoinMeta metaOf(String coinId) =>
      metas[coinId] ?? CoinMeta(id: coinId, symbol: coinId.toUpperCase(), name: coinId);

  double priceOf(String coinId) => prices[coinId] ?? 0;

  /// Set a custom display name (overrides Google name).
  Future<void> setDisplayName(String name) async {
    _customDisplayName = name.trim().isEmpty ? null : name.trim();
    final sp = await SharedPreferences.getInstance();
    if (_customDisplayName == null) {
      await sp.remove(_kDisplayNameKey);
    } else {
      await sp.setString(_kDisplayNameKey, _customDisplayName!);
    }
    if (isLoggedIn) _syncToCloud();
    notifyListeners();
  }

  /// Set a custom profile photo (local file path, overrides Google photo).
  Future<void> setCustomPhoto(String path) async {
    _customPhotoUrl = path;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('custom_photo_url', path);
    if (isLoggedIn) _syncToCloud();
    notifyListeners();
  }

  bool isFavorite(String coinId) => favorites.contains(coinId);

  Future<void> toggleFavorite(String coinId) async {
    if (favorites.contains(coinId)) {
      favorites.remove(coinId);
    } else {
      favorites.add(coinId);
    }
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_kFavoritesKey, favorites.toList());
    notifyListeners();
  }

  double portfolioValue() {
    final a = activeAccount;
    if (a == null) return 0;
    var v = a.cashUsd;
    for (final h in a.holdings.values) {
      v += h.amount * (prices[h.coinId] ?? 0);
    }
    return v;
  }

  Future<void> createAccount(ClassTier tier) async {
    account = Account.empty(tier);
    await _persist();
    notifyListeners();
  }

  Future<void> resetAccount(ClassTier tier) async {
    final a = account;
    if (a == null) {
      await createAccount(tier);
      return;
    }
    if (a.lockedInGame) return;
    final record = ResetRecord(
      resetAt: DateTime.now(),
      tier: a.tier,
      endingCashUsd: a.cashUsd,
      endingPortfolioUsd: portfolioValue(),
    );
    final fresh = Account.empty(tier);
    fresh.resetHistory = [...a.resetHistory, record];
    account = fresh;
    await _persist();
    notifyListeners();
  }

  Future<void> setLockedInGame(bool locked) async {
    if (account == null) return;
    account!.lockedInGame = locked;
    await _persist();
    notifyListeners();
  }

  final _rand = Random();

  /// Returns the game wallet if in an active game, otherwise the real account.
  Account? get activeAccount {
    if (inGame && gameStatus == 'active' && _gameWallet != null) {
      return _gameWallet;
    }
    return account;
  }

  /// Persist the right account (game → cloud, real → local).
  Future<void> _persistActive() async {
    if (inGame && _gameWallet != null) {
      syncGameWallet();
    } else {
      await _persist();
    }
  }

  Transaction placeOrder({
    required String coinId,
    required String symbol,
    required Side side,
    required double amount,
    required double pricePerUnitUsd,
  }) {
    final a = activeAccount;
    if (a == null) {
      _notify('No active account');
      return Transaction(
        id: 'err', coinId: coinId, symbol: symbol, side: side,
        amount: 0, pricePerUnitUsd: 0, totalUsd: 0,
        status: TxStatus.failed, placedAt: DateTime.now(),
      );
    }
    final tx = Transaction(
      id: '${DateTime.now().microsecondsSinceEpoch}_${_rand.nextInt(1 << 31)}',
      coinId: coinId,
      symbol: symbol,
      side: side,
      amount: amount,
      pricePerUnitUsd: pricePerUnitUsd,
      totalUsd: amount * pricePerUnitUsd,
      status: TxStatus.pending,
      placedAt: DateTime.now(),
    );
    a.transactions.insert(0, tx);
    _persistActive();
    notifyListeners();
    _notify('Order placed: ${side == Side.buy ? 'BUY' : 'SELL'} $symbol — filling in 1–5s');

    final delayMs = 1000 + _rand.nextInt(4000);
    Future.delayed(Duration(milliseconds: delayMs), () => _fill(tx.id));
    return tx;
  }

  void _fill(String id) {
    final a = activeAccount;
    if (a == null) return;
    final idx = a.transactions.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final tx = a.transactions[idx];
    if (tx.status != TxStatus.pending) return;

    final livePrice = prices[tx.coinId] ?? tx.pricePerUnitUsd;
    var total = tx.amount * livePrice;
    final existing = a.holdings[tx.coinId] ??
        Holding(coinId: tx.coinId, amount: 0, costBasisUsd: 0);

    if (tx.side == Side.buy) {
      var fee = total * kFeeRate;
      var totalWithFee = total + fee;
      // If the price drifted up during the 1–5s fill delay, clip the order
      // down to whatever cash is available so a 100% buy still fills. Only
      // fail if there's literally no cash.
      if (totalWithFee > a.cashUsd) {
        if (a.cashUsd <= 0) {
          tx.status = TxStatus.failed;
          tx.failReason = 'Not enough cash at fill price';
          tx.filledAt = DateTime.now();
          _persistActive();
          notifyListeners();
          _notify('Buy ${tx.symbol} failed: ${tx.failReason}');
          return;
        }
        totalWithFee = a.cashUsd;
        total = totalWithFee / (1 + kFeeRate);
        fee = totalWithFee - total;
        tx.amount = total / livePrice;
      }
      a.cashUsd -= totalWithFee;
      existing.amount += tx.amount;
      existing.costBasisUsd += totalWithFee; // fee is part of basis
      a.holdings[tx.coinId] = existing;
      tx.pricePerUnitUsd = livePrice;
      tx.totalUsd = total;
      tx.feeUsd = fee;
      tx.status = TxStatus.filled;
      tx.filledAt = DateTime.now();
    } else {
      // Be tolerant of float slop on 100% sells.
      if (tx.amount > existing.amount && tx.amount < existing.amount * 1.001) {
        tx.amount = existing.amount;
      }
      if (existing.amount < tx.amount) {
        tx.status = TxStatus.failed;
        tx.failReason = 'Holdings dropped below order size';
        tx.filledAt = DateTime.now();
      } else {
        total = tx.amount * livePrice;
        final fee = total * kFeeRate;
        final proceeds = total - fee;
        final avg = existing.amount > 0 ? existing.costBasisUsd / existing.amount : 0;
        a.cashUsd += proceeds;
        final newAmount = existing.amount - tx.amount;
        existing.amount = newAmount;
        existing.costBasisUsd =
            (existing.costBasisUsd - avg * tx.amount).clamp(0, double.infinity);
        // Treat sub-cent dust as zero so the holding disappears from the list.
        if (newAmount <= 1e-8 || newAmount * livePrice < 0.01) {
          a.holdings.remove(tx.coinId);
        } else {
          a.holdings[tx.coinId] = existing;
        }
        tx.pricePerUnitUsd = livePrice;
        tx.totalUsd = total;
        tx.feeUsd = fee;
        tx.status = TxStatus.filled;
        tx.filledAt = DateTime.now();
      }
    }
    _persistActive();
    notifyListeners();

    final verb = tx.side == Side.buy ? 'Bought' : 'Sold';
    if (tx.status == TxStatus.filled) {
      _notify('$verb ${tx.amount.toStringAsFixed(6)} ${tx.symbol} for \$${total.toStringAsFixed(2)} (fee \$${tx.feeUsd.toStringAsFixed(2)})');
    } else {
      _notify('${tx.side == Side.buy ? 'Buy' : 'Sell'} ${tx.symbol} failed: ${tx.failReason ?? 'unknown reason'}');
    }
  }

  // ---------- Limit orders (auto stop-loss / take-profit) ----------

  Future<void> addLimit({
    required String coinId,
    required String symbol,
    required LimitKind kind,
    required double triggerPrice,
    required double amount,
    Side side = Side.sell,
    ReservationDir? direction,
  }) async {
    final dir = direction ??
        (kind == LimitKind.stop ? ReservationDir.below : ReservationDir.above);
    final l = LimitOrder(
      id: '${DateTime.now().microsecondsSinceEpoch}_${_rand.nextInt(1 << 31)}',
      coinId: coinId,
      symbol: symbol,
      kind: kind,
      triggerPrice: triggerPrice,
      amount: amount,
      createdAt: DateTime.now(),
      side: side,
      direction: dir,
    );
    account!.limits.add(l);
    await _persist();
    notifyListeners();
    final label = side == Side.buy ? 'Buy reservation' : '${kind == LimitKind.stop ? 'Stop' : 'Take'} order';
    _notify('$label set on $symbol @ \$${triggerPrice.toStringAsFixed(triggerPrice > 10 ? 2 : 6)}');
  }

  Future<void> removeLimit(String id) async {
    account?.limits.removeWhere((l) => l.id == id);
    await _persist();
    notifyListeners();
  }

  List<LimitOrder> limitsFor(String coinId) =>
      account?.limits.where((l) => l.coinId == coinId).toList() ?? const [];

  void _checkLimits() {
    final a = account;
    if (a == null || a.limits.isEmpty) return;
    final fired = <LimitOrder>[];
    for (final l in a.limits) {
      final p = prices[l.coinId];
      if (p == null || p <= 0) continue;
      final hit = (l.direction == ReservationDir.below && p <= l.triggerPrice) ||
          (l.direction == ReservationDir.above && p >= l.triggerPrice);
      if (hit) fired.add(l);
    }
    for (final l in fired) {
      a.limits.removeWhere((x) => x.id == l.id);
      final p = prices[l.coinId]!;

      if (l.side == Side.sell) {
        final h = a.holdings[l.coinId];
        final available = (h?.amount ?? 0) - pendingSellAmount(l.coinId);
        final amt = l.amount > available ? available : l.amount;
        if (amt > 0) {
          _notify('${l.kind == LimitKind.stop ? 'Stop' : 'Take'} triggered on ${l.symbol} @ \$${p.toStringAsFixed(2)}');
          placeOrder(
            coinId: l.coinId,
            symbol: l.symbol,
            side: Side.sell,
            amount: amt,
            pricePerUnitUsd: p,
          );
        }
      } else {
        // Buy reservation
        final cash = availableCash();
        final cost = l.amount * p;
        if (cost > 0 && cash > 0) {
          final buyAmt = cost <= cash ? l.amount : cash / p;
          _notify('Buy reservation triggered on ${l.symbol} @ \$${p.toStringAsFixed(2)}');
          placeOrder(
            coinId: l.coinId,
            symbol: l.symbol,
            side: Side.buy,
            amount: buyAmt,
            pricePerUnitUsd: p,
          );
        }
      }
    }
    if (fired.isNotEmpty) {
      _persist();
    }
  }

  // ---------- Price alerts (one-shot, cloud-stored) ----------

  List<Map<String, dynamic>> priceAlerts = [];
  DateTime _lastAlertCheck = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> loadPriceAlerts() async {
    if (!isLoggedIn) return;
    priceAlerts = await FirestoreService.getPriceAlerts(uid!);
    notifyListeners();
  }

  Future<void> addPriceAlert({
    required String coinId,
    required String symbol,
    required double targetPrice,
    required String direction,
  }) async {
    if (!isLoggedIn) return;
    await FirestoreService.addPriceAlert(
      uid: uid!,
      coinId: coinId,
      symbol: symbol,
      targetPrice: targetPrice,
      direction: direction,
    );
    await loadPriceAlerts();
    _notify('Price alert set: $symbol ${direction == 'above' ? '>' : '<'} \$${targetPrice.toStringAsFixed(targetPrice > 10 ? 2 : 6)}');
  }

  Future<void> removePriceAlert(String alertId) async {
    await FirestoreService.deletePriceAlert(alertId);
    priceAlerts.removeWhere((a) => a['id'] == alertId);
    notifyListeners();
  }

  void _checkPriceAlerts() {
    // Throttle to once per 2 seconds to avoid spamming
    final now = DateTime.now();
    if (now.difference(_lastAlertCheck).inSeconds < 2) return;
    _lastAlertCheck = now;
    if (!isLoggedIn || priceAlerts.isEmpty) return;

    final toFire = <Map<String, dynamic>>[];
    for (final a in priceAlerts) {
      final p = prices[a['coinId']];
      if (p == null || p <= 0) continue;
      final target = (a['targetPrice'] as num).toDouble();
      final dir = a['direction'] as String;
      final hit = (dir == 'above' && p >= target) || (dir == 'below' && p <= target);
      if (hit) toFire.add(a);
    }
    for (final a in toFire) {
      final symbol = a['symbol'] as String;
      final target = (a['targetPrice'] as num).toDouble();
      _notify('Price alert: $symbol hit \$${target.toStringAsFixed(target > 10 ? 2 : 6)}!');
      FirestoreService.firePriceAlert(a['id'] as String);
      priceAlerts.removeWhere((x) => x['id'] == a['id']);
    }
    if (toFire.isNotEmpty) notifyListeners();
  }

  // ---------- FCM ----------

  Future<void> initFcm({bool silent = false}) async {
    if (!isLoggedIn) return;
    try {
      final messaging = FirebaseMessaging.instance;

      // Check current status first
      final current = await messaging.getNotificationSettings();
      if (current.authorizationStatus == AuthorizationStatus.denied) {
        // Previously denied — system won't show the popup again.
        pushEnabled = false;
        notifyListeners();
        // Only show the "open settings" dialog when user explicitly toggled
        if (!silent) _notify('open_notification_settings');
        return;
      }

      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        final token = await messaging.getToken();
        if (token != null) {
          await FirestoreService.saveFcmToken(uid!, token);
        }
      } else {
        // User denied — roll back the toggle
        pushEnabled = false;
        await FirestoreService.setPushEnabled(uid!, false);
        notifyListeners();
      }
    } catch (_) {
      // Something went wrong — roll back
      pushEnabled = false;
      if (isLoggedIn) {
        FirestoreService.setPushEnabled(uid!, false);
      }
      notifyListeners();
    }
  }
}
