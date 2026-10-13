part of '../main.dart';

// Safe reads that still work when offline.

// Offline-safe read helpers
const Duration _kNetworkTimeout = Duration(seconds: 2);
// Web: don't make screens wait for the server. After this time, show the cache
// (the server read keeps running and refreshes it).
const Duration _kReadTimeout =
    kIsWeb ? Duration(milliseconds: 900) : _kNetworkTimeout;

// Wi-Fi connected doesn't always mean the internet works. _netState() adds a quick
// DNS check (cached for a few seconds). When offline, go straight to the cache
// instead of waiting for a timeout, which caused endless loading.
enum _Net { none, unreachable, reachable }

_Net? _netCache;
DateTime _netCacheAt = DateTime.fromMillisecondsSinceEpoch(0);

void resetNetCache() {
  _netCache = null;
}

Future<_Net> _netState() async {
  bool linked = true;
  try {
    final r = await Connectivity().checkConnectivity();
    linked = !r.contains(ConnectivityResult.none);
  } catch (_) {}
  if (!linked) {
    _netCache = _Net.none;
    _netCacheAt = DateTime.now();
    return _Net.none;
  }
  final cached = _netCache;
  if (cached != null && cached != _Net.none) {
    final ttl = cached == _Net.reachable
        ? const Duration(seconds: 10)
        : const Duration(seconds: 4);
    if (DateTime.now().difference(_netCacheAt) < ttl) return cached;
  }
  // InternetAddress.lookup isn't available on web; the check above is enough.
  if (kIsWeb) {
    _netCache = _Net.reachable;
    _netCacheAt = DateTime.now();
    return _Net.reachable;
  }
  _Net result;
  try {
    final res = await InternetAddress.lookup('firestore.googleapis.com')
        .timeout(const Duration(seconds: 3));
    result = res.isNotEmpty ? _Net.reachable : _Net.unreachable;
  } catch (_) {
    result = _Net.unreachable;
  }
  _netCache = result;
  _netCacheAt = DateTime.now();
  return result;
}

Future<bool> _isOnline() async {
  try {
    final r = await Connectivity().checkConnectivity();
    return !r.contains(ConnectivityResult.none);
  } catch (_) {
    return true;
  }
}

Future<DocumentSnapshot<Map<String, dynamic>>> safeGetDoc(
    DocumentReference<Map<String, dynamic>> ref) async {
  const cacheOnly = GetOptions(source: Source.cache);
  final net = await _netState();
  if (net == _Net.reachable) {
    final server = ref.get();
    server.ignore();
    try {
      return await server.timeout(_kReadTimeout);
    } catch (_) {}
    try {
      return await ref.get(cacheOnly);
    } catch (_) {
      // Not cached yet: give the server a little more time.
      return server.timeout(const Duration(seconds: 8));
    }
  }
  try {
    final c = await ref.get(cacheOnly);
    if (c.exists || net == _Net.none) return c;
  } catch (_) {
    if (net == _Net.none) rethrow;
  }
  return ref.get().timeout(_kNetworkTimeout);
}

Future<DocumentSnapshot<Map<String, dynamic>>?> safeGetDocOrNull(
    DocumentReference<Map<String, dynamic>> ref) async {
  try {
    return await safeGetDoc(ref);
  } catch (_) {
    return null;
  }
}

Future<QuerySnapshot<Map<String, dynamic>>> safeGetQuery(
    Query<Map<String, dynamic>> query) async {
  const cacheOnly = GetOptions(source: Source.cache);
  final net = await _netState();
  if (net == _Net.reachable) {
    final server = query.get();
    server.ignore();
    try {
      return await server.timeout(_kReadTimeout);
    } catch (_) {}
    final cached = await query.get(cacheOnly);
    if (cached.docs.isNotEmpty) return cached;
    // Nothing cached: wait a bit longer for the server instead of showing an empty list.
    try {
      return await server.timeout(const Duration(seconds: 8));
    } catch (_) {
      return cached;
    }
  }
  final cached = await query.get(cacheOnly);
  if (cached.docs.isNotEmpty || net == _Net.none) return cached;
  try {
    return await query.get().timeout(_kNetworkTimeout);
  } catch (_) {
    return cached;
  }
}

class _QRes {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final bool fromCache;
  const _QRes(this.docs, this.fromCache);
}

// Never throws. On any failure it returns an empty result marked as from cache.
Future<_QRes> _safeQuery(Query<Map<String, dynamic>> query) async {
  try {
    final snap = await safeGetQuery(query);
    return _QRes(snap.docs, snap.metadata.isFromCache);
  } catch (_) {
    return const _QRes([], true);
  }
}

// Cache-first live query for StreamBuilders: device cache first, then live updates.
Stream<QuerySnapshot<Map<String, dynamic>>> liveQuery(
    Query<Map<String, dynamic>> q) {
  late final StreamController<QuerySnapshot<Map<String, dynamic>>> ctrl;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? sub;
  bool gotLive = false;
  bool cancelled = false;
  ctrl = StreamController<QuerySnapshot<Map<String, dynamic>>>(
    onListen: () {
      sub = q.snapshots().listen(
        (snap) {
          gotLive = true;
          if (!cancelled) ctrl.add(snap);
        },
        onError: (Object e, StackTrace st) {
          if (!cancelled) ctrl.addError(e, st);
        },
      );
      unawaited(() async {
        try {
          final cached = await q.get(const GetOptions(source: Source.cache));
          if (gotLive || cancelled) return;
          if (cached.docs.isNotEmpty) {
            ctrl.add(cached);
            return;
          }
          // Empty cache: give the live stream a moment, then show the empty result.
          await Future.delayed(const Duration(milliseconds: 1500));
          if (!gotLive && !cancelled) ctrl.add(cached);
        } catch (_) {}
      }());
    },
    onCancel: () async {
      cancelled = true;
      await sub?.cancel();
    },
  );
  return ctrl.stream;
}
