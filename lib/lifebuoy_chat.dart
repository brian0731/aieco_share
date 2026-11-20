import 'dart:async';

import 'package:flutter/material.dart';

import 'lifebuoy_illustration.dart';
import 'lifebuoy_search.dart';
import 'lightmesh.dart' show MeshChatService, MeshNetworkMode;

class LifebuoyChat extends StatefulWidget {
  const LifebuoyChat({super.key});

  @override
  State<LifebuoyChat> createState() => _LifebuoyChatState();
}

class _LifebuoyChatState extends State<LifebuoyChat> {
  static const relay = String.fromEnvironment('LIFEBUOY_RELAY_URL');
  final mesh = MeshChatService(onlineRelayUrl: relay);
  final composer = TextEditingController();
  final search = TextEditingController();
  bool started = false;
  bool busy = false;

  Future<void> operate(Future<void> Function() task) async {
    setState(() => busy = true);
    try {
      await task();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    mesh.dispose();
    composer.dispose();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: mesh,
    builder: (context, _) => SafeArea(
      child: Column(
        children: [
          if (!started)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: LifebuoyIllustration(
                scene: 'chat',
                color: Color(0xff344453),
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => operate(() async {
                        await mesh.setNetworkMode(MeshNetworkMode.offline);
                        await mesh.start();
                        if (mounted) setState(() => started = true);
                      }),
                child: const Text('加入 LAN 聊天'),
              ),
              OutlinedButton(
                onPressed: busy || relay.isEmpty
                    ? null
                    : () => operate(() async {
                        await mesh.setNetworkMode(MeshNetworkMode.online);
                        await mesh.start();
                        if (mounted) setState(() => started = true);
                      }),
                child: const Text('加入光網公開房間'),
              ),
            ],
          ),
          if (relay.isEmpty) const Text('尚未設定光網公開房間'),
          if (started) Text(mesh.status),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: LifebuoySearchField(
              controller: search,
              label: '搜尋聊天訊息或發送者',
              onChanged: () => setState(() {}),
            ),
          ),
          Expanded(child: messageList()),
          if (started)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: composer,
                      maxLength: 2000,
                      decoration: const InputDecoration(
                        labelText: '訊息',
                        counterText: '',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '傳送',
                    icon: const Icon(Icons.send),
                    onPressed: busy
                        ? null
                        : () => unawaited(
                            operate(() async {
                              if (await mesh.sendMessage(composer.text) &&
                                  mounted) {
                                composer.clear();
                              }
                            }),
                          ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  Widget messageList() {
    final query = search.text;
    final messages = mesh.activeRoomMessages.reversed
        .where(
          (message) =>
              matchesLifebuoySearch(query, [message.text, message.senderName]),
        )
        .toList();
    if (messages.isEmpty && query.trim().isNotEmpty) {
      return const Center(child: Text('找不到符合的聊天訊息'));
    }
    return ListView.builder(
      reverse: true,
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        return ListTile(
          title: Text(message.text),
          subtitle: Text(message.senderName),
        );
      },
    );
  }
}
