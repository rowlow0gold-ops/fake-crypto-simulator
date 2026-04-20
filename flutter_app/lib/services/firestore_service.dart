import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/models.dart';
import 'auth_service.dart';

class FirestoreService {
  static final _db = FirebaseFirestore.instance;

  // ---------- User profile / portfolio sync ----------

  static DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  /// Save the full account + profile to Firestore.
  static Future<void> saveProfile({
    required String uid,
    required Account account,
    String? displayName,
    String? email,
    String? photoUrl,
    bool pushEnabled = false,
  }) async {
    await _userDoc(uid).set({
      'displayName': displayName,
      'email': email,
      'photoUrl': photoUrl,
      'pushEnabled': pushEnabled,
      'portfolio': account.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Fetch the cloud account. Returns null if no cloud data exists.
  static Future<Account?> fetchCloudAccount(String uid) async {
    final snap = await _userDoc(uid).get();
    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null || data['portfolio'] == null) return null;
    try {
      return Account.fromJson(data['portfolio']);
    } catch (_) {
      return null;
    }
  }

  /// Check if cloud data exists for this user.
  static Future<bool> hasCloudData(String uid) async {
    final snap = await _userDoc(uid).get();
    return snap.exists && snap.data()?['portfolio'] != null;
  }

  /// Update push notification preference.
  static Future<void> setPushEnabled(String uid, bool enabled) async {
    await _userDoc(uid).set({'pushEnabled': enabled}, SetOptions(merge: true));
  }

  static Future<bool> getPushEnabled(String uid) async {
    final snap = await _userDoc(uid).get();
    return snap.data()?['pushEnabled'] ?? false;
  }

  /// Save FCM token for push notifications.
  static Future<void> saveFcmToken(String uid, String token) async {
    await _userDoc(uid).set({'fcmToken': token}, SetOptions(merge: true));
  }

  // ---------- Rooms / Games ----------

  static CollectionReference<Map<String, dynamic>> get _rooms =>
      _db.collection('rooms');

  /// Create a new game room, returns the room code.
  static Future<String> createRoom({
    required String code,
    required String creatorUid,
    required String creatorName,
    required String? creatorPhoto,
    required String mode, // 'original' or 'specials'
    required double specialsCash, // only used if mode == 'specials'
    required String classMode, // 'random', 'choose', 'vote'
    required int timeLimitMinutes,
    required String visibility, // 'total', 'top3', 'full', 'hidden'
    required Account? creatorAccount, // cloned for 'original' mode
    required ClassTier creatorClass, // for 'choose' or 'random' mode
  }) async {
    final gameWallet = mode == 'original' && creatorAccount != null
        ? creatorAccount.toJson()
        : Account.empty(creatorClass).toJson();

    await _rooms.doc(code).set({
      'code': code,
      'createdBy': creatorUid,
      'createdAt': FieldValue.serverTimestamp(),
      'mode': mode,
      'specialsCash': specialsCash,
      'classMode': classMode,
      'timeLimitMinutes': timeLimitMinutes,
      'visibility': visibility,
      'status': 'lobby',
      'startedAt': null,
      'endsAt': null,
      'members': {
        creatorUid: {
          'displayName': creatorName,
          'photoUrl': creatorPhoto,
          'class': creatorClass.name,
          'gameWallet': gameWallet,
          'portfolioValue': kStartingBalance[creatorClass] ?? 10000,
          'joinedAt': DateTime.now().millisecondsSinceEpoch,
        },
      },
      'votes': {},
    });
    return code;
  }

  /// Join an existing room.
  static Future<Map<String, dynamic>?> joinRoom({
    required String code,
    required String uid,
    required String displayName,
    required String? photoUrl,
    required Account? userAccount, // for 'original' mode
  }) async {
    final doc = await _rooms.doc(code).get();
    if (!doc.exists) return null;
    final data = doc.data()!;

    final mode = data['mode'] as String;
    final classMode = data['classMode'] as String;
    final status = data['status'] as String;

    if (status == 'ended') return null;

    // Determine class
    ClassTier tier;
    if (classMode == 'random') {
      final tiers = ClassTier.values;
      tier = tiers[DateTime.now().microsecond % tiers.length];
    } else if (classMode == 'choose') {
      // Default to middle, user picks later or we pass it in
      tier = ClassTier.middle;
    } else {
      // Vote mode — start as middle, will be reassigned after votes
      tier = ClassTier.middle;
    }

    final gameWallet = mode == 'original' && userAccount != null
        ? userAccount.toJson()
        : Account.empty(tier).toJson();

    final memberData = {
      'displayName': displayName,
      'photoUrl': photoUrl,
      'class': tier.name,
      'gameWallet': gameWallet,
      'portfolioValue': mode == 'original' ? 0.0 : kStartingBalance[tier],
      'joinedAt': DateTime.now().millisecondsSinceEpoch,
    };

    await _rooms.doc(code).update({
      'members.$uid': memberData,
    });
    return data;
  }

  /// Leave a room. If no members remain, delete it.
  static Future<void> leaveRoom(String code, String uid) async {
    final doc = await _rooms.doc(code).get();
    if (!doc.exists) return;
    final members = Map<String, dynamic>.from(doc.data()!['members'] ?? {});
    members.remove(uid);

    if (members.isEmpty) {
      await _rooms.doc(code).delete();
    } else {
      await _rooms.doc(code).update({
        'members.$uid': FieldValue.delete(),
      });
    }
  }

  /// Listen to room changes in real-time.
  static Stream<DocumentSnapshot<Map<String, dynamic>>> roomStream(String code) =>
      _rooms.doc(code).snapshots();

  /// Update a member's game wallet + portfolio value.
  static Future<void> updateMemberWallet({
    required String code,
    required String uid,
    required Account gameWallet,
    required double portfolioValue,
  }) async {
    await _rooms.doc(code).update({
      'members.$uid.gameWallet': gameWallet.toJson(),
      'members.$uid.portfolioValue': portfolioValue,
    });
  }

  /// Submit a class vote for another player.
  static Future<void> submitVote({
    required String code,
    required String voterUid,
    required String targetUid,
    required ClassTier tier,
  }) async {
    await _rooms.doc(code).update({
      'votes.$voterUid.$targetUid': tier.name,
    });
  }

  /// Start the game (transition from lobby to active).
  static Future<void> startGame(String code, int timeLimitMinutes) async {
    final now = DateTime.now();
    final end = now.add(Duration(minutes: timeLimitMinutes));
    await _rooms.doc(code).update({
      'status': 'active',
      'startedAt': Timestamp.fromDate(now),
      'endsAt': Timestamp.fromDate(end),
    });
  }

  /// End the game.
  static Future<void> endGame(String code) async {
    await _rooms.doc(code).update({'status': 'ended'});
  }

  /// Get room data once.
  static Future<Map<String, dynamic>?> getRoom(String code) async {
    final doc = await _rooms.doc(code).get();
    return doc.data();
  }

  // ---------- Room chat ----------

  static CollectionReference<Map<String, dynamic>> _chatCol(String code) =>
      _rooms.doc(code).collection('chat');

  static Future<void> sendMessage({
    required String code,
    required String uid,
    required String displayName,
    required String? photoUrl,
    required String text,
  }) async {
    await _chatCol(code).add({
      'uid': uid,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> chatStream(String code) =>
      _chatCol(code)
          .orderBy('createdAt', descending: false)
          .limitToLast(100)
          .snapshots();

  // ---------- Price alerts ----------

  static CollectionReference<Map<String, dynamic>> get _alerts =>
      _db.collection('priceAlerts');

  static Future<void> addPriceAlert({
    required String uid,
    required String coinId,
    required String symbol,
    required double targetPrice,
    required String direction, // 'above' or 'below'
  }) async {
    await _alerts.add({
      'uid': uid,
      'coinId': coinId,
      'symbol': symbol,
      'targetPrice': targetPrice,
      'direction': direction,
      'fired': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<List<Map<String, dynamic>>> getPriceAlerts(String uid) async {
    final snap = await _alerts
        .where('uid', isEqualTo: uid)
        .where('fired', isEqualTo: false)
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  static Future<void> deletePriceAlert(String alertId) async {
    await _alerts.doc(alertId).delete();
  }

  static Future<void> firePriceAlert(String alertId) async {
    await _alerts.doc(alertId).update({'fired': true});
  }
}
