part of 'main.dart';

class _UserSettingsPage extends StatefulWidget {
  const _UserSettingsPage({required this.account, required this.api});

  final Json account;
  final Future<Json> Function(String path, [Json? data]) api;

  @override
  State<_UserSettingsPage> createState() => _UserSettingsPageState();
}

class _UserSettingsPageState extends State<_UserSettingsPage> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(
    text: widget.account['name'] as String?,
  );
  late String? district =
      _districtNames.containsKey(widget.account['community_id'])
      ? widget.account['community_id'] as String
      : null;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> saveProfile() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api('account/profile', {
        'name': name.text.trim(),
        'community_id': district,
      });
      if (mounted) Navigator.pop(context, 'profile');
    } catch (problem) {
      if (mounted) {
        setState(() {
          error = problem is FormatException ? problem.message : '暫時無法儲存，請稍後再試';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> accountAction({required bool deleting}) async {
    final action = deleting ? 'delete' : 'password';
    final done = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _AccountPasswordDialog(deleting: deleting, api: widget.api),
    );
    if (done == true && mounted) Navigator.pop(context, action);
  }

  @override
  Widget build(BuildContext context) {
    final changedDistrict =
        district != null && district != widget.account['community_id'];
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('用戶設定')),
        body: SafeArea(
          child: Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: name,
                  enabled: !busy,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: '顯示名稱'),
                  validator: (value) {
                    final length = value?.trim().length ?? 0;
                    return length == 0 || length > 100
                        ? '請輸入 1 至 100 字的顯示名稱'
                        : null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: district,
                  isExpanded: true,
                  menuMaxHeight: 360,
                  decoration: const InputDecoration(labelText: '香港地區'),
                  items: [
                    for (final entry in _districtNames.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: busy
                      ? null
                      : (value) => setState(() => district = value),
                  validator: (value) => value == null ? '請選擇香港十八區之一' : null,
                ),
                if (changedDistrict)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('換區後會下架原區刊登。時間銀行餘額和既有交易會保留。'),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy ? null : saveProfile,
                  child: Text(busy ? '儲存中…' : '儲存資料'),
                ),
                const Divider(height: 32),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('更改密碼'),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: !busy,
                  onTap: () => accountAction(deleting: false),
                ),
                ListTile(
                  leading: const Icon(Icons.person_remove_outlined),
                  title: const Text('刪除帳戶'),
                  trailing: const Icon(Icons.chevron_right),
                  textColor: Theme.of(context).colorScheme.error,
                  iconColor: Theme.of(context).colorScheme.error,
                  enabled: !busy,
                  onTap: () => accountAction(deleting: true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountPasswordDialog extends StatefulWidget {
  const _AccountPasswordDialog({required this.deleting, required this.api});

  final bool deleting;
  final Future<Json> Function(String path, [Json? data]) api;

  @override
  State<_AccountPasswordDialog> createState() => _AccountPasswordDialogState();
}

class _AccountPasswordDialogState extends State<_AccountPasswordDialog> {
  final form = GlobalKey<FormState>();
  final current = TextEditingController();
  final replacement = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    current.dispose();
    replacement.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget
          .api(widget.deleting ? 'account/delete' : 'account/password', {
            'current_password': current.text,
            if (!widget.deleting) 'new_password': replacement.text,
          });
      if (mounted) Navigator.pop(context, true);
    } catch (problem) {
      if (mounted) {
        setState(() {
          busy = false;
          error = problem is FormatException ? problem.message : '暫時無法完成，請稍後再試';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(widget.deleting ? '永久刪除帳戶？' : '更改密碼'),
      scrollable: true,
      content: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.deleting)
              const Text(
                '刪除後無法登入或恢復帳戶。刊登原文、評分及與帳戶連結的光網訊息會移除，待完成交易會取消。共同交易會保留時數及狀態，並移除你的顯示名稱和交收地點。舊版訪客訊息與其他光網 App 已收到的副本可能仍然存在。',
              )
            else
              const Text('更新密碼後，所有裝置都需要重新登入。'),
            TextFormField(
              controller: current,
              enabled: !busy,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: '現有密碼'),
              validator: (value) => (value ?? '').isEmpty ? '請輸入現有密碼' : null,
            ),
            if (!widget.deleting) ...[
              TextFormField(
                controller: replacement,
                enabled: !busy,
                obscureText: true,
                decoration: const InputDecoration(labelText: '新密碼'),
                validator: (value) {
                  final text = value ?? '';
                  return text.length < 12 || utf8.encode(text).length > 256
                      ? '請使用至少 12 個字元'
                      : null;
                },
              ),
              TextFormField(
                enabled: !busy,
                obscureText: true,
                decoration: const InputDecoration(labelText: '確認新密碼'),
                validator: (value) =>
                    value != replacement.text ? '兩次輸入的密碼不一致' : null,
              ),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: busy ? null : submit,
          style: widget.deleting
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                )
              : null,
          child: Text(
            busy
                ? '處理中…'
                : widget.deleting
                ? '永久刪除'
                : '更新密碼',
          ),
        ),
      ],
    ),
  );
}
