part of 'main.dart';

extension _ExchangePages on _LifebuoyHomeState {
  Future<List<String>?> fields(String heading, List<String> labels) async {
    final form = GlobalKey<FormState>();
    final values = List.filled(labels.length, '');
    return showDialog<List<String>>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(heading),
        content: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < labels.length; i++)
                  TextFormField(
                    decoration: InputDecoration(labelText: labels[i]),
                    validator: (value) =>
                        value == null || value.trim().isEmpty ? '請填寫' : null,
                    onSaved: (value) => values[i] = value!.trim(),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              form.currentState!.save();
              Navigator.pop(dialog, values);
            },
            child: const Text('送出'),
          ),
        ],
      ),
    );
  }

  Future<void> addItem() async {
    final values = await fields('刊登物品', ['我有', '我需要', '大致區域']);
    if (values == null || !mounted) return;
    await run(
      () => mutate('items', {
        'id': newId(),
        'title': values[0],
        'wanted': values[1],
        'area': values[2],
      }),
    );
  }

  Future<void> propose(Json wanted) async {
    final items = list('items')
        .where(
          (item) => item['owner_id'] == account?['id'] && !_isReserved(item),
        )
        .toList();
    final form = GlobalKey<FormState>();
    Json? offered = items.firstOrNull;
    var meeting = '';
    final send = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('交換 ${wanted['title']}'),
        scrollable: true,
        content: items.isEmpty
            ? const Text('請先刊登要提供的物品。')
            : Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<Json>(
                      initialValue: offered,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '我提供的物品'),
                      items: [
                        for (final item in items)
                          DropdownMenuItem(
                            value: item,
                            child: Text(
                              item['title'].toString(),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (item) => offered = item,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      decoration: const InputDecoration(labelText: '公共交收地點與時間'),
                      validator: (text) => text == null || text.trim().isEmpty
                          ? '請填寫交收地點與時間'
                          : null,
                      onSaved: (text) => meeting = text!.trim(),
                    ),
                  ],
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(items.isEmpty ? '關閉' : '取消'),
          ),
          if (items.isNotEmpty)
            FilledButton(
              onPressed: () {
                if (!form.currentState!.validate()) return;
                form.currentState!.save();
                Navigator.pop(dialog, true);
              },
              child: const Text('送出交換提案'),
            ),
        ],
      ),
    );
    if (send != true || offered == null || !mounted) return;
    await run(
      () => mutate('exchanges', {
        'id': newId(),
        'offered': offered!['id'],
        'wanted': wanted['id'],
        'meeting': meeting,
      }),
    );
  }

  bool _isReserved(Json item) =>
      item['reserved'] == 1 || item['reserved'] == true;

  Widget exchangeBoard() {
    final query = exchangeSearch.text;
    final searching = query.trim().isNotEmpty;
    final items = list('items')
        .where(
          (item) => matchesLifebuoySearch(query, [
            item['title'],
            item['wanted'],
            _districtArea(item),
          ]),
        )
        .toList();
    final exchanges = list('exchanges')
        .where(
          (exchange) => matchesLifebuoySearch(query, [
            exchange['offered_title'],
            exchange['wanted_title'],
            exchange['meeting'],
          ]),
        )
        .toList();
    return listPage('exchange-board', [
      const LifebuoyIllustration(scene: 'exchange', color: Color(0xfff2dfca)),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(child: sectionTitle('物品交換')),
          FilledButton.icon(
            onPressed: busy
                ? null
                : account == null
                ? signin
                : addItem,
            icon: const Icon(Icons.add),
            label: const Text('刊登物品'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      LifebuoySearchField(
        controller: exchangeSearch,
        label: '搜尋物品、地區或交收地點',
        onChanged: updateSearch,
      ),
      const SizedBox(height: 12),
      if (account == null) publicBoardStatus(),
      if (items.isEmpty && !busy && home != null)
        emptyList(
          Icons.inventory_2_outlined,
          searching ? '找不到符合的物品' : '目前沒有可瀏覽的物品',
        ),
      for (final item in items)
        _ListCard(
          icon: Icons.inventory_2_outlined,
          title: item['title'].toString(),
          menu: item['owner_id'] == account?['id']
              ? null
              : listingSafetyMenu(item, item: true),
          label: _isReserved(item)
              ? '已保留'
              : item['owner_id'] == account?['id']
              ? '我的物品'
              : '可交換',
          details: Text('想換 ${item['wanted']} · ${_districtArea(item)}'),
          action: _isReserved(item) || item['owner_id'] == account?['id']
              ? null
              : FilledButton.tonalIcon(
                  onPressed: busy
                      ? null
                      : account == null
                      ? signin
                      : () => propose(item),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('提出交換'),
                ),
        ),
      if (account != null) ...[
        const SizedBox(height: 16),
        sectionTitle('我的交換'),
        if (exchanges.isEmpty)
          emptyList(Icons.swap_horiz, searching ? '找不到符合的交換提案' : '暫無交換提案'),
      ],
      for (final exchange in exchanges) ...[
        _ListCard(
          icon: Icons.swap_horiz,
          title: '${exchange['offered_title']} ⇄ ${exchange['wanted_title']}',
          label: switch (exchange['state']) {
            'proposed' => '待接受',
            'reserved' when exchange['expired'] == 1 => '保留已到期',
            'reserved' =>
              '待交收（${exchange['proposer_confirmed'] + exchange['owner_confirmed']}／2 已確認）',
            'completed' => '已完成',
            _ => '已取消',
          },
          details: Text(exchange['meeting'].toString()),
          action: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (exchange['state'] == 'proposed' ||
                  exchange['state'] == 'reserved')
                _CardActions(
                  secondary: exchangeAction(exchange, 'cancel', '取消交換'),
                  primary:
                      exchange['state'] == 'proposed' &&
                          exchange['owner_id'] == account?['id']
                      ? exchangeAction(exchange, 'accept', '接受交換')
                      : exchange['state'] == 'reserved' &&
                            exchange['expired'] != 1 &&
                            exchange['expired'] != true &&
                            exchange[exchange['owner_id'] == account?['id']
                                    ? 'owner_confirmed'
                                    : 'proposer_confirmed'] ==
                                0
                      ? exchangeAction(exchange, 'handoff', '確認交收')
                      : null,
                ),
              tradeActions('exchanges', exchange),
            ],
          ),
        ),
      ],
    ]);
  }

  Widget exchangeAction(Json exchange, String action, String label) {
    final press = busy
        ? null
        : () => run(() => mutate('exchanges/${exchange['id']}/$action', {}));
    return action == 'cancel'
        ? OutlinedButton(onPressed: press, child: Text(label))
        : FilledButton(onPressed: press, child: Text(label));
  }

  Widget tradeActions(String resource, Json trade) {
    final kind = resource == 'services' ? 'service' : 'exchange';
    final id = trade['id'];
    final dispute = list(
      'disputes',
    ).where((d) => d['kind'] == kind && d['trade_id'] == id).firstOrNull;
    final rating = list(
      'ratings',
    ).where((r) => r['kind'] == kind && r['trade_id'] == id).firstOrNull;
    final completed =
        trade['state'] == (kind == 'service' ? 'settled' : 'completed');
    final expires = DateTime.tryParse(
      trade['completed_at']?.toString() ?? '',
    )?.add(const Duration(days: 7));
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        if (rating != null)
          Text.rich(
            TextSpan(
              children: [
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Icon(
                    Icons.star_rounded,
                    size: 17,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                TextSpan(text: ' 我的評分 ${rating['stars']}／5'),
              ],
            ),
          ),
        if (rating == null &&
            completed &&
            expires != null &&
            DateTime.now().isBefore(expires) &&
            (dispute == null || dispute['outcome'] != null))
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    final stars = await showDialog<int>(
                      context: context,
                      builder: (_) => const LifebuoyRatingDialog(),
                    );
                    if (stars != null && mounted) {
                      await run(
                        () => mutate('$resource/$id/rate', {'stars': stars}),
                      );
                    }
                  },
            child: const Text('評分'),
          ),
        if (dispute != null)
          Text(switch (dispute['outcome']) {
            'restore' => '申訴已處理，評價恢復 · ${dispute['resolution_reason']}',
            'exclude' => '申訴已處理，評價排除 · ${dispute['resolution_reason']}',
            _ => '申訴處理中',
          })
        else if (trade['state'] != 'cancelled' && trade['state'] != 'reversed')
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    final reason = await fields('提出申訴', ['原因']);
                    if (reason != null && mounted) {
                      await run(
                        () => mutate('$resource/$id/dispute', {
                          'reason': reason.single,
                        }),
                      );
                    }
                  },
            child: const Text('申訴'),
          ),
      ],
    );
  }

  Future<void> showReputation(Json member) async {
    final profile = await api(
      'members/${Uri.encodeComponent(member['id'].toString())}',
    );
    if (!mounted) return;
    final count = profile['count'];
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(profile['name'].toString()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            memberRating(profile),
            const SizedBox(height: 8),
            Text('$count 則評價'),
          ],
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

  Widget memberRating(Json member) {
    final score = member['score'] as num?;
    final completed = member['completed_count'];
    final rating = score == null
        ? (member.containsKey('score') ? '評分資料不足' : '暫未提供評分')
        : '${(score * 20).toStringAsFixed(2)}／100';
    final colors = Theme.of(context).colorScheme;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        Text.rich(
          TextSpan(
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(
                  score == null
                      ? Icons.star_outline_rounded
                      : Icons.star_rounded,
                  size: 18,
                  color: score == null
                      ? colors.onSurfaceVariant
                      : colors.primary,
                ),
              ),
              TextSpan(text: ' $rating'),
            ],
          ),
        ),
        if (completed != null) Text('互助 $completed 次'),
      ],
    );
  }
}
