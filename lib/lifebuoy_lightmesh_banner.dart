import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class LifebuoyLightMeshBanner extends StatelessWidget {
  const LifebuoyLightMeshBanner({super.key});

  static final googlePlay = Uri.https(
    'play.google.com',
    '/store/apps/details',
    {'id': 'aieco.light.mesh'},
  );
  static final appStore = Uri.https(
    'apps.apple.com',
    '/us/app/傳播光-lightmesh/id6781610489',
  );

  Future<void> openStore(BuildContext context, Uri url) async {
    try {
      if (await launchUrl(url, mode: LaunchMode.externalApplication)) return;
    } on Exception {
      // The platform can reject the request when no external handler exists.
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('暫時無法開啟商店')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = switch (theme.platform) {
      TargetPlatform.android => googlePlay,
      TargetPlatform.iOS => appStore,
      _ => null,
    };
    if (store == null) return const SizedBox.shrink();

    const background = Color(0xff103e36);
    const foreground = Color(0xfff4fcf4);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: background,
        child: SizedBox(
          height: 120,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/images/lifebuoy/lightmesh-download.webp',
                fit: BoxFit.fitHeight,
                alignment: Alignment.centerRight,
                excludeFromSemantics: true,
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [background, background.withValues(alpha: 0)],
                    stops: const [0.06, 0.7],
                  ),
                ),
              ),
              Semantics(
                link: true,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: () => openStore(context, store),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: 0.56,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 14),
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '下載傳播光 APP',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: foreground,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.open_in_new,
                                size: 18,
                                color: foreground,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
