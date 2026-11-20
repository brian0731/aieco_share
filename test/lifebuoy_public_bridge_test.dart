import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/lifebuoy_public_bridge.dart';

class Relay {
  Relay(this.server) {
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      clients.add(socket);
      socket.listen(
        (data) {
          for (final client in clients.toList()) {
            if (client.readyState == WebSocket.open) client.add(data);
          }
        },
        onDone: () => clients.remove(socket),
        onError: (_) => clients.remove(socket),
      );
    });
  }

  final HttpServer server;
  final clients = <WebSocket>{};
  Uri get uri => Uri.parse('ws://127.0.0.1:${server.port}/ws/light');

  static Future<Relay> start([int port = 0]) async =>
      Relay(await HttpServer.bind(InternetAddress.loopbackIPv4, port));

  Future<void> close() async {
    for (final client in clients.toList()) {
      unawaited(client.close());
    }
    await server.close(force: true);
  }
}

Map<String, Object> message(String id, String room) => {
  'kind': 'aieco.light.chat.v1',
  'messageId': id,
  'senderId': 'test-$id',
  'senderName': '測試成員',
  'roomId': room,
  'text': '驗收 $id',
  'sentAt': DateTime.now().toUtc().toIso8601String(),
};

Future<void> until(bool Function() check) async {
  for (var i = 0; i < 150; i++) {
    if (check()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('Timed out waiting for relay');
}

void main() {
  test(
    'approved room chat, both ways, dedupe, reconnection and disconnect',
    () async {
      final a = await Relay.start();
      var b = await Relay.start();
      final bPort = b.server.port;
      final bridge = PublicBridge([
        BridgeEndpoint('a', a.uri, {'room:left': 'approved'}),
        BridgeEndpoint('b', b.uri, {'room:right': 'approved'}),
      ], retry: const Duration(milliseconds: 60))..start();
      addTearDown(() async {
        await bridge.close();
        await a.close();
        await b.close();
      });
      final left = await WebSocket.connect(a.uri.toString());
      var right = await WebSocket.connect(b.uri.toString());
      final leftPackets = <Map<String, dynamic>>[];
      final rightPackets = <Map<String, dynamic>>[];
      left.listen(
        (data) =>
            leftPackets.add(jsonDecode(data as String) as Map<String, dynamic>),
      );
      void watchRight() {
        right.listen(
          (data) => rightPackets.add(
            jsonDecode(data as String) as Map<String, dynamic>,
          ),
        );
      }

      watchRight();
      await until(() => a.clients.length == 2 && b.clients.length == 2);
      final packet = message('one', 'room:left');
      left.add(jsonEncode(packet));
      left.add(jsonEncode(packet));
      left.add(jsonEncode(message('private', 'room:private')));
      left.add(
        jsonEncode({
          ...message('location', 'room:left'),
          'kind': 'aieco.light.location.v1',
        }),
      );
      left.add(
        jsonEncode({
          ...message('direct', 'room:left'),
          'targetId': 'private-user',
        }),
      );
      right.add(jsonEncode(message('two', 'room:right')));
      await until(
        () =>
            leftPackets.any((p) => p['messageId'] == 'two') &&
            rightPackets.length >= 2,
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final bridgedRight = rightPackets
          .where((p) => p['_lifebuoyBridge'] != null)
          .toList();
      expect(bridgedRight.map((p) => p['messageId']), ['one']);
      expect(bridgedRight.single['roomId'], 'room:right');
      expect(
        leftPackets.where((p) => p['messageId'] == 'two').single['roomId'],
        'room:left',
      );

      await b.close();
      await until(() => bridge.endpoints[1].socket == null);
      b = await Relay.start(bPort);
      right = await WebSocket.connect(b.uri.toString());
      watchRight();
      await until(() => b.clients.length == 2);
      left.add(jsonEncode(message('reconnect', 'room:left')));
      await until(() => rightPackets.any((p) => p['messageId'] == 'reconnect'));
      await bridge.close();
      left.add(jsonEncode(message('disabled', 'room:left')));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(rightPackets.any((p) => p['messageId'] == 'disabled'), false);
      unawaited(left.close());
      unawaited(right.close());
    },
  );

  test(
    'only approved and enabled relay entries with approved public maps connect',
    () {
      Map<String, dynamic> relay(
        String id,
        int port, {
        bool approved = true,
        bool enabled = true,
        bool room = true,
      }) => {
        'id': id,
        'url': 'ws://127.0.0.1:$port',
        'approved': approved,
        'enabled': enabled,
        'rooms': [
          {
            'local': 'room:main',
            'shared': 'main',
            'approved': true,
            'public': room,
          },
        ],
      };
      final bridge = PublicBridge.fromConfig({
        'relays': [
          relay('active', 5001),
          relay('disabled', 5002, enabled: false),
          relay('denied', 5003, approved: false),
          relay('private', 5004, room: false),
        ],
      });
      expect(bridge.endpoints.map((e) => e.id), ['active']);
    },
  );
}
