import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'lightmesh.dart' show MeshMessage;

class LifebuoyChatHistory {
  LifebuoyChatHistory({
    required this.relayUrl,
    this.directory = getApplicationSupportDirectory,
  });

  final String relayUrl;
  final Future<Directory> Function() directory;
  final _deletedMembers = <String>{};
  Future<void> _pending = Future<void>.value();

  Future<T> _queue<T>(Future<T> Function() action) {
    final next = _pending.then((_) => action());
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<File> _file() async {
    final folder = await directory();
    final relay = sha256.convert(utf8.encode(relayUrl));
    return File('${folder.path}/lifebuoy-chat-$relay.json');
  }

  Future<List<MeshMessage>> load() => _queue(() async => _read(await _file()));

  Future<void> save(List<MeshMessage> messages) =>
      _queue(() async => _write(await _file(), messages));

  Future<void> eraseMember(String id) {
    _deletedMembers.add(id);
    return _queue(() async {
      final file = await _file();
      if (await file.exists()) await _write(file, await _read(file));
    });
  }

  Future<List<MeshMessage>> _read(File file) async {
    if (!await file.exists()) return [];
    try {
      final records = jsonDecode(await file.readAsString());
      if (records is! List) return [];
      return records
          .map(_decode)
          .whereType<MeshMessage>()
          .where((message) => !_deletedMembers.contains(message.localMemberId))
          .toList();
    } on FormatException {
      return [];
    }
  }

  Future<void> _write(File file, List<MeshMessage> messages) async {
    final temporary = File('${file.path}.tmp');
    final records = [
      for (final message in messages)
        if (!_deletedMembers.contains(message.localMemberId))
          {
            'id': message.id,
            'roomId': message.roomId,
            'roomName': message.roomName,
            'senderId': message.senderId,
            'senderName': message.senderName,
            'senderDisplayName': message.senderDisplayName,
            'senderUserName': message.senderUserName,
            'text': message.text,
            'sentAt': message.sentAt.toUtc().toIso8601String(),
            'isMine': message.isMine,
            if (message.localMemberId != null)
              'localMemberId': message.localMemberId,
          },
    ];
    await temporary.writeAsString(jsonEncode(records), flush: true);
    await temporary.rename(file.path);
  }

  static MeshMessage? _decode(Object? record) {
    if (record case {
      'id': final String id,
      'roomId': final String roomId,
      'roomName': final String roomName,
      'senderId': final String senderId,
      'senderName': final String senderName,
      'senderDisplayName': final String senderDisplayName,
      'senderUserName': final String senderUserName,
      'text': final String text,
      'sentAt': final String timestamp,
      'isMine': final bool isMine,
    }) {
      final sentAt = DateTime.tryParse(timestamp);
      if (sentAt == null ||
          id.isEmpty ||
          senderId.isEmpty ||
          text.trim().isEmpty) {
        return null;
      }
      return MeshMessage(
        id: id,
        roomId: roomId,
        roomName: roomName,
        senderId: senderId,
        senderName: senderName,
        senderDisplayName: senderDisplayName,
        senderUserName: senderUserName,
        text: text,
        sentAt: sentAt.toLocal(),
        isMine: isMine,
        localMemberId: record['localMemberId'] is String
            ? record['localMemberId'] as String
            : null,
      );
    }
    return null;
  }
}
