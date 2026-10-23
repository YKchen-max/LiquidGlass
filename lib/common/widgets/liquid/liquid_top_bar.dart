// SPDX-License-Identifier: GPL-3.0-or-later
//
// 顶栏（UIdraft 线框①②顶部：搜索栏 + 通知 + 头像）。
// UI 重构暂存组件（排期 #23）：暂不编译、不接入；接入时 searchHint/回调接 pages/search。
import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';

class LiquidTopBar extends StatelessWidget {
  const LiquidTopBar({
    super.key,
    this.searchHint = '搜索bilibili',
    this.onSearchTap,
    this.onNotificationTap,
    this.onAvatarTap,
  });

  final String searchHint;
  final VoidCallback? onSearchTap;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: LiquidGlassSurface(
        material: LiquidGlassMaterial.regular,
        borderRadius: BorderRadius.circular(26),
        shadow: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: <Widget>[
              // 搜索胶囊（假输入框）
              Expanded(
                child: Semantics(
                  button: true,
                  label: '搜索：$searchHint',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onSearchTap,
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(19),
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: <Widget>[
                          Icon(LiquidIcons.search, size: 20, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              searchHint,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontFamily: LiquidFontFamily.text,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _TopBarIconButton(
                icon: LiquidIcons.notifications,
                tooltip: '通知',
                onTap: onNotificationTap,
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: '我的头像',
                child: GestureDetector(
                  onTap: onAvatarTap,
                  // 暂存期头像为占位圆；接入时换用户真实头像（cached_network_image）
                  child: CircleAvatar(
                    radius: 17,
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(LiquidIcons.profile, size: 18, color: scheme.onPrimaryContainer),
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

class _TopBarIconButton extends StatelessWidget {
  const _TopBarIconButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: tooltip,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, size: 22, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
