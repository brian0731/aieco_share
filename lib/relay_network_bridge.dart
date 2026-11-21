import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// A single active phone can join two otherwise independent broadcast relays.
/// Both sockets are separate from the phone's normal chat connection.
class RelayNetworkBridge extends ChangeNotifier {
  RelayNetworkBridge({
    required this.localRelayUrl,
    this.onConnected,
    this.forwardPacket,
    this.retryDelay = const Duration(seconds: 5),
    this.chatReceiptTimeout = const Duration(seconds: 1),
    Future<WebSocket> Function(String)? connect,
  }) : _connect = connect ?? WebSocket.connect;

  final String localRelayUrl;
  final VoidCallback? onConnected;
  final bool Function(Map<String, dynamic>)? forwardPacket;
  final Duration retryDelay;
  final Duration chatReceiptTimeout;
  final Future<WebSocket> Function(String) _connect;
  final String _id =
      'bridge-${DateTime.now().microsecondsSinceEpoch}-'
      '${Random.secure().nextInt(1 << 32)}';
  final List<WebSocket?> _sockets = [null, null];
  final List<bool> _connecting = [false, false];
  final List<Timer?> _retries = [null, null];
  final LinkedHashMap<String, DateTime> _seen = LinkedHashMap();
  final _pendingChat = <LinkedHashMap<String, _PendingBridgedChat>>[
    LinkedHashMap(),
    LinkedHashMap(),
  ];
  final List<Timer?> _chatRetries = [null, null];
  static const _pathKey = '_lightBridgePath';
  static const _receiptKey = '_lightBridgeReceipt';
  static const _receiptKind = 'aieco.light.chat.bridge-ack.v1';
  static const _maxBytes = 64 * 1024;
  static const _maxHops = 8;
  static const _maxSeen = 1024;
  static const _maxPendingChat = 64;
  static const _maxChatAttempts = 4;
  static const _chatKind = 'aieco.light.chat.v1';
  static const _retention = Duration(minutes: 2);
  static const _kinds = {
    'aieco.light.hello.v1',
    'aieco.light.bye.v1',
    _chatKind,
    'aieco.light.room.v1',
    'aieco.light.location.v1',
    'aieco.light.activity.v1',
    'aieco.light.help.v1',
    'aieco.light.supply.v1',
    'aieco.light.credit.v1',
    'aieco.light.admin.v1',
  };
  int _generation = 0;
  bool _disposed = false;
  bool _active = false;
  String? _remoteRelayUrl;
  String? _error;

  bool get active => _active;
  bool get connected =>
      _active &&
      _sockets.every((socket) => socket?.readyState == WebSocket.open);
  String? get remoteRelayUrl => _remoteRelayUrl;
  String? get error => _error;
  String get connectionCode => codeFor(localRelayUrl);

  /// Written to the same relay by an app that accepted a bridged chat.
  static Map<String, Object?>? chatReceiptFor(Map<String, dynamic> packet) {
    final bridgeId = packet[_receiptKey];
    final path = packet[_pathKey];
    if (bridgeId is! String ||
        !bridgeId.startsWith('bridge-') ||
        bridgeId.length > 80 ||
        path is! List ||
        path.isEmpty ||
        path.last != bridgeId ||
        _chatSignature(packet) == null) {
      return null;
    }
    return {
      'kind': _receiptKind,
      _receiptKey: bridgeId,
      'senderId': packet['senderId'],
      'messageId': packet['messageId'],
    };
  }

  static String? _chatSignature(Map<String, dynamic> packet) {
    final senderId = packet['senderId'];
    final messageId = packet['messageId'];
    if (senderId is! String ||
        senderId.isEmpty ||
        messageId is! String ||
        messageId.isEmpty)
      return null;
    return jsonEncode([_chatKind, senderId, messageId]);
  }

  static String codeFor(String relayUrl) => Uri(
    scheme: 'lightmesh',
    host: 'connect',
    queryParameters: {'relay': normalizeRelayUrl(relayUrl)},
  ).toString();

  static String normalizeRelayUrl(String input) {
    var uri = Uri.tryParse(input.trim());
    if (uri?.scheme == 'lightmesh' && uri?.host == 'connect') {
      uri = Uri.tryParse(uri!.queryParameters['relay'] ?? '');
    }
    if (uri == null ||
        !{'ws', 'wss'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const FormatException('請貼上有效的光網連接碼。');
    }
    return uri.replace(path: uri.path.isEmpty ? '/' : uri.path).toString();
  }

  Future<void> join(String code) async {
    // Validate before replacing a working connection.
    final remote = normalizeRelayUrl(code);
    final local = normalizeRelayUrl(localRelayUrl);
    if (remote == local) {
      throw const FormatException('這是本網絡的連接碼，請使用另一個 APP 的連接碼。');
    }
    if (_disposed) return;
    disconnect();
    _remoteRelayUrl = remote;
    _active = true;
    final generation = _generation;
    notifyListeners();
    await Future.wait([
      _open(0, local, generation),
      _open(1, remote, generation),
    ]);
  }

  Future<void> _open(int side, String url, int generation) async {
    if (!_current(generation) || _connecting[side] || _sockets[side] != null) {
      return;
    }
    _connecting[side] = true;
    var timedOut = false;
    try {
      final socket = await _connect(url)
          .then((socket) {
            if (timedOut) _discard(socket);
            return socket;
          })
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () {
              timedOut = true;
              throw const SocketException('connection timeout');
            },
          );
      if (!_current(generation)) {
        _discard(socket);
        return;
      }
      _sockets[side] = socket;
      socket.pingInterval = const Duration(seconds: 20);
      socket.listen(
        (data) {
          if (_current(generation) && identical(_sockets[side], socket)) {
            _receive(side, data);
          }
        },
        onDone: () => _lost(side, socket, url, generation),
        onError: (Object _) => _lost(side, socket, url, generation),
        cancelOnError: true,
      );
      // Unconfirmed writes on a lost socket can be resent on the new one.
      for (final packet in _pendingChat[side].values) {
        packet.nextAttempt = DateTime.now();
      }
      _flushPendingChat(side);
      if (connected) _error = null;
      notifyListeners();
      if (connected) onConnected?.call();
    } on Object {
      if (_current(generation)) {
        _error = '暫時未能連接另一個光網，正在自動重試。';
        _retry(side, url, generation);
        notifyListeners();
      }
    } finally {
      if (_current(generation)) _connecting[side] = false;
    }
  }

  bool _current(int generation) =>
      !_disposed && _active && generation == _generation;

  static void _discard(WebSocket socket) {
    // Drain late handshakes too, so close frames are consumed and TCP is freed.
    socket.listen((_) {}, onError: (Object _) {}, cancelOnError: true);
    unawaited(socket.close());
  }

  void _lost(int side, WebSocket socket, String url, int generation) {
    if (!_current(generation) || !identical(_sockets[side], socket)) return;
    _sockets[side] = null;
    _chatRetries[side]?.cancel();
    _chatRetries[side] = null;
    unawaited(socket.close());
    _error = '光網連接中斷，正在自動重試。';
    _retry(side, url, generation);
    notifyListeners();
  }

  void _retry(int side, String url, int generation) {
    if (_retries[side] != null || !_current(generation)) return;
    _retries[side] = Timer(retryDelay, () {
      _retries[side] = null;
      unawaited(_open(side, url, generation));
    });
  }

  void _receive(int side, Object? data) {
    try {
      final String text;
      if (data is String) {
        if (data.length > _maxBytes) return;
        text = data;
      } else if (data is List<int> && data.length <= _maxBytes) {
        text = utf8.decode(data);
      } else {
        return;
      }
      if (utf8.encode(text).length > _maxBytes) return;
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return;
      if (decoded['kind'] == _receiptKind) {
        final signature = _chatSignature(decoded);
        if (decoded[_receiptKey] == _id && signature != null) {
          final pending = _pendingChat[side][signature];
          if (pending != null && pending.attempts > 0) {
            _pendingChat[side].remove(signature);
            _rememberForwarded(signature, DateTime.now());
          }
        }
        return;
      }
      if (!_kinds.contains(decoded['kind'])) return;
      if (forwardPacket?.call(decoded) == false) return;
      // Older relays stamp both fields and reject packets carrying either one.
      decoded.remove('relayReceivedAt');
      decoded.remove('relaySourcePeerId');
      final rawPath = decoded.remove(_pathKey);
      if (rawPath != null &&
          (rawPath is! List || rawPath.any((id) => id is! String))) {
        return;
      }
      final path = rawPath is List ? rawPath.cast<String>() : <String>[];
      if (path.contains(_id) || path.length >= _maxHops) return;

      final isChat = decoded['kind'] == _chatKind;
      if (!isChat && !connected) return;

      // A history replay can change hops without changing the chat message.
      final chatSignature = isChat ? _chatSignature(decoded) : null;
      final signature = chatSignature ?? jsonEncode(_canonical(decoded));
      final now = DateTime.now();
      while (_seen.isNotEmpty &&
          now.difference(_seen.values.first) > _retention) {
        _seen.remove(_seen.keys.first);
      }
      final destination = 1 - side;
      for (final queue in _pendingChat) {
        queue.removeWhere(
          (_, packet) => now.difference(packet.receivedAt) > _retention,
        );
      }
      if (_seen.containsKey(signature) ||
          _pendingChat.any((queue) => queue.containsKey(signature)))
        return;

      decoded[_pathKey] = [...path, _id];
      if (isChat) {
        decoded.remove(_receiptKey);
        if (chatSignature != null) decoded[_receiptKey] = _id;
      }
      final outgoing = jsonEncode(decoded);
      if (utf8.encode(outgoing).length > _maxBytes) return;

      if (isChat) {
        final queue = _pendingChat[destination];
        queue[signature] = _PendingBridgedChat(
          outgoing,
          now,
          requiresReceipt: chatSignature != null,
        );
        while (queue.length > _maxPendingChat) {
          queue.remove(queue.keys.first);
        }
        _flushPendingChat(destination);
      } else if (_send(destination, outgoing)) {
        _rememberForwarded(signature, now);
      }
    } on Object {
      // Invalid packets never take down a network bridge.
    }
  }

  void _flushPendingChat(int destination) {
    _chatRetries[destination]?.cancel();
    _chatRetries[destination] = null;
    if (_sockets[destination]?.readyState != WebSocket.open) return;
    final queue = _pendingChat[destination];
    final now = DateTime.now();
    DateTime? nextAttempt;
    for (final entry in queue.entries.toList()) {
      final packet = entry.value;
      if (now.difference(packet.receivedAt) > _retention) {
        queue.remove(entry.key);
        continue;
      }
      if (!packet.nextAttempt.isAfter(now)) {
        if (packet.attempts >= _maxChatAttempts) {
          _rememberForwarded(entry.key, now);
          queue.remove(entry.key);
          continue;
        }
        if (!_send(destination, packet.text)) return;
        if (!packet.requiresReceipt) {
          _rememberForwarded(entry.key, now);
          queue.remove(entry.key);
          continue;
        }
        packet.nextAttempt = now.add(
          chatReceiptTimeout * (1 << packet.attempts),
        );
        packet.attempts++;
      }
      if (nextAttempt == null || packet.nextAttempt.isBefore(nextAttempt)) {
        nextAttempt = packet.nextAttempt;
      }
    }
    if (nextAttempt != null) {
      _chatRetries[destination] = Timer(
        nextAttempt.difference(DateTime.now()),
        () => _flushPendingChat(destination),
      );
    }
  }

  bool _send(int destination, String text) {
    final socket = _sockets[destination];
    if (socket == null || socket.readyState != WebSocket.open) return false;
    try {
      socket.add(text);
      return true;
    } on Object {
      final url = destination == 0
          ? normalizeRelayUrl(localRelayUrl)
          : _remoteRelayUrl!;
      _lost(destination, socket, url, _generation);
      return false;
    }
  }

  void _rememberForwarded(String signature, DateTime now) {
    _seen[signature] = now;
    while (_seen.length > _maxSeen) {
      _seen.remove(_seen.keys.first);
    }
  }

  static Object? _canonical(Object? value) {
    if (value is Map<String, dynamic>) {
      return {
        for (final key in value.keys.toList()..sort())
          key: _canonical(value[key]),
      };
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  void disconnect() {
    _generation++;
    _active = false;
    _remoteRelayUrl = null;
    _error = null;
    for (var side = 0; side < 2; side++) {
      _retries[side]?.cancel();
      _retries[side] = null;
      _chatRetries[side]?.cancel();
      _chatRetries[side] = null;
      final socket = _sockets[side];
      _sockets[side] = null;
      _connecting[side] = false;
      _pendingChat[side].clear();
      if (socket != null) unawaited(socket.close());
    }
    _seen.clear();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    disconnect();
    super.dispose();
  }
}

class _PendingBridgedChat {
  _PendingBridgedChat(
    this.text,
    this.receivedAt, {
    required this.requiresReceipt,
  }) : nextAttempt = receivedAt;

  final String text;
  final DateTime receivedAt;
  final bool requiresReceipt;
  DateTime nextAttempt;
  int attempts = 0;
}
