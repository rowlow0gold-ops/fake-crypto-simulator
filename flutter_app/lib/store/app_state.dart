import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/coingecko.dart';
import '../models/models.dart';

const _kAccountKey = 'fake_crypto_account_v2';

class AppState extends ChangeNotifier {
  Account? account;
  Map<String, double> prices = {};
  Map<String, double> changes24h = {};
  Map<String, double> volumes = {};
  Map<String, CoinMeta> metas = {};
  bool ready = false;

  BinanceStream? _stream;
  Timer? _coalesce;
  Timer? _restPoll;
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
    _stream?.close();
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
    final a = account;
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
    final h = account?.holdings[coinId];
    if (h == null) return 0;
    return (h.amount - pendingSellAmount(coinId)).clamp(0, double.infinity);
  }

  /// USD currently reserved by pending BUY orders.
  double pendingBuyCost() {
    final a = account;
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
    final a = account;
    if (a == null) return 0;
    return (a.cashUsd - pendingBuyCost()).clamp(0, double.infinity);
  }

  CoinMeta metaOf(String coinId) =>
      metas[coinId] ?? CoinMeta(id: coinId, symbol: coinId.toUpperCase(), name: coinId);

  double priceOf(String coinId) => prices[coinId] ?? 0;

  double portfolioValue() {
    final a = account;
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

  Transaction placeOrder({
    required String coinId,
    required String symbol,
    required Side side,
    required double amount,
    required double pricePerUnitUsd,
  }) {
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
    account!.transactions.insert(0, tx);
    _persist();
    notifyListeners();
    _notify('Order placed: ${side == Side.buy ? 'BUY' : 'SELL'} $symbol — filling in 1–5s');

    final delayMs = 1000 + _rand.nextInt(4000);
    Future.delayed(Duration(milliseconds: delayMs), () => _fill(tx.id));
    return tx;
  }

  void _fill(String id) {
    final a = account;
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
          _persist();
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
    _persist();
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
  }) async {
    final l = LimitOrder(
      id: '${DateTime.now().microsecondsSinceEpoch}_${_rand.nextInt(1 << 31)}',
      coinId: coinId,
      symbol: symbol,
      kind: kind,
      triggerPrice: triggerPrice,
      amount: amount,
      createdAt: DateTime.now(),
    );
    account!.limits.add(l);
    await _persist();
    notifyListeners();
    _notify('${kind == LimitKind.stop ? 'Stop' : 'Take'} order set on $symbol @ \$${triggerPrice.toStringAsFixed(triggerPrice > 10 ? 2 : 6)}');
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
      final hit = (l.kind == LimitKind.stop && p <= l.triggerPrice) ||
          (l.kind == LimitKind.take && p >= l.triggerPrice);
      if (hit) fired.add(l);
    }
    for (final l in fired) {
      a.limits.removeWhere((x) => x.id == l.id);
      final h = a.holdings[l.coinId];
      final available = (h?.amount ?? 0) - pendingSellAmount(l.coinId);
      final amt = l.amount > available ? available : l.amount;
      if (amt > 0) {
        _notify('${l.kind == LimitKind.stop ? 'Stop' : 'Take'} triggered on ${l.symbol} @ \$${prices[l.coinId]!.toStringAsFixed(2)}');
        placeOrder(
          coinId: l.coinId,
          symbol: l.symbol,
          side: Side.sell,
          amount: amt,
          pricePerUnitUsd: prices[l.coinId]!,
        );
      }
    }
    if (fired.isNotEmpty) {
      _persist();
    }
  }
}
