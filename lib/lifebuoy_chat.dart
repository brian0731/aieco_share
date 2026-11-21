import 'dart:async';

import 'package:flutter/material.dart';

import 'lifebuoy_chat_connection.dart';
import 'lifebuoy_illustration.dart';
import 'lifebuoy_search.dart';
import 'lightmesh.dart'
    show MeshChatService, MeshMessageBubble, MeshNetworkMode;

class LifebuoyChat extends StatefulWidget {
  const LifebuoyChat({super.key});

  @override
  State<LifebuoyChat> createState() => _LifebuoyChatState();
}

class _LifebuoyChatState extends State<LifebuoyChat> {
  static const relay = String.fromEnvironment(
    'LIFEBUOY_RELAY_URL',
    defaultValue: 'wss://lifebuoy.aieco.hk/ws/light',
  );
  static const connectionCode = String.fromEnvironment(
    'LIFEBUOY_NETWORK_CONNECTION_CODE',
  );
  static const directory = String.fromEnvironment(
    'AIECO_NETWORK_DIRECTORY_URL',
    defaultValue: 'https://lifebuoy.aieco.hk/api/lightmesh',
  );
  final mesh = MeshChatService(
    onlineRelayUrl: relay,
    networkConnectionCode: connectionCode,
    networkDirectoryUrl: directory,
    bridgePublicChatOnly: true,
  );
  final composer = TextEditingController();
  final search = TextEditingController();
  bool busy = false;

  Future<void> joinPublicRoom() => operate(() async {
    await mesh.setNetworkMode(MeshNetworkMode.online);
    await mesh.start();
  });

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

  Future<void> sendMessage() => operate(() async {
    final text = composer.text;
    if (await mesh.sendMessage(text) && mounted && composer.text == text) {
      composer.clear();
    }
  });

  void showNetworkConnection() => showDialog<void>(
    context: context,
    builder: (_) => LifebuoyChatConnection(mesh: mesh, directoryUrl: directory),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: mesh,
    builder: (context, _) {
      final room = mesh.activeRoom;
      final messages = mesh.activeRoomMessages;
      final buttonStyle = FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!mesh.isRunning) ...[
                const LifebuoyIllustration(
                  scene: 'chat',
                  color: Color(0xff344453),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy || !mesh.onlineConfigured
                          ? null
                          : joinPublicRoom,
                      style: buttonStyle,
                      icon: const Icon(Icons.public, size: 18),
                      label: const Text(
                        '公開房間',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: busy || !mesh.onlineConfigured
                          ? null
                          : showNetworkConnection,
                      style: buttonStyle,
                      icon: Icon(
                        mesh.networkBridge.connected
                            ? Icons.link
                            : Icons.hub_outlined,
                        size: 18,
                      ),
                      label: const Text(
                        '連接光網',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              if (!mesh.onlineConfigured)
                const Text('尚未設定光網公開房間', textAlign: TextAlign.center)
              else if (mesh.isRunning)
                Text(
                  mesh.networkBridge.connected ? '光網聊天室已互通' : mesh.status,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 8),
              Expanded(
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.forum_outlined,
                              color: Color(0xff0d7c66),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                room.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            Text(
                              '${messages.length} 則',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: LifebuoySearchField(
                          controller: search,
                          label: '搜尋聊天訊息或發送者',
                          onChanged: () => setState(() {}),
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xffe0e5de)),
                      Expanded(child: messageList()),
                      if (mesh.isRunning)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: composer,
                                  minLines: 1,
                                  maxLines: 4,
                                  maxLength: 2000,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: busy
                                      ? null
                                      : (_) => unawaited(sendMessage()),
                                  decoration: InputDecoration(
                                    hintText: '傳送到 ${room.name}',
                                    counterText: '',
                                    prefixIcon: const Icon(
                                      Icons.chat_bubble_outline,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              IconButton.filled(
                                tooltip: '送出',
                                icon: const Icon(Icons.send),
                                onPressed: busy ? null : sendMessage,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget messageList() {
    final query = search.text;
    final messages = mesh.activeRoomMessages.reversed
        .where(
          (message) =>
              matchesLifebuoySearch(query, [message.text, message.senderName]),
        )
        .toList();
    if (messages.isEmpty) {
      if (query.trim().isNotEmpty) {
        return const Center(child: Text('找不到符合的聊天訊息'));
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: const Color(0xffe0f2e9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.light_mode_outlined,
                color: Color(0xff0d7c66),
                size: 34,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '未有訊息',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(14),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        return MeshMessageBubble(
          key: ValueKey(message.id),
          message: message,
          onDelete: (message) => mesh.deleteMessageFromFeed(message.id),
        );
      },
    );
  }
}
