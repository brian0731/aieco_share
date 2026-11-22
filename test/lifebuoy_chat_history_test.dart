import 'dart:convert';
import 'dart:io';

import 'package:aieco_share/lifebuoy_chat.dart';
import 'package:aieco_share/lifebuoy_chat_history.dart';
import 'package:aieco_share/lightmesh.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

MeshMessage message(String id, {String? memberId}) => MeshMessage(
  id: id,
  roomId: 'room:main',
  roomName: '傳播頻道',
  senderId: 'sender-$id',
  senderName: '測試成員',
  text: '訊息 $id',
  sentAt: DateTime.utc(2026, 11, 22),
  isMine: memberId != null,
  localMemberId: memberId,
);

String messageKey(MeshMessage message) => sha256
    .convert(
      utf8.encode(jsonEncode([message.id, message.senderId, message.text])),
    )
    .toString();

void main() {
  test(
    'account erasure removes local messages even if a save was queued',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'lifebuoy-chat-history',
      );
      addTearDown(() => folder.delete(recursive: true));
      LifebuoyChatHistory open() =>
          LifebuoyChatHistory(relayUrl: 'test', directory: () async => folder);
      final history = open();
      final peer = message('peer');
      final mine = message('mine', memberId: 'member');
      final messages = [peer, mine];
      await history.save(messages);
      expect((await open().load()).last.isMine, isTrue);
      await Future.wait([
        history.save(messages),
        history.eraseMember('member'),
        history.save(messages),
      ]);
      final restored = await open().load();
      expect(restored.map((entry) => entry.id), ['peer']);
      expect(restored.single.sentAt.toUtc(), peer.sentAt);
    },
  );

  testWidgets('chat opens offline and keeps moderated messages deleted', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'mesh.blockedUsers': ['sender-blocked'],
      'mesh.hiddenMessages': ['b764013e-7e11-43ee-b608-0b7238e22983'],
    });
    final folder = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('lifebuoy-chat-widget'),
    ))!;
    addTearDown(() => folder.delete(recursive: true));
    LifebuoyChatHistory open() =>
        LifebuoyChatHistory(relayUrl: '', directory: () async => folder);
    final history = open();
    final visible = message('offline');
    final removed = message('removed');
    await tester.runAsync(
      () => history.save([
        visible,
        removed,
        message('blocked'),
        message('b764013e-7e11-43ee-b608-0b7238e22983'),
      ]),
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LifebuoyChat(
              active: true,
              history: history,
              checkModeration: (_, _) async => {
                'removed': [messageKey(removed)],
              },
            ),
          ),
        ),
      );
      await history.load();
    });
    for (var step = 0; step < 25; step++) {
      final ids = await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return (await history.load()).map((entry) => entry.id).toList();
      });
      await tester.pump();
      if (ids?.length == 1) break;
    }
    expect(find.text(visible.text), findsOneWidget);
    expect(find.text(removed.text), findsNothing);
    expect(
      (await tester.runAsync(() => open().load()))!.map((entry) => entry.id),
      ['offline'],
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
