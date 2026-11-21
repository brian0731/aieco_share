import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lightmesh.dart' show MeshChatService, MeshNetworkMode;
import 'network_pairing_client.dart';

class LifebuoyChatConnection extends StatefulWidget {
  const LifebuoyChatConnection({
    super.key,
    required this.mesh,
    required this.directoryUrl,
  });

  final MeshChatService mesh;
  final String directoryUrl;

  @override
  State<LifebuoyChatConnection> createState() => _LifebuoyChatConnectionState();
}

class _LifebuoyChatConnectionState extends State<LifebuoyChatConnection> {
  final code = TextEditingController();
  bool busy = false;
  bool loadingOwnCode = false;
  String ownCode = '';
  String? error;

  @override
  void initState() {
    super.initState();
    ownCode = widget.mesh.networkConnectionCode;
    if (ownCode.isEmpty && widget.mesh.onlineConfigured) loadOwnCode();
  }

  Future<void> loadOwnCode() async {
    setState(() => loadingOwnCode = true);
    try {
      final value = await NetworkPairingClient(
        widget.directoryUrl,
      ).codeFor(widget.mesh.onlineRelayUrl);
      if (mounted) setState(() => ownCode = value);
    } on FormatException {
      // Retrying the lookup does not affect entering another network's code.
    } finally {
      if (mounted) setState(() => loadingOwnCode = false);
    }
  }

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> pasteCode() async {
    final value = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    if (!mounted || value == null) return;
    if (NetworkPairingClient.codePattern.hasMatch(value)) {
      code.text = value;
      setState(() => error = null);
    } else {
      setState(() => error = '請輸入 6 位數字連接碼。');
    }
  }

  Future<void> connect() async {
    final value = code.text.trim();
    final mesh = widget.mesh;
    if (!NetworkPairingClient.codePattern.hasMatch(value)) {
      setState(() => error = '請輸入 6 位數字連接碼。');
      return;
    }
    if (value == ownCode) {
      setState(() => error = '這是本網絡的連接碼，請輸入另一個 APP 的碼。');
      return;
    }
    setState(() {
      error = null;
      busy = true;
    });
    try {
      FocusScope.of(context).unfocus();
      await mesh.setNetworkMode(MeshNetworkMode.online);
      if (mounted) await mesh.connectOtherNetwork(value);
    } on FormatException catch (problem) {
      if (mounted) setState(() => error = problem.message);
    } on Object {
      if (mounted) setState(() => error = '暫時未能連接，請稍後再試。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mesh = widget.mesh;
    return ListenableBuilder(
      listenable: mesh,
      builder: (context, _) {
        final bridge = mesh.networkBridge;
        return AlertDialog(
          title: const Text('連接另一個光網 APP'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mesh.onlineConfigured)
                const Text('社區救生圈尚未設定公網聊天室。')
              else ...[
                if (ownCode.isNotEmpty) ...[
                  const Text('社區救生圈連接碼'),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          ownCode,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: '複製本網絡連接碼',
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: ownCode)),
                        icon: const Icon(Icons.copy_outlined),
                      ),
                    ],
                  ),
                  const Divider(),
                ] else if (loadingOwnCode)
                  const LinearProgressIndicator(semanticsLabel: '查詢本網絡連接碼')
                else
                  TextButton.icon(
                    onPressed: loadOwnCode,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新查詢本網絡連接碼'),
                  ),
                TextField(
                  controller: code,
                  enabled: !busy && !bridge.active,
                  maxLength: 6,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) {
                    if (error != null) setState(() => error = null);
                  },
                  decoration: InputDecoration(
                    labelText: '對方的 6 位連接碼',
                    suffixIcon: IconButton(
                      tooltip: '貼上連接碼',
                      onPressed: busy || bridge.active ? null : pasteCode,
                      icon: const Icon(Icons.content_paste),
                    ),
                  ),
                ),
                if (busy) const LinearProgressIndicator(),
                if (error != null || bridge.active) ...[
                  const SizedBox(height: 8),
                  Text(
                    error ??
                        (bridge.connected
                            ? '兩個 APP 的聊天室已互通'
                            : bridge.error ?? '正在連接另一個光網…'),
                  ),
                ],
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('關閉'),
            ),
            if (bridge.active)
              OutlinedButton(
                onPressed: busy ? null : mesh.disconnectOtherNetwork,
                child: const Text('中斷互通'),
              )
            else if (mesh.onlineConfigured)
              FilledButton.icon(
                onPressed: busy ? null : connect,
                icon: const Icon(Icons.link),
                label: const Text('接通另一個 APP'),
              ),
          ],
        );
      },
    );
  }
}
