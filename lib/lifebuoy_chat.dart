import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'lifebuoy_chat_connection.dart';
import 'lifebuoy_chat_history.dart';
import 'lifebuoy_illustration.dart';
import 'lifebuoy_search.dart';
import 'lightmesh.dart'
    show MeshChatService, MeshContentModeration, MeshMessage, MeshMessageBubble;

Future<bool> confirmSafetyBlock(BuildContext context, String name) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('封鎖用戶？'),
        content: Text('這部裝置會隱藏 $name 在這個功能發佈的內容。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('封鎖'),
          ),
        ],
      ),
    ) ??
    false;

String _messageKey(MeshMessage message) => sha256
    .convert(
      utf8.encode(
        jsonEncode([
          message.id.trim(),
          message.senderId.trim(),
          message.text.trim(),
        ]),
      ),
    )
    .toString();

String _senderKey(MeshMessage message) =>
    sha256.convert(utf8.encode(message.senderId.trim())).toString();

class LifebuoyChat extends StatefulWidget {
  const LifebuoyChat({
    super.key,
    required this.active,
    required this.history,
    this.report,
    this.checkModeration,
    this.prepareMessage,
    this.signIn,
    this.memberId,
  });

  final bool active;
  final LifebuoyChatHistory history;
  static const relay = String.fromEnvironment(
    'LIFEBUOY_RELAY_URL',
    defaultValue: 'wss://lifebuoy.aieco.hk/ws/light',
  );
  final Future<bool> Function(Map<String, dynamic>)? report;
  final Future<Map<String, dynamic>> Function(List<String>, List<String>)?
  checkModeration;
  final Future<({String messageId, String senderId})> Function(String)?
  prepareMessage;
  final Future<void> Function()? signIn;
  final String? memberId;

  @override
  State<LifebuoyChat> createState() => _LifebuoyChatState();
}

class _LifebuoyChatState extends State<LifebuoyChat> {
  static const connectionCode = String.fromEnvironment(
    'LIFEBUOY_NETWORK_CONNECTION_CODE',
  );
  static const directory = String.fromEnvironment(
    'AIECO_NETWORK_DIRECTORY_URL',
    defaultValue: 'https://lifebuoy.aieco.hk/api/lightmesh',
  );
  late final mesh = MeshChatService(
    onlineRelayUrl: widget.history.relayUrl,
    networkConnectionCode: connectionCode,
    networkDirectoryUrl: directory,
    bridgePublicChatOnly: true,
  );
  final composer = TextEditingController();
  final search = TextEditingController();
  bool busy = false;
  bool checkingModeration = false;
  Timer? moderationTimer;
  final removedMessages = <String>{};
  final removedSenders = <String>{};
  Future<void>? restoringHistory;
  List<MeshMessage>? lastHistory;
  bool historyReady = false;
  bool historyUnavailable = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) unawaited(activateChat());
  }

  @override
  void didUpdateWidget(LifebuoyChat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.memberId != null && oldWidget.memberId != widget.memberId) {
      composer.clear();
      search.clear();
    }
    if (widget.active && !oldWidget.active) unawaited(activateChat());
    if (!widget.active) moderationTimer?.cancel();
  }

  Future<void> restoreHistory() async {
    await mesh.loadSavedDisplayName();
    if (!mounted) return;
    await mesh.loadModerationPreferences();
    if (!mounted) return;
    try {
      final saved = await widget.history.load();
      if (!mounted) return;
      lastHistory = saved;
      mesh.restorePublicChatHistory(saved);
    } catch (_) {
      if (mounted) setState(() => historyUnavailable = true);
    }
    if (!mounted) return;
    setState(() => historyReady = true);
    mesh.addListener(updateHistory);
    updateHistory();
  }

  void updateHistory() {
    final snapshot = mesh.publicRoomMessages;
    if (listEquals(snapshot, lastHistory)) return;
    lastHistory = snapshot;
    unawaited(saveHistory(snapshot));
  }

  Future<void> saveHistory(List<MeshMessage> snapshot) async {
    try {
      await widget.history.save(snapshot);
      if (mounted && historyUnavailable) {
        setState(() => historyUnavailable = false);
      }
    } catch (_) {
      if (identical(lastHistory, snapshot)) lastHistory = null;
      if (mounted && !historyUnavailable) {
        setState(() => historyUnavailable = true);
      }
    }
  }

  Future<void> activateChat() async {
    await (restoringHistory ??= restoreHistory());
    if (!mounted || !widget.active) return;
    joinPublicRoom();
    if (widget.checkModeration != null) {
      unawaited(refreshModeration());
      moderationTimer?.cancel();
      moderationTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => refreshModeration(),
      );
    }
  }

  Future<void> refreshModeration() async {
    final check = widget.checkModeration;
    if (check == null || checkingModeration) return;
    final messages = mesh.activeRoomMessages
        .where((message) => !wasRemoved(message))
        .toList();
    if (messages.isEmpty) return;
    checkingModeration = true;
    try {
      for (var offset = 0; offset < messages.length; offset += 50) {
        final batch = messages.skip(offset).take(50).toList();
        final result = await check(
          batch.map(_messageKey).toList(),
          batch
              .where(
                (message) => message.senderId.startsWith('lifebuoy-member-'),
              )
              .map(_senderKey)
              .toSet()
              .toList(),
        );
        if (!mounted) return;
        final removed =
            (result['removed'] as List?)?.whereType<String>().toSet() ?? {};
        final senders =
            (result['removed_senders'] as List?)?.whereType<String>().toSet() ??
            {};
        if (!removedMessages.containsAll(removed) ||
            !removedSenders.containsAll(senders)) {
          setState(() {
            removedMessages.addAll(removed);
            removedSenders.addAll(senders);
          });
          mesh.purgeMessages(
            mesh.activeRoomMessages
                .where(wasRemoved)
                .map((message) => message.id)
                .toSet(),
          );
        }
      }
    } catch (_) {
      // Keep known removals while the moderation API is temporarily unavailable.
    } finally {
      checkingModeration = false;
    }
  }

  bool wasRemoved(MeshMessage message) =>
      (removedMessages.isNotEmpty &&
          removedMessages.contains(_messageKey(message))) ||
      (removedSenders.isNotEmpty &&
          removedSenders.contains(_senderKey(message)));

  Future<void> reportMessage(MeshMessage message) async {
    final report = widget.report;
    if (report == null) return;
    final submitted = await report({
      'kind': 'chat',
      'target_id': message.id,
      'sender_id': message.senderId,
      'sender_name': message.senderName,
      'content': message.text,
    });
    if (submitted && mounted) mesh.deleteMessageFromFeed(message.id);
  }

  Future<void> blockSender(String id, String name) async {
    if (await confirmSafetyBlock(context, name) && mounted) {
      mesh.blockUser(id, userName: name);
    }
  }

  Future<void> showChatSafety() => showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('聊天安全'),
      scrollable: true,
      content: ListenableBuilder(
        listenable: mesh,
        builder: (_, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('請勿發送騷擾、仇恨、威脅、色情或違法內容。用訊息旁的選單舉報，亦可聯絡管理員。'),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SelectableText('info@aieco.hk'),
            ),
            const Divider(),
            Text(mesh.blockedUsers.isEmpty ? '尚未封鎖聊天用戶' : '已封鎖的聊天用戶'),
            for (final user in mesh.blockedUsers)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(user.name),
                trailing: TextButton(
                  onPressed: () =>
                      mesh.unblockUser(user.id, userName: user.name),
                  child: const Text('解除封鎖'),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('關閉'),
        ),
      ],
    ),
  );

  void joinPublicRoom() {
    if (mesh.onlineConfigured && !mesh.onlineConnected) {
      unawaited(mesh.refreshNetworkPresence());
    }
  }

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
    moderationTimer?.cancel();
    mesh.removeListener(updateHistory);
    mesh.dispose();
    composer.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> sendMessage() => operate(() async {
    final draft = composer.text;
    final text = draft.trim();
    if (text.isEmpty) return;
    final prepare = widget.prepareMessage;
    if (prepare != null && widget.memberId == null) {
      await widget.signIn?.call();
      return;
    }
    final member = widget.memberId;
    try {
      final authorization = await prepare?.call(text);
      if (!mounted || widget.memberId != member) return;
      final sent = await mesh.sendMessage(
        text,
        authorizedMessageId: authorization?.messageId,
        authorizedSenderId: authorization?.senderId,
        localMemberId: member,
      );
      if (sent && mounted && composer.text == draft) composer.clear();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException ? error.message : '未能傳送訊息，請稍後再試。',
            ),
          ),
        );
      }
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
      final messages = mesh.activeRoomMessages
          .where(
            (message) =>
                MeshContentModeration.check(message.senderName).allowed &&
                !wasRemoved(message),
          )
          .toList();
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
              FilledButton.tonalIcon(
                onPressed: busy || !mesh.onlineConfigured
                    ? null
                    : showNetworkConnection,
                icon: Icon(
                  mesh.networkBridge.connected
                      ? Icons.link
                      : Icons.hub_outlined,
                  size: 18,
                ),
                label: const Text('連接光網'),
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
              if (historyUnavailable)
                const Text('暫時無法存取手機上的聊天紀錄。', textAlign: TextAlign.center),
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
                            IconButton(
                              tooltip: '聊天安全',
                              onPressed: showChatSafety,
                              icon: const Icon(Icons.shield_outlined, size: 20),
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
                      Expanded(child: messageList(messages)),
                      if (mesh.onlineConfigured)
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
                                  onSubmitted: busy || !historyReady
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
                                onPressed: busy || !historyReady
                                    ? null
                                    : sendMessage,
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

  Widget messageList(List<MeshMessage> roomMessages) {
    if (!historyReady && widget.active) {
      return const Center(child: Text('正在載入聊天紀錄…'));
    }
    final query = search.text;
    final messages = roomMessages.reversed
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
          onReport: widget.report == null ? null : reportMessage,
          onBlockUser: blockSender,
          onDelete: (message) => mesh.deleteMessageFromFeed(message.id),
        );
      },
    );
  }
}
