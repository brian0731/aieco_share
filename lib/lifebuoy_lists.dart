part of 'main.dart';

enum _TimeTab { services, entries, members }

const _postKinds = {
  'all': '全部',
  'request': '找支援',
  'offer': '我能幫忙',
  'free': '免費求助',
};

String _signedMinutes(Object? value, {required bool credit}) =>
    '${credit ? '+' : '−'}$value 分鐘';

class _Amount extends StatelessWidget {
  const _Amount(this.text, {required this.credit});

  final String text;
  final bool credit;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.titleSmall?.copyWith(
      color: credit ? const Color(0xff006451) : const Color(0xff96382c),
      fontWeight: FontWeight.w700,
    ),
  );
}

class _ListCard extends StatelessWidget {
  const _ListCard({
    required this.icon,
    required this.title,
    this.label,
    this.details,
    this.action,
    this.tone,
  });

  final IconData icon;
  final String title;
  final String? label;
  final Widget? details;
  final Widget? action;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = tone ?? colors.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SizedBox(
                width: 42,
                height: 42,
                child: Icon(icon, size: 21, color: accent),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (label != null)
                    Text(
                      label!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: accent,
                      ),
                    ),
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (details != null) ...[const SizedBox(height: 5), details!],
                  if (action != null) ...[const SizedBox(height: 6), action!],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension _LifebuoyLists on _LifebuoyHomeState {
  Widget listPage(String key, List<Widget> children) => RefreshIndicator(
    onRefresh: () => run(refresh),
    child: ListView(
      key: PageStorageKey(key),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: children,
    ),
  );

  Widget sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
  );

  Widget emptyList(IconData icon, String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
      ],
    ),
  );

  String shortDate(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '';
    final locale = MaterialLocalizations.of(context);
    return '${locale.formatShortDate(date)} · ${locale.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
  }

  bool matchesPost(String query, Json post) => matchesLifebuoySearch(query, [
    post['title'],
    _districtArea(post),
    post['author'],
    _postKinds[post['kind']],
  ]);

  Widget feed() {
    final query = postSearch.text;
    final posts = list('posts')
        .where((post) => postFilter == 'all' || post['kind'] == postFilter)
        .where((post) => matchesPost(query, post))
        .toList();
    return listPage('help-board', [
      const LifebuoyIllustration(scene: 'community', color: Color(0xffdce9dc)),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(child: sectionTitle('最新貼文')),
          FilledButton.icon(
            onPressed: busy
                ? null
                : account == null
                ? signin
                : showPostComposer,
            icon: Icon(account == null ? Icons.login : Icons.add),
            label: Text(
              account == null
                  ? '登入刊登'
                  : draft == null
                  ? '刊登'
                  : '重送草稿',
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      LifebuoySearchField(
        controller: postSearch,
        label: '搜尋服務、地區或發佈者',
        onChanged: updateSearch,
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final entry in _postKinds.entries)
            ChoiceChip(
              selected: postFilter == entry.key,
              label: Text(entry.value),
              onSelected: (_) => selectPostFilter(entry.key),
            ),
        ],
      ),
      const SizedBox(height: 12),
      if (home case {'fetchedAt': final String date})
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            '更新於 ${shortDate(date)}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      if (posts.isEmpty && !busy)
        emptyList(
          Icons.forum_outlined,
          query.trim().isEmpty ? '目前沒有這類貼文' : '找不到符合條件的貼文',
        ),
      for (final post in posts) postCard(post),
    ]);
  }

  Future<void> showPostComposer() async {
    var submitting = false;
    String? sheetError;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, updateSheet) {
          Future<void> submit() async {
            if (submitting) return;
            updateSheet(() => submitting = true);
            await run(publish);
            if (!sheet.mounted) return;
            if (error == null) {
              Navigator.of(sheet).pop();
            } else {
              updateSheet(() {
                sheetError = error;
                submitting = false;
              });
            }
          }

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              20 + MediaQuery.viewInsetsOf(sheet).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                sectionTitle(draft == null ? '刊登貼文' : '待重送草稿'),
                DropdownButtonFormField<String>(
                  key: ValueKey(kind),
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: '刊登類別'),
                  items: [
                    for (final key in ['request', 'offer', 'free'])
                      DropdownMenuItem(
                        value: key,
                        child: Text(_postKinds[key]!),
                      ),
                  ],
                  onChanged: draft != null || submitting
                      ? null
                      : (value) {
                          updateSheet(() => kind = value!);
                        },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: title,
                  readOnly: draft != null || submitting,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: '標題'),
                ),
                TextField(
                  controller: area,
                  readOnly: draft != null || submitting,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: '大致區域'),
                ),
                if (kind != 'free')
                  TextField(
                    controller: duration,
                    readOnly: draft != null || submitting,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: kind == 'request' ? '支出分鐘' : '收取分鐘',
                    ),
                  ),
                if (sheetError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      sheetError!,
                      style: TextStyle(
                        color: Theme.of(sheet).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: submitting ? null : submit,
                  child: Text(draft == null ? '發布貼文' : '重送草稿'),
                ),
                if (draft != null)
                  TextButton(
                    onPressed: submitting
                        ? null
                        : () async {
                            await run(discardDraft);
                            if (sheet.mounted) {
                              updateSheet(() => sheetError = error);
                            }
                          },
                    child: const Text('放棄草稿'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget postCard(Json post) {
    final type = post['kind'];
    final isRequest = type == 'request';
    final free = type == 'free';
    final mine = account?['id'] == post['author_id'];
    final matched = post['matched'] == 1 || post['matched'] == true;
    final earns = mine ? !isRequest : isRequest;
    return _ListCard(
      icon: free
          ? Icons.favorite_outline
          : isRequest
          ? Icons.support_agent_outlined
          : Icons.volunteer_activism_outlined,
      tone: free ? const Color(0xff705923) : null,
      label:
          '${_postKinds[type] ?? '社區貼文'}${matched
              ? ' · 已配對'
              : mine
              ? ' · 我的貼文'
              : ''}',
      title: post['title'].toString(),
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_districtArea(post)} · ${post['author']}'),
          const SizedBox(height: 4),
          if (free)
            const Text('免費')
          else
            _Amount(
              '${earns ? '提供協助可收取' : '獲得支援需支付'} ${post['minutes']} 分鐘',
              credit: earns,
            ),
        ],
      ),
      action: free || mine || matched
          ? null
          : OutlinedButton(
              onPressed: busy
                  ? null
                  : account == null
                  ? signin
                  : () => run(() => mutate('posts/${post['id']}/match', {})),
              child: Text(isRequest ? '提供協助' : '請求支援'),
            ),
    );
  }

  Widget timeBank() {
    final signedIn = account != null;
    final theme = Theme.of(context);
    final balance = account?['balance'];
    const panelText = Color(0xff123c34);
    final query = timeSearch.text;
    final searching = query.trim().isNotEmpty;
    final publicServices = signedIn
        ? const <Json>[]
        : list('posts')
              .where(
                (post) => post['kind'] != 'free' && matchesPost(query, post),
              )
              .toList();
    final matchingServices = list('services')
        .where((service) => matchesLifebuoySearch(query, [service['title']]))
        .toList();
    final entries = list('entries')
        .where(
          (entry) =>
              matchesLifebuoySearch(query, [entry['title'], entryLabel(entry)]),
        )
        .toList();
    final members = list('members')
        .where((member) => matchesLifebuoySearch(query, [member['name']]))
        .toList();
    return listPage('time-bank', [
      LifebuoyIllustration(
        scene: 'time',
        color: const Color(0xffe0eee1),
        height: 108,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.schedule, color: panelText, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    signedIn ? '可用時間' : '起始額度',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: panelText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${signedIn ? balance : 60} 分鐘',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: panelText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (signedIn && balance == 0)
                Text('目前沒有可支出的時間', style: TextStyle(color: panelText)),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 16,
        runSpacing: 4,
        children: const [
          _Amount('+ 提供協助', credit: true),
          _Amount('− 獲得支援', credit: false),
        ],
      ),
      const SizedBox(height: 16),
      if (!signedIn) ...[
        OutlinedButton.icon(
          onPressed: busy ? null : signin,
          icon: const Icon(Icons.login),
          label: const Text('登入查看帳本'),
        ),
        const SizedBox(height: 14),
      ] else ...[
        SegmentedButton<_TimeTab>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: _TimeTab.services, label: Text('我的服務')),
            ButtonSegment(value: _TimeTab.entries, label: Text('收支明細')),
            ButtonSegment(value: _TimeTab.members, label: Text('成員')),
          ],
          selected: {timeTab},
          onSelectionChanged: (value) => selectTimeTab(value.single),
        ),
        const SizedBox(height: 14),
      ],
      LifebuoySearchField(
        controller: timeSearch,
        label: !signedIn
            ? '搜尋公開服務'
            : switch (timeTab) {
                _TimeTab.services => '搜尋我的服務',
                _TimeTab.entries => '搜尋收支明細',
                _TimeTab.members => '搜尋成員',
              },
        onChanged: updateSearch,
      ),
      const SizedBox(height: 12),
      if (!signedIn) ...[
        if (publicServices.isEmpty && !busy)
          emptyList(
            Icons.assignment_outlined,
            searching ? '找不到符合的服務' : '暫無公開服務',
          ),
        for (final post in publicServices) postCard(post),
      ] else ...[
        ...switch (timeTab) {
          _TimeTab.services => [
            if (matchingServices.isEmpty)
              emptyList(
                Icons.assignment_outlined,
                searching ? '找不到符合的服務' : '暫無已配對服務',
              ),
            for (final service in matchingServices) serviceCard(service),
          ],
          _TimeTab.entries => [
            if (entries.isEmpty)
              emptyList(
                Icons.receipt_long_outlined,
                searching ? '找不到符合的收支明細' : '暫無入帳紀錄',
              ),
            for (final entry in entries) entryCard(entry),
          ],
          _TimeTab.members => [
            if (members.isEmpty)
              emptyList(Icons.people_outline, searching ? '找不到符合的成員' : '暫無成員'),
            for (final member in members)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(member['name'].toString()),
                trailing: const Icon(Icons.chevron_right),
                onTap: busy ? null : () => run(() => showReputation(member)),
              ),
          ],
        },
      ],
    ]);
  }

  String entryLabel(Json entry) => switch (entry['kind']) {
    'opening_credit' => '起始額度',
    'reversal' => '帳目更正',
    _ => (entry['delta'] as int) > 0 ? '服務收入' : '服務支出',
  };

  Widget entryCard(Json entry) {
    final delta = entry['delta'] as int;
    final credit = delta > 0;
    final label = entryLabel(entry);
    final title = entry['title'] as String?;
    return _ListCard(
      icon: credit ? Icons.south_west : Icons.north_east,
      label: title == null ? null : label,
      title: title ?? label,
      details: Text(shortDate(entry['created_at'])),
      action: _Amount(
        _signedMinutes(delta.abs(), credit: credit),
        credit: credit,
      ),
    );
  }

  Widget serviceCard(Json service) {
    final payer = service['payer_id'] == account?['id'];
    final side = payer ? 'payer' : 'provider';
    final other = payer ? 'provider' : 'payer';
    final state = service['state'];
    final step = state == 'agreement' ? 'agreed' : 'confirmed';
    final mine =
        service['${side}_$step'] == 1 || service['${side}_$step'] == true;
    final theirs =
        service['${other}_$step'] == 1 || service['${other}_$step'] == true;
    final pending = state == 'agreement' || state == 'pending';
    final action = pending && !mine
        ? (state == 'agreement' ? 'agree' : 'confirm')
        : null;
    final status = switch (state) {
      'agreement' => mine ? '等對方同意時間' : '待你同意時間',
      'pending' => mine ? '等對方確認完成' : '待你確認完成',
      'settled' => '已入帳',
      'reversed' => '已更正',
      _ => '已取消',
    };
    final amount = _signedMinutes(service['minutes'], credit: !payer);
    return _ListCard(
      icon: payer ? Icons.north_east : Icons.south_west,
      label: '${payer ? '找支援' : '提供協助'} · $status',
      title: service['title'].toString(),
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state == 'cancelled' || state == 'reversed')
            Text('原定 $amount')
          else
            _Amount(pending ? '預計 $amount' : amount, credit: !payer),
          if (pending)
            Text('你${mine ? '已' : '未'}確認 · 對方${theirs ? '已' : '未'}確認'),
        ],
      ),
      action: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (action != null)
            FilledButton.tonal(
              onPressed: busy
                  ? null
                  : () => run(
                      () => mutate('services/${service['id']}/$action', {
                        'minutes': service['minutes'],
                      }),
                    ),
              child: Text(action == 'agree' ? '同意時數' : '確認完成'),
            ),
          tradeActions('services', service),
        ],
      ),
    );
  }
}
