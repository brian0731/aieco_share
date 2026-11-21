import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lifebuoy_chat.dart';
import 'lifebuoy_illustration.dart';
import 'lifebuoy_lightmesh_banner.dart';
import 'lifebuoy_rating.dart';
import 'lifebuoy_search.dart';

part 'lifebuoy_districts.dart';
part 'lifebuoy_exchange.dart';
part 'lifebuoy_lists.dart';
part 'lifebuoy_signin.dart';
part 'lifebuoy_settings.dart';

void main() => runApp(const LifebuoyApp());

typedef Json = Map<String, dynamic>;

class LifebuoyApp extends StatelessWidget {
  const LifebuoyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '社區救生圈',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff006a61)),
      useMaterial3: true,
    ),
    home: const LifebuoyHome(),
  );
}

class LifebuoyHome extends StatefulWidget {
  const LifebuoyHome({super.key});

  @override
  State<LifebuoyHome> createState() => _LifebuoyHomeState();
}

class _LifebuoyHomeState extends State<LifebuoyHome> {
  static const endpoint = String.fromEnvironment(
    'LIFEBUOY_API_URL',
    defaultValue: 'https://lifebuoy.aieco.hk',
  );
  final title = TextEditingController();
  final area = TextEditingController();
  final duration = TextEditingController(text: '30');
  final postSearch = TextEditingController();
  final timeSearch = TextEditingController();
  final exchangeSearch = TextEditingController();
  final random = Random.secure();
  final localAuth = LocalAuthentication();
  final biometricStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions.biometric(
      enforceBiometrics: true,
      requireBiometricsPerOperation: true,
      biometricType: AndroidBiometricType.strongBiometricOnly,
      biometricPromptTitle: '社區救生圈',
      biometricPromptSubtitle: '請驗證裝置生物認證',
      biometricPromptNegativeButton: '取消',
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
      accessControlFlags: [AccessControlFlag.biometryCurrentSet],
    ),
  );
  static final biometricKey =
      'lifebuoy.session.${Uri.encodeComponent(endpoint)}';
  static final biometricPreference = '$biometricKey.enabled';
  bool get biometricPlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  bool biometricSaved = false;
  Json? home;
  Json? draft;
  String? activeToken;
  String kind = 'request';
  String? error;
  bool busy = false;
  int tab = 0;
  String postFilter = 'all';
  _TimeTab timeTab = _TimeTab.services;

  void selectPostFilter(String value) => setState(() => postFilter = value);
  void selectTimeTab(_TimeTab value) => setState(() => timeTab = value);
  void updateSearch() => setState(() {});

  @override
  void initState() {
    super.initState();
    if (biometricPlatform) unawaited(checkBiometricSession());
    unawaited(run(refresh));
  }

  @override
  void dispose() {
    title.dispose();
    area.dispose();
    duration.dispose();
    postSearch.dispose();
    timeSearch.dispose();
    exchangeSearch.dispose();
    super.dispose();
  }

  static final draftPrefix = 'lifebuoy.draft.${Uri.encodeComponent(endpoint)}.';
  String draftKey(String member) =>
      '$draftPrefix${account?['community_id']}.$member';
  Json? get account => home?['account'] as Json?;
  List<Json> list(String key) => (home?[key] as List? ?? []).cast<Json>();

  Future<Json> api(String path, [Json? data]) async {
    final base = Uri.tryParse(endpoint);
    if (base == null ||
        !base.hasAuthority ||
        base.userInfo.isNotEmpty ||
        (base.scheme != 'https' && !(kDebugMode && base.scheme == 'http'))) {
      throw const FormatException('請設定 LIFEBUOY_API_URL');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final url = base.resolve('/api/v1/$path');
      final request = await client.openUrl(data == null ? 'GET' : 'POST', url);
      request.followRedirects = false;
      if (activeToken case final String session) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $session');
      }
      if (data != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(data));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 12));
      final result = jsonDecode(body) as Json;
      if (response.statusCode >= 400) {
        if (response.statusCode == 401 && activeToken != null) {
          if (biometricSaved) await discardInvalidBiometricSession();
          clearSession();
          if (mounted) unawaited(loadPublicBoard());
        }
        throw FormatException(switch (result['statusMessage']) {
          'insufficient_balance' => '付款方可用時間不足，這筆服務尚未入帳。',
          'invalid_token' || 'token_required' => '登入已失效，請重新登入',
          'incorrect_credentials' => '使用者名稱或密碼錯誤',
          'incorrect_current_password' => '現有密碼不正確',
          'member_account_required' => '此功能只適用於會員帳戶',
          'district_conflict' => '暫時無法轉往此區，請稍後再試',
          'retry_transaction' => '資料正在更新，請稍後再試',
          'invalid_username' => '使用者名稱須為 3 至 32 個英文字母、數字或底線',
          'invalid_password' => '密碼須至少 12 個字元，且不得超過 256 位元組',
          'invalid_name' => '請輸入顯示名稱（最多 100 個字元）',
          'username_taken' => '此使用者名稱已被使用',
          'district_required' || 'invalid_district' => '請選擇香港十八區之一',
          'registration_unavailable' => '暫時無法註冊，請稍後重試',
          'try_again_later' => '嘗試次數過多，請稍後再試',
          'minutes_mismatch' => '分鐘數與約定不符',
          'already_matched' => '此服務已有配對',
          'rating_exists' => '你已為這筆紀錄評分。',
          'rating_unavailable' => '這筆紀錄已無法評分。',
          'trade_disputed' => '這筆紀錄正在處理申訴。',
          _ => '操作未完成（${response.statusCode}）',
        });
      }
      return result;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> run(Future<void> Function() work) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException ? e.message : '暫時無法確認結果，請連線後重試',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> refresh() async {
    final current = await api(activeToken == null ? 'board' : 'home');
    if (mounted) setState(() => home = current);
  }

  Future<void> loadPublicBoard() async {
    try {
      final board = await api('board');
      if (mounted && activeToken == null) setState(() => home = board);
    } catch (_) {
      // The session error is already shown by the action that triggered it.
    }
  }

  Future<void> signin() async {
    final session = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _AccountPage(
          api: passwordAuth,
          biometricLogin: biometricSaved ? readBiometricSession : null,
        ),
      ),
    );
    if (session == null || !mounted) return;
    await run(() => openSession(session));
  }

  Future<void> checkBiometricSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(biometricPreference) ?? false;
      if (mounted) setState(() => biometricSaved = saved);
    } on PlatformException {
      // Password login stays available if secure storage is unavailable.
    }
  }

  Future<void> forgetBiometricSession() async {
    if (!biometricPlatform) return;
    await biometricStorage.delete(key: biometricKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(biometricPreference);
    if (mounted) setState(() => biometricSaved = false);
  }

  Future<void> discardInvalidBiometricSession() async {
    try {
      await forgetBiometricSession();
    } on PlatformException {
      if (mounted) setState(() => biometricSaved = false);
    }
  }

  Future<void> enableBiometricSession() async {
    final session = activeToken;
    if (session == null) return;
    try {
      if ((await localAuth.getAvailableBiometrics()).isEmpty) {
        throw const FormatException('請先在手機設定登記指紋或生物認證');
      }
      // Password login with another account must replace the saved session.
      await biometricStorage.write(key: biometricKey, value: session);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(biometricPreference, true);
      if (mounted) setState(() => biometricSaved = true);
    } on PlatformException {
      throw const FormatException('未能啟用生物認證，請檢查手機設定後重試');
    } on LocalAuthException {
      throw const FormatException('未能啟用生物認證，請檢查手機設定後重試');
    }
  }

  Future<String?> readBiometricSession() async {
    try {
      final session = await biometricStorage.read(key: biometricKey);
      if (session != null) return session;
      await discardInvalidBiometricSession();
    } on PlatformException {
      throw const FormatException('未能完成生物認證，請重試或使用密碼登入');
    }
    throw const FormatException('裝置登入憑證已失效，請使用密碼登入');
  }

  Future<Json> passwordAuth(String path, [Json? data]) async {
    final result = await api(path, data);
    if (biometricSaved) await discardInvalidBiometricSession();
    return result;
  }

  Future<void> openSession(String session) async {
    activeToken = session;
    try {
      await refresh();
    } catch (_) {
      activeToken = null;
      rethrow;
    }
    await restoreDraft();
  }

  Future<void> restoreDraft() async {
    final member = account?['id']?.toString();
    if (!mounted || member == null) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(draftKey(member));
    if (saved != null && mounted) {
      final value = jsonDecode(saved) as Json;
      setState(() {
        draft = value;
        kind = value['kind'] as String;
        title.text = value['title'] as String;
        area.text = value['area'] as String;
        duration.text = (value['minutes'] ?? 30).toString();
      });
    }
  }

  void clearSession() {
    if (!mounted) return;
    setState(() {
      activeToken = null;
      home = null;
      draft = null;
      kind = 'request';
      title.clear();
      area.clear();
      duration.text = '30';
    });
  }

  Future<void> signout() async {
    try {
      await api('auth/logout', {});
    } finally {
      clearSession();
      try {
        if (biometricSaved) await forgetBiometricSession();
      } finally {
        await loadPublicBoard();
      }
    }
  }

  Future<void> openUserSettings() async {
    final member = account;
    if (member == null) return;
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _UserSettingsPage(account: member, api: api),
      ),
    );
    if (!mounted || result == null) return;
    if (result == 'profile') {
      await run(() async {
        final oldDistrict = account?['community_id'];
        await refresh();
        if (mounted && oldDistrict != account?['community_id']) {
          setState(() {
            draft = null;
            kind = 'request';
            title.clear();
            area.clear();
            duration.text = '30';
          });
          await restoreDraft();
        }
      });
      return;
    }
    clearSession();
    if (biometricSaved) await discardInvalidBiometricSession();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result == 'delete' ? '帳戶已刪除' : '密碼已更新，請重新登入')),
    );
    await loadPublicBoard();
    if (result == 'delete') {
      final prefs = await SharedPreferences.getInstance();
      final suffix = '.${member['id']}';
      for (final key in prefs.getKeys()) {
        if (key.startsWith(draftPrefix) && key.endsWith(suffix)) {
          await prefs.remove(key);
        }
      }
    }
  }

  String newId() {
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> publish() async {
    if (title.text.trim().isEmpty || area.text.trim().isEmpty) {
      throw const FormatException('請填寫標題及大致區域');
    }
    final minutes = int.tryParse(duration.text);
    if (kind != 'free' && (minutes == null || minutes < 1 || minutes > 1440)) {
      throw const FormatException('請輸入 1 至 1440 的整數分鐘');
    }
    final payload = <String, dynamic>{
      'id': draft?['id'] ?? newId(),
      'kind': kind,
      'title': title.text.trim(),
      'area': area.text.trim(),
      'minutes': kind == 'free' ? null : minutes,
    };
    if (draft != null && jsonEncode(draft) != jsonEncode(payload)) {
      throw const FormatException('請先重送原草稿，或放棄原草稿再刊登');
    }
    final prefs = await SharedPreferences.getInstance();
    final key = draftKey(account!['id'].toString());
    await prefs.setString(key, jsonEncode(payload));
    if (mounted) setState(() => draft = payload);
    await api('posts', payload);
    await prefs.remove(key);
    if (mounted) {
      setState(() {
        draft = null;
        title.clear();
        area.clear();
      });
    }
    await refresh();
  }

  Future<void> discardDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(draftKey(account!['id'].toString()));
    if (mounted) setState(() => draft = null);
  }

  Future<void> mutate(String path, Json data) async {
    await api(path, data);
    await refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('社區救生圈'),
      actions: [
        if (tab != 3)
          IconButton(
            tooltip: '更新',
            onPressed: busy ? null : () => run(refresh),
            icon: const Icon(Icons.refresh),
          ),
        if (account == null)
          IconButton(
            tooltip: '登入或註冊',
            onPressed: busy ? null : signin,
            icon: const Icon(Icons.person_outline),
          )
        else
          PopupMenuButton<String>(
            tooltip: '用戶設定',
            icon: const Icon(Icons.manage_accounts_outlined),
            enabled: !busy,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'settings', child: Text('用戶設定')),
              if (biometricPlatform)
                PopupMenuItem(
                  value: biometricSaved ? 'disable' : 'enable',
                  child: Text(biometricSaved ? '停用指紋／生物認證登入' : '啟用指紋／生物認證登入'),
                ),
              if (biometricSaved)
                const PopupMenuItem(value: 'lock', child: Text('鎖定帳戶')),
              const PopupMenuItem(value: 'logout', child: Text('登出')),
            ],
            onSelected: (action) => action == 'settings'
                ? openUserSettings()
                : run(switch (action) {
                    'enable' => enableBiometricSession,
                    'disable' => forgetBiometricSession,
                    'lock' => () async {
                      clearSession();
                      await loadPublicBoard();
                    },
                    _ => signout,
                  }),
          ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: tab,
              children: [
                feed(),
                timeBank(),
                exchangeBoard(),
                LifebuoyChat(active: tab == 3),
              ],
            ),
          ),
        ],
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (value) {
        FocusScope.of(context).unfocus();
        setState(() => tab = value);
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.volunteer_activism_outlined),
          label: '社區互助',
        ),
        NavigationDestination(icon: Icon(Icons.schedule), label: '時間銀行'),
        NavigationDestination(icon: Icon(Icons.swap_horiz), label: '交換'),
        NavigationDestination(
          icon: Icon(Icons.chat_bubble_outline),
          label: '光網聊天',
        ),
      ],
    ),
  );
}
