/// Simulated taker fee, applied on both buys and sells. 0.1% — same as Binance spot.
const double kFeeRate = 0.001;

enum ClassTier { upper, middle, working, lower }

const Map<ClassTier, double> kStartingBalance = {
  ClassTier.upper: 1000000,
  ClassTier.middle: 100000,
  ClassTier.working: 10000,
  ClassTier.lower: 1000,
};

const Map<ClassTier, String> kClassLabels = {
  ClassTier.upper: 'Upper class',
  ClassTier.middle: 'Middle class',
  ClassTier.working: 'Working class',
  ClassTier.lower: 'Lower class',
};

ClassTier tierFromString(String s) =>
    ClassTier.values.firstWhere((t) => t.name == s, orElse: () => ClassTier.middle);

class CoinMeta {
  final String id;
  final String symbol;
  final String name;
  const CoinMeta({required this.id, required this.symbol, required this.name});
}

class Holding {
  String coinId;
  double amount;
  double costBasisUsd;
  Holding({required this.coinId, required this.amount, required this.costBasisUsd});

  Map<String, dynamic> toJson() =>
      {'coinId': coinId, 'amount': amount, 'costBasisUsd': costBasisUsd};
  factory Holding.fromJson(Map<String, dynamic> j) => Holding(
      coinId: j['coinId'],
      amount: (j['amount'] as num).toDouble(),
      costBasisUsd: (j['costBasisUsd'] as num).toDouble());
}

enum Side { buy, sell }
enum TxStatus { pending, filled, failed }

class Transaction {
  final String id;
  final String coinId;
  final String symbol;
  final Side side;
  double amount;
  double pricePerUnitUsd;
  double totalUsd;
  double feeUsd;
  TxStatus status;
  String? failReason;
  final DateTime placedAt;
  DateTime? filledAt;

  Transaction({
    required this.id,
    required this.coinId,
    required this.symbol,
    required this.side,
    required this.amount,
    required this.pricePerUnitUsd,
    required this.totalUsd,
    required this.status,
    required this.placedAt,
    this.feeUsd = 0,
    this.failReason,
    this.filledAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'coinId': coinId,
        'symbol': symbol,
        'side': side.name,
        'amount': amount,
        'pricePerUnitUsd': pricePerUnitUsd,
        'totalUsd': totalUsd,
        'feeUsd': feeUsd,
        'status': status.name,
        'failReason': failReason,
        'placedAt': placedAt.millisecondsSinceEpoch,
        'filledAt': filledAt?.millisecondsSinceEpoch,
      };

  factory Transaction.fromJson(Map<String, dynamic> j) => Transaction(
        id: j['id'],
        coinId: j['coinId'],
        symbol: j['symbol'],
        side: Side.values.byName(j['side']),
        amount: (j['amount'] as num).toDouble(),
        pricePerUnitUsd: (j['pricePerUnitUsd'] as num).toDouble(),
        totalUsd: (j['totalUsd'] as num).toDouble(),
        feeUsd: ((j['feeUsd'] as num?) ?? 0).toDouble(),
        status: TxStatus.values.byName(j['status']),
        failReason: j['failReason'] as String?,
        placedAt: DateTime.fromMillisecondsSinceEpoch(j['placedAt']),
        filledAt: j['filledAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(j['filledAt'])
            : null,
      );
}

/// Auto-sell trigger. `stop` fires when price falls to/below [triggerPrice];
/// `take` fires when price rises to/above [triggerPrice].
enum LimitKind { stop, take }

/// Reservation: buy or sell at a target price.
/// `above` = trigger when price >= target, `below` = trigger when price <= target.
enum ReservationDir { above, below }

class LimitOrder {
  final String id;
  final String coinId;
  final String symbol;
  final LimitKind kind;
  final double triggerPrice;
  final double amount; // coin units to sell/buy when triggered
  final DateTime createdAt;
  final Side side; // buy or sell
  final ReservationDir direction; // above or below trigger

  LimitOrder({
    required this.id,
    required this.coinId,
    required this.symbol,
    required this.kind,
    required this.triggerPrice,
    required this.amount,
    required this.createdAt,
    this.side = Side.sell,
    this.direction = ReservationDir.below,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'coinId': coinId,
        'symbol': symbol,
        'kind': kind.name,
        'triggerPrice': triggerPrice,
        'amount': amount,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'side': side.name,
        'direction': direction.name,
      };

  factory LimitOrder.fromJson(Map<String, dynamic> j) => LimitOrder(
        id: j['id'],
        coinId: j['coinId'],
        symbol: j['symbol'],
        kind: LimitKind.values.byName(j['kind']),
        triggerPrice: (j['triggerPrice'] as num).toDouble(),
        amount: (j['amount'] as num).toDouble(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(j['createdAt']),
        side: j['side'] != null ? Side.values.byName(j['side']) : Side.sell,
        direction: j['direction'] != null
            ? ReservationDir.values.byName(j['direction'])
            : (j['kind'] == 'stop' ? ReservationDir.below : ReservationDir.above),
      );
}

class ResetRecord {
  final DateTime resetAt;
  final ClassTier tier;
  final double endingCashUsd;
  final double endingPortfolioUsd;
  ResetRecord(
      {required this.resetAt,
      required this.tier,
      required this.endingCashUsd,
      required this.endingPortfolioUsd});

  Map<String, dynamic> toJson() => {
        'resetAt': resetAt.millisecondsSinceEpoch,
        'tier': tier.name,
        'endingCashUsd': endingCashUsd,
        'endingPortfolioUsd': endingPortfolioUsd,
      };
  factory ResetRecord.fromJson(Map<String, dynamic> j) => ResetRecord(
        resetAt: DateTime.fromMillisecondsSinceEpoch(j['resetAt']),
        tier: tierFromString(j['tier']),
        endingCashUsd: (j['endingCashUsd'] as num).toDouble(),
        endingPortfolioUsd: (j['endingPortfolioUsd'] as num).toDouble(),
      );
}

class Account {
  DateTime createdAt;
  ClassTier tier;
  double cashUsd;
  Map<String, Holding> holdings;
  List<Transaction> transactions;
  List<ResetRecord> resetHistory;
  List<LimitOrder> limits;
  bool lockedInGame;

  Account({
    required this.createdAt,
    required this.tier,
    required this.cashUsd,
    required this.holdings,
    required this.transactions,
    required this.resetHistory,
    required this.limits,
    required this.lockedInGame,
  });

  factory Account.empty(ClassTier tier) => Account(
        createdAt: DateTime.now(),
        tier: tier,
        cashUsd: kStartingBalance[tier]!,
        holdings: {},
        transactions: [],
        resetHistory: [],
        limits: [],
        lockedInGame: false,
      );

  Map<String, dynamic> toJson() => {
        'createdAt': createdAt.millisecondsSinceEpoch,
        'tier': tier.name,
        'cashUsd': cashUsd,
        'holdings': holdings.map((k, v) => MapEntry(k, v.toJson())),
        'transactions': transactions.map((t) => t.toJson()).toList(),
        'resetHistory': resetHistory.map((r) => r.toJson()).toList(),
        'limits': limits.map((l) => l.toJson()).toList(),
        'lockedInGame': lockedInGame,
      };

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        createdAt: DateTime.fromMillisecondsSinceEpoch(j['createdAt']),
        tier: tierFromString(j['tier']),
        cashUsd: (j['cashUsd'] as num).toDouble(),
        holdings: (j['holdings'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, Holding.fromJson(v))),
        transactions: (j['transactions'] as List)
            .map((e) => Transaction.fromJson(e))
            .toList(),
        resetHistory: (j['resetHistory'] as List)
            .map((e) => ResetRecord.fromJson(e))
            .toList(),
        limits: ((j['limits'] as List?) ?? const [])
            .map((e) => LimitOrder.fromJson(e))
            .toList(),
        lockedInGame: j['lockedInGame'] ?? false,
      );
}
