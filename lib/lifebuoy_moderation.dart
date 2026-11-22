part of 'main.dart';

const _blockedMembersPreference = 'lifebuoy.blocked-members.v1';

String listingAuthorKey(Json row, {required bool item}) {
  final field = item ? 'owner' : 'author';
  final district = row['${field}_origin'] ?? row['community_id'];
  return '$district/${row['${field}_id']}';
}

extension _LifebuoyModeration on _LifebuoyHomeState {
  Future<void> restoreBlockedMembers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(
        prefs.getString(_blockedMembersPreference) ?? '{}',
      );
      if (mounted && saved is Map) {
        updateBlockedMembers({
          for (final entry in saved.entries)
            if (entry.key is String && entry.value is String)
              entry.key as String: entry.value as String,
          ...blockedMembers.value,
        });
      }
    } on PlatformException {
      // The current session can still hide blocked accounts.
    } on FormatException {
      // Ignore invalid data from older local preferences.
    }
  }

  Future<void> saveBlockedMembers(Map<String, String> next) async {
    if (!mounted) return;
    updateBlockedMembers(next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_blockedMembersPreference, jsonEncode(next));
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('封鎖設定只在今次使用期間生效。')));
      }
    }
  }

  Future<bool> submitContentReport(Json target) async {
    if (account == null) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('登入後舉報'),
          content: const Text('請登入或建立帳號。舉報將交由管理員處理。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('登入或註冊'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return false;
      await signin();
      if (!mounted || account == null) return false;
    }
    final reason = (await fields('舉報內容', ['舉報原因']))?.single;
    if (reason == null || !mounted) return false;
    if (reason.length > 500) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('舉報原因最多 500 字。')));
      return false;
    }
    try {
      await api('reports', {...target, 'reason': reason});
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已送交管理員處理。')));
      }
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException ? error.message : '未能送出舉報，請稍後重試。',
            ),
          ),
        );
      }
      return false;
    }
  }

  Widget listingSafetyMenu(Json row, {required bool item}) {
    final author = (row[item ? 'owner' : 'author'] as String?) ?? '發佈者';
    final key = listingAuthorKey(row, item: item);
    return PopupMenuButton<bool>(
      tooltip: item ? '刊登安全選項' : '貼文安全選項',
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (report) async {
        if (report) {
          await submitContentReport({
            'kind': item ? 'item' : 'post',
            'target_id': row['id'],
            'community_id': row['community_id'],
          });
        } else if (await confirmSafetyBlock(context, author) && mounted) {
          await saveBlockedMembers({...blockedMembers.value, key: author});
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: true, child: Text(item ? '舉報刊登' : '舉報貼文')),
        const PopupMenuItem(value: false, child: Text('封鎖用戶')),
      ],
    );
  }

  Future<void> openContentSafety() => showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('內容安全'),
      scrollable: true,
      content: ValueListenableBuilder(
        valueListenable: blockedMembers,
        builder: (_, entries, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('請勿發佈騷擾、仇恨、威脅、色情或違法內容。可從貼文或刊登的選單舉報，亦可聯絡管理員。'),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SelectableText('info@aieco.hk'),
            ),
            const Divider(),
            Text(entries.isEmpty ? '尚未封鎖任何刊登者' : '已封鎖的刊登者'),
            for (final entry in entries.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.value),
                trailing: TextButton(
                  onPressed: () => saveBlockedMembers(
                    {...blockedMembers.value}..remove(entry.key),
                  ),
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
}
