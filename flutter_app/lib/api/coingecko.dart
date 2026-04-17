// Binance public market data API (free, no auth, real-time).
// File kept as coingecko.dart for import compatibility.
//
// Rate-limit strategy:
//   * REST snapshot (`fetchMarkets`)   — weight 40, throttled to 1/min + cached.
//   * Klines (`fetchHistory`)          — weight 2, per-(symbol,range) cached.
//   * Honors HTTP 429/418 `Retry-After` with exponential backoff.
//   * All REST calls go through a single shared limiter.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

const String kRestBase = 'https://api.binance.com';
const String kWsBase   = 'wss://stream.binance.com:9443';

// ---------- Rate limiter ----------

class _RateLimiter {
  // Binance: 6000 request-weight/min per IP on spot REST.
  // We stay well below — aim for ~30 weight/sec budget locally.
  static const int _capacity = 120;            // max burst of "weight"
  static const int _refillPerSec = 30;         // weight replenished per second
  double _tokens = _capacity.toDouble();
  DateTime _last = DateTime.now();
  DateTime? _blockedUntil;                     // set when 429/418 hits

  Future<void> consume(int weight) async {
    while (true) {
      if (_blockedUntil != null && DateTime.now().isBefore(_blockedUntil!)) {
        final wait = _blockedUntil!.difference(DateTime.now());
        await Future.delayed(wait + const Duration(milliseconds: 50));
      }
      final now = DateTime.now();
      final elapsed = now.difference(_last).inMilliseconds / 1000.0;
      _tokens = min(_capacity.toDouble(), _tokens + elapsed * _refillPerSec);
      _last = now;
      if (_tokens >= weight) {
        _tokens -= weight;
        return;
      }
      final need = weight - _tokens;
      final waitMs = (need / _refillPerSec * 1000).ceil() + 20;
      await Future.delayed(Duration(milliseconds: waitMs));
    }
  }

  void penalize(Duration d) {
    final until = DateTime.now().add(d);
    if (_blockedUntil == null || until.isAfter(_blockedUntil!)) {
      _blockedUntil = until;
    }
  }
}

final _limiter = _RateLimiter();

Future<http.Response> _getWithBackoff(Uri url, {int weight = 1}) async {
  for (int attempt = 0; attempt < 5; attempt++) {
    await _limiter.consume(weight);
    http.Response r;
    try {
      r = await http.get(url).timeout(const Duration(seconds: 15));
    } catch (e) {
      if (attempt == 4) rethrow;
      await Future.delayed(Duration(milliseconds: 500 * (1 << attempt)));
      continue;
    }
    if (r.statusCode == 429 || r.statusCode == 418) {
      final hdr = r.headers['retry-after'];
      final secs = int.tryParse(hdr ?? '') ?? (1 << attempt);
      _limiter.penalize(Duration(seconds: secs));
      continue;
    }
    if (r.statusCode >= 500 && r.statusCode < 600) {
      await Future.delayed(Duration(milliseconds: 500 * (1 << attempt)));
      continue;
    }
    return r;
  }
  throw Exception('rate-limited or unreachable');
}

// ---------- MarketRow ----------

class MarketRow {
  final String id;        // BTCUSDT
  final String symbol;    // BTC
  final String name;      // BTC (Binance has no full names)
  double currentPrice;
  double? change24hPct;
  double totalVolume;     // quote volume (USDT)
  int? marketCapRank;
  MarketRow({
    required this.id,
    required this.symbol,
    required this.name,
    required this.currentPrice,
    required this.change24hPct,
    required this.totalVolume,
    this.marketCapRank,
  });
}

// ---------- fetchMarkets (snapshot + throttled cache) ----------

List<MarketRow>? _marketCache;
DateTime? _marketCacheAt;
Future<List<MarketRow>>? _inflightMarkets;

Future<List<MarketRow>> fetchMarkets({int pages = 0, bool force = false}) async {
  // Cache for 60s — the WebSocket handles real-time updates, so we only need
  // REST for the initial list of symbols.
  final fresh = _marketCacheAt != null &&
      DateTime.now().difference(_marketCacheAt!).inSeconds < 60;
  if (!force && _marketCache != null && fresh) return _marketCache!;
  if (_inflightMarkets != null) return _inflightMarkets!;

  _inflightMarkets = () async {
    try {
      // /ticker/24hr without symbol = weight 40.
      final r = await _getWithBackoff(
          Uri.parse('$kRestBase/api/v3/ticker/24hr'), weight: 40);
      if (r.statusCode != 200) throw Exception('markets ${r.statusCode}');
      final List data = jsonDecode(r.body);
      final rows = <MarketRow>[];
      for (final j in data) {
        final s = j['symbol'] as String;
        if (!s.endsWith('USDT')) continue;
        final base = s.substring(0, s.length - 4);
        if (base.endsWith('UP') || base.endsWith('DOWN') ||
            base.endsWith('BULL') || base.endsWith('BEAR')) continue;
        final last = double.tryParse(j['lastPrice']?.toString() ?? '') ?? 0;
        if (last <= 0) continue;
        rows.add(MarketRow(
          id: s,
          symbol: base,
          name: base,
          currentPrice: last,
          change24hPct: double.tryParse(j['priceChangePercent']?.toString() ?? ''),
          totalVolume: double.tryParse(j['quoteVolume']?.toString() ?? '') ?? 0,
        ));
      }
      rows.sort((a, b) => b.totalVolume.compareTo(a.totalVolume));
      for (int i = 0; i < rows.length; i++) {
        rows[i].marketCapRank = i + 1;
      }
      _marketCache = rows;
      _marketCacheAt = DateTime.now();
      return rows;
    } finally {
      _inflightMarkets = null;
    }
  }();
  return _inflightMarkets!;
}

// ---------- WebSocket stream ----------

class TickerUpdate {
  final String id;
  final double price;
  final double? change24hPct;
  final double totalVolume;
  const TickerUpdate(this.id, this.price, this.change24hPct, this.totalVolume);
}

class BinanceStream {
  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  bool _closed = false;
  Timer? _reconnect;
  int _backoff = 1;
  final void Function(List<TickerUpdate>) onBatch;
  final void Function(Object err)? onError;

  BinanceStream({required this.onBatch, this.onError});

  void connect() {
    if (_closed) return;
    try {
      _ch = WebSocketChannel.connect(Uri.parse('$kWsBase/ws/!ticker@arr'));
      _sub = _ch!.stream.listen(
        (raw) {
          _backoff = 1;
          try {
            final dynamic parsed = jsonDecode(raw as String);
            if (parsed is! List) return;
            final out = <TickerUpdate>[];
            for (final e in parsed) {
              final s = e['s'] as String? ?? '';
              if (!s.endsWith('USDT')) continue;
              final p = double.tryParse(e['c']?.toString() ?? '') ?? 0;
              if (p <= 0) continue;
              out.add(TickerUpdate(
                s,
                p,
                double.tryParse(e['P']?.toString() ?? ''),
                double.tryParse(e['q']?.toString() ?? '') ?? 0,
              ));
            }
            if (out.isNotEmpty) onBatch(out);
          } catch (_) {}
        },
        onError: (e) {
          onError?.call(e);
          _scheduleReconnect();
        },
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
    } catch (e) {
      onError?.call(e);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_closed) return;
    _reconnect?.cancel();
    final delay = Duration(seconds: _backoff);
    _backoff = min(_backoff * 2, 30); // cap at 30s
    _reconnect = Timer(delay, () {
      _sub?.cancel();
      _ch?.sink.close();
      connect();
    });
  }

  void close() {
    _closed = true;
    _reconnect?.cancel();
    _sub?.cancel();
    _ch?.sink.close();
  }
}

// ---------- Klines (historical chart) with per-range cache ----------

class _KlineCacheEntry {
  final List<(DateTime, double)> data;
  final DateTime at;
  _KlineCacheEntry(this.data, this.at);
}

final Map<String, _KlineCacheEntry> _klineCache = {};
final Map<String, Future<List<(DateTime, double)>>> _klineInflight = {};

/// How long a given range is considered fresh before refetching.
Duration _klineTtl(String range) {
  switch (range) {
    case '1d':  return const Duration(seconds: 60);
    case '7d':  return const Duration(minutes: 5);
    case '30d': return const Duration(minutes: 15);
    case '90d': return const Duration(hours: 1);
    case '1y':  return const Duration(hours: 6);
    case 'max': return const Duration(hours: 12);
    default:    return const Duration(minutes: 5);
  }
}

Future<List<(DateTime, double)>> fetchHistory(String coinId, Object range) async {
  final key = '$coinId|$range';
  final rangeStr = range.toString();
  final cached = _klineCache[key];
  if (cached != null &&
      DateTime.now().difference(cached.at) < _klineTtl(rangeStr)) {
    return cached.data;
  }
  if (_klineInflight[key] != null) return _klineInflight[key]!;

  _klineInflight[key] = () async {
    try {
      final mapping = <String, (String, int)>{
        '1d':  ('15m', 96),
        '7d':  ('1h',  168),
        '30d': ('4h',  180),
        '90d': ('12h', 180),
        '1y':  ('1d',  365),
        'max': ('1w',  1000),
      };
      final sel = mapping[rangeStr] ?? mapping['7d']!;
      final url = Uri.parse(
          '$kRestBase/api/v3/klines?symbol=$coinId&interval=${sel.$1}&limit=${sel.$2}');
      final r = await _getWithBackoff(url, weight: 2);
      if (r.statusCode != 200) throw Exception('klines ${r.statusCode}');
      final List data = jsonDecode(r.body);
      final out = <(DateTime, double)>[
        for (final k in data)
          (
            DateTime.fromMillisecondsSinceEpoch((k[6] as num).toInt()),
            double.tryParse(k[4]?.toString() ?? '') ?? 0,
          ),
      ];
      _klineCache[key] = _KlineCacheEntry(out, DateTime.now());
      return out;
    } finally {
      _klineInflight.remove(key);
    }
  }();
  return _klineInflight[key]!;
}
