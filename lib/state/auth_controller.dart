import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/qc_socket.dart';
import '../config.dart';
import '../crypto/key_storage.dart';
import '../crypto/qc_crypto.dart';
import '../models/models.dart';

class AuthController extends ChangeNotifier {
  AuthController({required this.storage, required this.socket});

  final KeyStorage storage;
  final QcSocket socket;

  late ApiClient api;
  QcUser? user;
  List<KeyPairHex>? lastGeneratedKeySet;
  String? error;
  bool loading = false;
  bool ready = false;
  bool hasLocalKeyring = false;
  String? pending2faTempToken;
  bool pending2faRememberMe = true;

  /// Called whenever the realtime socket is (re)connected so chat can re-bind listeners.
  VoidCallback? onSocketConnected;

  String get apiBase => storage.getApiBase() ?? AppConfig.defaultApiBase;

  Future<void> bootstrap() async {
    api = ApiClient(baseUrl: AppConfig.apiUrl(apiBase), storage: storage);
    final stored = storage.getStoredUser();
    final token = storage.getToken();

    // Always unlock the root gate first — never leave a black/native splash
    // waiting on secure-storage or network.
    if (stored != null && token != null) {
      try {
        user = QcUser.fromJson(stored);
      } catch (e, st) {
        debugPrint('bootstrap: cached user corrupt, clearing session: $e\n$st');
        storage.clearSession();
        user = null;
      }
    }
    ready = true;
    notifyListeners();

    if (user == null || token == null) return;

    // Secure storage can hang on slow emulators — bound it so UI stays alive.
    try {
      await _refreshKeyringFlag().timeout(const Duration(seconds: 3));
      notifyListeners();
    } catch (_) {
      hasLocalKeyring = false;
      notifyListeners();
    }

    try {
      final data = await api.me().timeout(const Duration(seconds: 8));
      final fresh = data['user'] as Map<String, dynamic>? ?? data;
      final nextToken = data['token'] as String? ?? token;
      user = QcUser.fromJson(fresh);
      await storage.saveSession(nextToken, user!.toJson(), storage.getSessionId());
      try {
        await _refreshKeyringFlag().timeout(const Duration(seconds: 3));
      } catch (_) {}
      _connectSocket(nextToken);
      notifyListeners();
    } on ApiException catch (e) {
      if (e.status == 401) {
        await logout();
      } else {
        _connectSocket(token);
      }
    } catch (_) {
      // offline / timeout — keep cached session
      _connectSocket(token);
    }
  }

  Future<void> setApiBase(String url) async {
    await storage.setApiBase(url);
    api.baseUrl = AppConfig.apiUrl(url);
    notifyListeners();
  }

  Future<void> _refreshKeyringFlag() async {
    final u = user;
    if (u == null) {
      hasLocalKeyring = false;
      return;
    }
    if (u.publicKeys.isNotEmpty) {
      hasLocalKeyring = await storage.keyringMatchesPublishedKeys(u.id, u.publicKeys);
    } else {
      hasLocalKeyring = await storage.hasKeyring(u.id);
    }
  }

  void _connectSocket(String token) {
    final url = AppConfig.signalUrl(apiBase);
    if (url.isEmpty) return;
    socket.connect(url: url, token: token);
  }

  Future<bool> register({
    required String username,
    required String email,
    required String password,
  }) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final keySet = generateKeySet();
      lastGeneratedKeySet = keySet;
      final data = await api.register(
        username: username,
        email: email,
        password: password,
        publicKeys: keySet.map((k) => k.publicKey).toList(),
      );
      final token = data['token'] as String;
      final newUser = QcUser.fromJson(data['user'] as Map<String, dynamic>);
      await storage.addKeySetToRing(newUser.id, keySet);
      await storage.saveSession(token, newUser.toJson(), data['sessionId'] as String?);
      user = newUser;
      hasLocalKeyring = true;
      _connectSocket(token);
      return true;
    } on ApiException catch (e) {
      error = _friendlyRegister(e);
      lastGeneratedKeySet = null;
      return false;
    } catch (e) {
      error = 'Network error: cannot reach the QuantumChat server.';
      lastGeneratedKeySet = null;
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> login({
    required String email,
    required String password,
    bool rememberMe = true,
  }) async {
    loading = true;
    error = null;
    pending2faTempToken = null;
    notifyListeners();
    try {
      final data = await api.login(
        email: email,
        password: password,
        deviceLabel: AppConfig.deviceLabel(),
        rememberMe: rememberMe,
      );
      if (data['requires2fa'] == true) {
        pending2faTempToken = data['tempToken'] as String?;
        pending2faRememberMe = data['rememberMe'] != false;
        return false;
      }
      await _acceptSession(data);
      return true;
    } on ApiException catch (e) {
      error = _friendlyLogin(e);
      return false;
    } catch (_) {
      error = 'Network error: cannot reach the QuantumChat server.';
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> verify2fa(String code) async {
    final temp = pending2faTempToken;
    if (temp == null) return false;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final data = await api.verify2fa(
        tempToken: temp,
        token: code,
        deviceLabel: AppConfig.deviceLabel(),
        rememberMe: pending2faRememberMe,
      );
      pending2faTempToken = null;
      await _acceptSession(data);
      return true;
    } on ApiException catch (e) {
      error = e.message;
      return false;
    } catch (_) {
      error = 'Network error: cannot reach the QuantumChat server.';
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _acceptSession(Map<String, dynamic> data) async {
    final token = data['token'] as String;
    final loggedIn = QcUser.fromJson(data['user'] as Map<String, dynamic>);
    final previous = storage.getStoredUser();
    if (previous != null && '${previous['id']}' != loggedIn.id) {
      await storage.clearKeyring('${previous['id']}');
    }
    await storage.saveSession(token, loggedIn.toJson(), data['sessionId'] as String?);
    user = loggedIn;
    await _refreshKeyringFlag();
    _connectSocket(token);
  }

  Future<bool> importKeys(List<String> secretKeys) async {
    final u = user;
    if (u == null) throw StateError('Not authenticated');
    if (secretKeys.length != keySetSize) {
      throw ApiException('Expected $keySetSize keys in the file, found ${secretKeys.length}');
    }
    final data = await api.me();
    final fresh = QcUser.fromJson(data['user'] as Map<String, dynamic>? ?? data);
    final accountKeys = fresh.publicKeys.map((k) => k.toLowerCase()).toSet();
    final keySet = secretKeys.map((sk) {
      final pub = derivePublicKey(sk);
      return KeyPairHex(publicKey: pub, secretKey: sk);
    }).toList();
    final unmatched = keySet.where((k) => !accountKeys.contains(k.publicKey.toLowerCase())).toList();
    if (unmatched.isNotEmpty) {
      throw ApiException(
        "These keys don't match this account's current public keys — wrong file, or keys were regenerated since it was saved",
      );
    }
    await storage.addKeySetToRing(fresh.id, keySet);
    user = fresh;
    await storage.saveSession(storage.getToken()!, fresh.toJson());
    hasLocalKeyring = true;
    notifyListeners();
    return true;
  }

  Future<List<KeyPairHex>> regenerateKeys() async {
    final u = user;
    if (u == null) throw StateError('Not authenticated');
    final keySet = generateKeySet();
    await storage.addKeySetToRing(u.id, keySet);
    final updated = await api.updatePublicKeys(keySet.map((k) => k.publicKey).toList());
    user = updated;
    lastGeneratedKeySet = keySet;
    await storage.saveSession(storage.getToken()!, updated.toJson());
    hasLocalKeyring = true;
    notifyListeners();
    return keySet;
  }

  Future<void> logout() async {
    storage.clearSession();
    socket.disconnect();
    user = null;
    hasLocalKeyring = false;
    lastGeneratedKeySet = null;
    pending2faTempToken = null;
    notifyListeners();
  }

  void updateUser(QcUser next) {
    user = next;
    storage.saveSession(storage.getToken() ?? '', next.toJson());
    notifyListeners();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  void cancel2fa() {
    pending2faTempToken = null;
    notifyListeners();
  }

  String _friendlyLogin(ApiException e) {
    if (e.status == 429) {
      return "You've made too many attempts. Take a breather and try again in a minute.";
    }
    if (e.status == 401 || e.message.toLowerCase().contains('invalid email or password')) {
      return "We couldn't find an account matching those credentials.";
    }
    if (e.status != null && e.status! >= 500) {
      return 'Our servers are experiencing an issue. Please try again in a few moments.';
    }
    return e.message;
  }

  String _friendlyRegister(ApiException e) {
    if (e.status == 429) {
      return "You've made too many attempts. Take a breather and try again in a minute.";
    }
    if (e.status == 409 || e.message.toLowerCase().contains('already in use')) {
      return 'That username or email is already associated with an account.';
    }
    if (e.message.toLowerCase().contains('password must be at least 8')) {
      return 'Your password must be at least 8 characters long.';
    }
    return e.message;
  }
}
