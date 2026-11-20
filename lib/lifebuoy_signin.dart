part of 'main.dart';

class _AccountPage extends StatefulWidget {
  const _AccountPage({required this.api, this.biometricLogin});

  final Future<Json> Function(String path, [Json? data]) api;
  final Future<String?> Function()? biometricLogin;

  @override
  State<_AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<_AccountPage> {
  final form = GlobalKey<FormState>();
  final username = TextEditingController();
  final password = TextEditingController();
  final confirmation = TextEditingController();
  final name = TextEditingController();
  bool registering = false;
  bool obscurePassword = true;
  bool busy = false;
  String? districtId;
  String? error;

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    confirmation.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> unlock() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final token = await widget.biometricLogin!();
      if (mounted && token != null) Navigator.pop(context, token);
    } on FormatException catch (problem) {
      if (mounted) setState(() => error = problem.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      error = null;
      busy = true;
    });
    try {
      final result = await widget
          .api(registering ? 'auth/register' : 'auth/login', {
            'username': username.text.trim(),
            'password': password.text,
            if (registering) 'name': name.text.trim(),
            if (registering) 'community_id': districtId!,
          });
      if (mounted) {
        TextInput.finishAutofillContext();
        Navigator.pop(context, result['token'] as String);
      }
    } catch (problem) {
      if (mounted) {
        setState(() {
          error = problem is FormatException ? problem.message : '無法連線，請稍後再試';
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final action = registering ? '註冊' : '登入';
    return Scaffold(
      appBar: AppBar(title: Text(action)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: AutofillGroup(
              onDisposeAction: AutofillContextAction.cancel,
              child: Form(
                key: form,
                child: ListView(
                  shrinkWrap: true,
                  scrollCacheExtent: const ScrollCacheExtent.pixels(600),
                  padding: const EdgeInsets.all(24),
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: LifebuoyIllustration(
                        scene: 'login',
                        color: Theme.of(context).colorScheme.surfaceContainer,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (registering) ...[
                      TextFormField(
                        controller: name,
                        enabled: !busy,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: '顯示名稱'),
                        validator: (value) {
                          final length = value?.trim().length ?? 0;
                          return length >= 1 && length <= 100
                              ? null
                              : '請輸入顯示名稱';
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: districtId,
                        isExpanded: true,
                        menuMaxHeight: 360,
                        decoration: const InputDecoration(
                          labelText: '香港地區（必選）',
                        ),
                        hint: const Text('請選擇十八區之一'),
                        items: [
                          for (final district in _districtNames.entries)
                            DropdownMenuItem(
                              value: district.key,
                              child: Text(district.value),
                            ),
                        ],
                        onChanged: busy ? null : (value) => districtId = value,
                        validator: (value) => value == null ? '請選擇香港地區' : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: username,
                      enabled: !busy,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: '使用者名稱'),
                      validator: (value) {
                        return RegExp(
                              r'^[a-zA-Z0-9_]{3,32}$',
                            ).hasMatch(value?.trim() ?? '')
                            ? null
                            : '請輸入 3 至 32 個英文字母、數字或底線';
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: password,
                      enabled: !busy,
                      obscureText: obscurePassword,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: [
                        registering
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      textInputAction: registering
                          ? TextInputAction.next
                          : TextInputAction.done,
                      onFieldSubmitted: registering ? null : (_) => submit(),
                      decoration: InputDecoration(
                        labelText: '密碼',
                        suffixIcon: IconButton(
                          tooltip: obscurePassword ? '顯示密碼' : '隱藏密碼',
                          onPressed: () => setState(
                            () => obscurePassword = !obscurePassword,
                          ),
                          icon: Icon(
                            obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) {
                        final text = value ?? '';
                        if (text.isEmpty) return '請輸入密碼';
                        if (registering &&
                            (text.length < 12 ||
                                utf8.encode(text).length > 256)) {
                          return '請使用至少 12 個字元的密碼';
                        }
                        return null;
                      },
                    ),
                    if (registering) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: confirmation,
                        enabled: !busy,
                        obscureText: obscurePassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => submit(),
                        decoration: const InputDecoration(labelText: '確認密碼'),
                        validator: (value) {
                          if (value == null || value.isEmpty) return '請再次輸入密碼';
                          return value == password.text ? null : '兩次輸入的密碼不一致';
                        },
                      ),
                    ],
                    if (error case final String message)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          message,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: busy ? null : submit,
                      child: Text(action),
                    ),
                    if (!registering && widget.biometricLogin != null)
                      OutlinedButton.icon(
                        onPressed: busy ? null : unlock,
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('指紋／生物認證登入'),
                      ),
                    if (busy) const LinearProgressIndicator(),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () {
                              form.currentState?.reset();
                              password.clear();
                              confirmation.clear();
                              setState(() {
                                registering = !registering;
                                districtId = null;
                                obscurePassword = true;
                                error = null;
                              });
                            },
                      child: Text(registering ? '已有帳號？登入' : '建立帳號'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
