import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/lifebuoy_public_bridge.dart <roster.json>',
    );
    exitCode = 64;
    return;
  }
  final file = File(args.single);
  var previous = '';
  PublicBridge? bridge;
  while (true) {
    try {
      final source = await file.readAsString();
      if (source != previous) {
        await bridge?.close();
        bridge = null;
        final config = jsonDecode(source) as Map<String, dynamic>;
        if (config['enabled'] == true) {
          bridge = PublicBridge.fromConfig(config)..start();
        }
        previous = source;
      }
    } catch (error) {
      await bridge?.close();
      bridge = null;
      previous = '';
      stderr.writeln(
        'Bridge disabled: invalid or unreadable roster (${error.runtimeType})',
      );
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
}

class BridgeEndpoint {
  BridgeEndpoint(this.id, this.url, this.rooms);
  final String id;
  final Uri url;
  final Map<String, String> rooms;
  WebSocket? socket;
  DateTime window = DateTime.fromMillisecondsSinceEpoch(0);
  int messages = 0;

  bool allowMessage(DateTime now) {
    if (now.difference(window) >= const Duration(seconds: 10)) {
      window = now;
      messages = 0;
    }
    return ++messages <= 50;
  }
}

class PublicBridge {
  PublicBridge(this.endpoints, {this.retry = const Duration(seconds: 5)});

  factory PublicBridge.fromConfig(Map<String, dynamic> config) {
    final endpoints = <BridgeEndpoint>[];
    final ids = <String>{};
    final urls = <Uri>{};
    for (final entry in config['relays'] as List) {
      if (entry['approved'] != true || entry['enabled'] != true) continue;
      final id = entry['id'] as String;
      final uri = Uri.parse(entry['url'] as String);
      if (!RegExp(r'^[a-zA-Z0-9_-]{1,40}$').hasMatch(id) ||
          uri.userInfo.isNotEmpty ||
          uri.host.isEmpty ||
          !(uri.scheme == 'wss' ||
              (uri.scheme == 'ws' &&
                  (uri.host == '127.0.0.1' || uri.host == 'localhost'))) ||
          !ids.add(id) ||
          !urls.add(uri)) {
        throw const FormatException('Invalid relay roster entry');
      }
      final rooms = <String, String>{};
      for (final room in entry['rooms'] as List) {
        if (room['public'] != true || room['approved'] != true) continue;
        final local = room['local'] as String;
        final shared = room['shared'] as String;
        if (!RegExp(r'^room:[a-zA-Z0-9_-]{1,80}$').hasMatch(local) ||
            !RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(shared) ||
            rooms.containsKey(local) ||
            rooms.containsValue(shared)) {
          throw const FormatException('Invalid room mapping');
        }
        rooms[local] = shared;
      }
      if (rooms.isNotEmpty) endpoints.add(BridgeEndpoint(id, uri, rooms));
    }
    return PublicBridge(endpoints);
  }

  final List<BridgeEndpoint> endpoints;
  final Duration retry;
  final seen = <String, DateTime>{};
  var running = false;

  void start() {
    if (running) return;
    running = true;
    for (final endpoint in endpoints) {
      unawaited(connect(endpoint));
    }
  }

  Future<void> connect(BridgeEndpoint endpoint) async {
    while (running) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      WebSocket? socket;
      try {
        final handshake = WebSocket.connect(
          endpoint.url.toString(),
          customClient: client,
        );
        socket = await handshake.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            client.close(force: true);
            unawaited(
              handshake.then<void>((lateSocket) async {
                await lateSocket.close();
              }, onError: (Object _) {}),
            );
            throw TimeoutException('Relay handshake');
          },
        );
        if (!running) return;
        endpoint.socket = socket;
        socket.pingInterval = const Duration(seconds: 20);
        stdout.writeln('Connected approved relay ${endpoint.id}');
        await for (final packet in socket) {
          if (!running) break;
          forward(endpoint, packet);
        }
      } catch (error) {
        if (running) {
          stderr.writeln(
            'Relay ${endpoint.id}: ${error.runtimeType}; retrying',
          );
        }
      } finally {
        endpoint.socket = null;
        if (socket != null) unawaited(socket.close());
        client.close(force: true);
      }
      if (running) await Future<void>.delayed(retry);
    }
  }

  void forward(BridgeEndpoint source, Object? data) {
    if (data is! String ||
        data.length > 65536 ||
        utf8.encode(data).length > 65536) {
      return;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(data);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    if (decoded['kind'] != 'aieco.light.chat.v1' ||
        decoded.containsKey('_lifebuoyBridge') ||
        decoded.containsKey('_lightBridgePath')) {
      return;
    }
    const fields = {
      'kind',
      'app',
      'messageId',
      'roomId',
      'roomName',
      'senderId',
      'senderName',
      'senderUserName',
      'tcpPort',
      'text',
      'sentAt',
      'hops',
    };
    if (decoded.keys.any((key) => !fields.contains(key))) return;
    final shared = source.rooms[decoded['roomId']];
    if (shared == null) return;
    final messageId = decoded['messageId'];
    final senderId = decoded['senderId'];
    final name = decoded['senderName'];
    final message = decoded['text'];
    final sentAt = decoded['sentAt'];
    if (messageId is! String ||
        messageId.isEmpty ||
        messageId.length > 120 ||
        senderId is! String ||
        senderId.isEmpty ||
        senderId.length > 120 ||
        name is! String ||
        name.isEmpty ||
        name.length > 100 ||
        message is! String ||
        message.trim().isEmpty ||
        message.length > 2000 ||
        sentAt is! String ||
        DateTime.tryParse(sentAt) == null) {
      return;
    }
    final now = DateTime.now();
    if (!source.allowMessage(now)) return;
    seen.removeWhere(
      (_, time) => now.difference(time) > const Duration(minutes: 5),
    );
    final key = jsonEncode([shared, senderId, messageId]);
    if (seen.containsKey(key)) return;
    bool sent = false;
    for (final target in endpoints) {
      if (source == target || target.socket?.readyState != WebSocket.open) {
        continue;
      }
      for (final room in target.rooms.entries) {
        if (room.value != shared) continue;
        final packet = <String, Object?>{
          'kind': 'aieco.light.chat.v1',
          'app': '社區救生圈',
          'messageId': messageId,
          'senderId': senderId,
          'senderName': name,
          'text': message,
          'sentAt': sentAt,
          'roomId': room.key,
          'roomName': '光網公開聊天室',
          'hops': 0,
          '_lifebuoyBridge': source.id,
        };
        target.socket!.add(jsonEncode(packet));
        sent = true;
      }
    }
    if (sent) {
      if (seen.length >= 4096) seen.remove(seen.keys.first);
      seen[key] = now;
    }
  }

  Future<void> close() async {
    running = false;
    await Future.wait(
      endpoints.map((endpoint) async {
        final socket = endpoint.socket;
        if (socket != null) {
          await socket.close().timeout(
            const Duration(seconds: 2),
            onTimeout: () {},
          );
        }
      }),
    );
  }
}
